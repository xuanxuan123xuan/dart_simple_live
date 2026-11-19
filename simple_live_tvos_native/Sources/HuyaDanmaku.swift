import Foundation
import SimpleLiveTVOSCore

enum HuyaDanmaku {
    static func join(uid: Int64, channel: Int64, subchannel: Int64) -> Data {
        var user = TarsWriter()
        user.number(0, uid)
        user.number(1, 1)
        user.text(2, "")
        user.text(3, "")
        user.number(4, channel)
        user.number(5, subchannel)
        user.number(6, 0)
        user.number(7, 0)
        var command = TarsWriter()
        command.number(0, 1)
        command.bytes(1, user.data)
        return command.data
    }

    static func decode(_ frame: Data, roomID: String) throws -> DanmakuEvent? {
        var command = TarsReader(frame)
        let commandFields = try command.fields()
        guard commandFields[0]?.number == 7, let payload = commandFields[1]?.bytes else { return nil }
        var push = TarsReader(payload)
        let fields = try push.fields()
        guard fields[1]?.number == 1400, let data = fields[2]?.bytes else { return nil }
        var notice = TarsReader(data)
        let message = try notice.fields()
        guard let content = message[3]?.text, !content.isEmpty else { return nil }
        let nickname = message[0]?.structure?[2]?.text ?? ""
        let rawColor = message[6]?.structure?[0]?.number ?? 0
        let color = rawColor > 0 ? rawColor : 0xffffff
        return DanmakuEvent(id: UUID().uuidString, room: RoomKey(provider: .huya, roomId: roomID),
            userName: nickname, message: content,
            color: DanmakuColor(red: Int((color >> 16) & 255), green: Int((color >> 8) & 255), blue: Int(color & 255)),
            spans: DanmakuEmoji.huya(content))
    }
}

private struct TarsWriter {
    private(set) var data = Data()

    mutating func number(_ tag: UInt8, _ value: Int64) {
        if value == 0 {
            data.append(tag << 4 | 12)
        } else if let byte = Int8(exactly: value) {
            data.append(tag << 4)
            data.append(UInt8(bitPattern: byte))
        } else if let short = Int16(exactly: value) {
            data.append(tag << 4 | 1)
            append(short)
        } else if let int = Int32(exactly: value) {
            data.append(tag << 4 | 2)
            append(int)
        } else {
            data.append(tag << 4 | 3)
            append(value)
        }
    }

    mutating func text(_ tag: UInt8, _ value: String) {
        data.append(tag << 4 | 6)
        data.append(UInt8(value.utf8.count))
        data.append(contentsOf: value.utf8)
    }

    mutating func bytes(_ tag: UInt8, _ payload: Data) {
        data.append(tag << 4 | 13)
        data.append(0)
        number(0, Int64(payload.count))
        data.append(payload)
    }

    private mutating func append<T: FixedWidthInteger>(_ value: T) {
        var bytes = value.bigEndian
        withUnsafeBytes(of: &bytes) { data.append(contentsOf: $0) }
    }
}

private indirect enum TarsValue {
    case int(Int64), blob(Data), string(String), fields([Int: TarsValue]), skipped

    var number: Int64? { if case let .int(value) = self { value } else { nil } }
    var bytes: Data? { if case let .blob(value) = self { value } else { nil } }
    var text: String? { if case let .string(value) = self { value } else { nil } }
    var structure: [Int: TarsValue]? { if case let .fields(value) = self { value } else { nil } }
}

private struct TarsReader {
    private let bytes: [UInt8]
    private var index = 0
    private var budget = 16_384

    init(_ data: Data) { bytes = Array(data) }

    mutating func fields(_ depth: Int = 0, nested: Bool = false) throws -> [Int: TarsValue] {
        guard depth < 12 else { throw LiveProviderError.invalidResponse }
        var result: [Int: TarsValue] = [:]
        while index < bytes.count {
            let (tag, type) = try header()
            if type == 11 {
                guard nested else { throw LiveProviderError.invalidResponse }
                return result
            }
            result[tag] = try value(type, depth: depth)
        }
        if nested { throw LiveProviderError.invalidResponse }
        return result
    }

    private mutating func header() throws -> (Int, UInt8) {
        guard budget > 0 else { throw LiveProviderError.invalidResponse }
        budget -= 1
        let byte = try take(1).first ?? 0
        let tag = byte >> 4
        return (tag == 15 ? Int(try take(1).first ?? 0) : Int(tag), byte & 15)
    }

    private mutating func value(_ type: UInt8, depth: Int) throws -> TarsValue {
        guard depth < 12 else { throw LiveProviderError.invalidResponse }
        switch type {
        case 0: return .int(Int64(Int8(bitPattern: UInt8(try unsigned(1)))))
        case 1: return .int(Int64(Int16(bitPattern: UInt16(try unsigned(2)))))
        case 2: return .int(Int64(Int32(bitPattern: UInt32(try unsigned(4)))))
        case 3: return .int(Int64(bitPattern: try unsigned(8)))
        case 4, 5:
            _ = try take(type == 4 ? 4 : 8)
            return .skipped
        case 6, 7:
            let length = Int(try unsigned(type == 6 ? 1 : 4))
            return .string(String(decoding: try take(length), as: UTF8.self))
        case 8, 9:
            let items = try length(depth)
            guard items <= 8192 else { throw LiveProviderError.invalidResponse }
            for _ in 0..<(type == 8 ? items * 2 : items) {
                _ = try value(header().1, depth: depth + 1)
            }
            return .skipped
        case 10: return .fields(try fields(depth + 1, nested: true))
        case 12: return .int(0)
        case 13:
            guard try header().1 == 0 else { throw LiveProviderError.invalidResponse }
            let count = try length(depth)
            return .blob(Data(try take(count)))
        default: throw LiveProviderError.invalidResponse
        }
    }

    private mutating func length(_ depth: Int) throws -> Int {
        let type = try header().1
        guard let value = try value(type, depth: depth + 1).number, value >= 0, value <= Int64(bytes.count - index) else {
            throw LiveProviderError.invalidResponse
        }
        return Int(value)
    }

    private mutating func unsigned(_ count: Int) throws -> UInt64 {
        try take(count).reduce(0) { $0 << 8 | UInt64($1) }
    }

    private mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, count <= bytes.count - index else { throw LiveProviderError.invalidResponse }
        let end = index + count
        defer { index = end }
        return bytes[index..<end]
    }
}
