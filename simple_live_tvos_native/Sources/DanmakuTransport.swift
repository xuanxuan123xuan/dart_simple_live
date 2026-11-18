import Foundation
import SimpleLiveTVOSCore
import zlib

typealias DanmakuContinuation = AsyncThrowingStream<DanmakuEvent, Error>.Continuation

struct DanmakuConnection {
    let request: URLRequest
    let initialFrames: [Data]
    let heartbeatInterval: Duration
    let heartbeat: () -> Data
    let decode: (Data) throws -> (events: [DanmakuEvent], reply: Data?)

    static func stream(connect: @escaping @Sendable () async throws -> DanmakuConnection) -> AsyncThrowingStream<DanmakuEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
            let task = Task {
                for attempt in 0..<3 {
                    do {
                        try Task.checkCancellation()
                        let connection = try await connect()
                        try await connection.consume(continuation)
                        continuation.finish()
                        return
                    } catch {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        if attempt == 2 {
                            continuation.finish(throwing: error)
                            return
                        }
                        do { try await Task.sleep(for: .seconds(2 << attempt)) }
                        catch { continuation.finish(); return }
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func consume(_ continuation: DanmakuContinuation) async throws {
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.maximumMessageSize = 4 * 1024 * 1024
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        try await withTaskCancellationHandler {
            for frame in initialFrames { try await socket.send(.data(frame)) }
            let heartbeat = Task {
                do {
                    while !Task.isCancelled {
                        try await socket.send(.data(self.heartbeat()))
                        try await Task.sleep(for: heartbeatInterval)
                    }
                } catch {
                    if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
                }
            }
            defer { heartbeat.cancel() }
            while !Task.isCancelled {
                guard case let .data(frame) = try await socket.receive() else { continue }
                let result = try decode(frame)
                if let reply = result.reply { try await socket.send(.data(reply)) }
                for event in result.events { continuation.yield(event) }
            }
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }
}

enum DanmakuCompression {
    static func inflate(_ bytes: Data) throws -> Data {
        guard !bytes.isEmpty, bytes.count <= 4 * 1024 * 1024 else { throw LiveProviderError.invalidResponse }
        var stream = z_stream()
        // Auto-detect gzip or zlib wrapping and verify its checksum.
        guard inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw LiveProviderError.invalidResponse
        }
        defer { inflateEnd(&stream) }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        return try bytes.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = UInt32(bytes.count)
            while true {
                let (result, written) = buffer.withUnsafeMutableBufferPointer { chunk in
                    stream.next_out = chunk.baseAddress
                    stream.avail_out = UInt32(chunk.count)
                    let result = zlib.inflate(&stream, Z_NO_FLUSH)
                    return (result, chunk.count - Int(stream.avail_out))
                }
                guard output.count + written <= 4 * 1024 * 1024 else { throw LiveProviderError.invalidResponse }
                output.append(contentsOf: buffer.prefix(written))
                if result == Z_STREAM_END { return output }
                guard result == Z_OK, written > 0 else { throw LiveProviderError.invalidResponse }
            }
        }
    }
}

struct ProtoMessage {
    private enum Value {
        case integer(UInt64)
        case bytes(Data)
    }

    private var fields: [Int: [Value]] = [:]

    init(_ data: Data) throws {
        guard data.count <= 4 * 1024 * 1024 else { throw LiveProviderError.invalidResponse }
        let bytes = Array(data)
        var index = 0
        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard index < bytes.count else { throw LiveProviderError.invalidResponse }
                let value = bytes[index]
                index += 1
                guard shift != 63 || value <= 1 else { throw LiveProviderError.invalidResponse }
                result |= UInt64(value & 127) << shift
                if value < 128 { return result }
            }
            throw LiveProviderError.invalidResponse
        }
        var count = 0
        while index < bytes.count {
            count += 1
            let tag = try varint()
            guard (1...536870911).contains(tag >> 3), count <= 8192 else { throw LiveProviderError.invalidResponse }
            let field = Int(tag >> 3)
            switch tag & 7 {
            case 0:
                fields[field, default: []].append(.integer(try varint()))
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count - index) else { throw LiveProviderError.invalidResponse }
                let end = index + Int(length)
                fields[field, default: []].append(.bytes(Data(bytes[index..<end])))
                index = end
            case 1, 5:
                let length = tag & 7 == 1 ? 8 : 4
                guard bytes.count - index >= length else { throw LiveProviderError.invalidResponse }
                index += length
            default: throw LiveProviderError.invalidResponse
            }
        }
    }

    func number(_ field: Int) -> UInt64 {
        if case let .integer(value) = fields[field]?.last { return value }
        return 0
    }

    func data(_ field: Int) -> Data { values(field).last ?? Data() }

    func values(_ field: Int) -> [Data] {
        (fields[field] ?? []).compactMap { if case let .bytes(value) = $0 { value } else { nil } }
    }

    func text(_ field: Int) -> String { String(decoding: data(field), as: UTF8.self) }
}

struct ProtoWriter {
    private(set) var data = Data()

    mutating func number(_ field: Int, _ value: UInt64) {
        varint(UInt64(field << 3))
        varint(value)
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        varint(UInt64(field << 3 | 2))
        varint(UInt64(value.count))
        data.append(value)
    }

    mutating func text(_ field: Int, _ value: String) {
        if !value.isEmpty { bytes(field, Data(value.utf8)) }
    }

    private mutating func varint(_ value: UInt64) {
        var value = value
        while value >= 128 {
            data.append(UInt8(value & 127) | 128)
            value >>= 7
        }
        data.append(UInt8(value))
    }
}
