import Combine
import Darwin
import Foundation
import Network

struct LANSyncRequest {
    let method: String
    let path: String
    let query: [String: String]
    let body: Data

    static func parse(_ data: Data) throws -> Self? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > 8192 { throw SyncError.invalidProfile }
            return nil
        }
        guard headerEnd.lowerBound <= 8192,
              let header = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else {
            throw SyncError.invalidProfile
        }
        let lines = header.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ")
        guard start.count == 3, ["HTTP/1.1", "HTTP/1.0"].contains(start[2]),
              start[1].hasPrefix("/"), !start[1].hasPrefix("//"),
              let target = URLComponents(string: String(start[1])), target.fragment == nil else {
            throw SyncError.invalidProfile
        }
        var length: Int?
        for line in lines.dropFirst() {
            let fields = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { throw SyncError.invalidProfile }
            switch fields[0].lowercased() {
            case "transfer-encoding": throw SyncError.invalidProfile
            case "content-length":
                guard length == nil, let value = Int(fields[1].trimmingCharacters(in: .whitespaces)),
                      value >= 0 else { throw SyncError.invalidProfile }
                guard value <= SyncProfile.maxBytes else { throw SyncError.tooLarge }
                length = value
            default: continue
            }
        }
        let bodyStart = headerEnd.upperBound
        let bodyEnd = bodyStart + (length ?? 0)
        guard data.count >= bodyEnd else { return nil }
        guard data.count == bodyEnd else { throw SyncError.invalidProfile }
        var query: [String: String] = [:]
        for item in target.queryItems ?? [] {
            guard let value = item.value, query[item.name] == nil else { throw SyncError.invalidProfile }
            query[item.name] = value
        }
        return Self(method: String(start[0]), path: target.path, query: query, body: Data(data[bodyStart..<bodyEnd]))
    }
}

@MainActor
final class LANSync: ObservableObject {
    static let httpPort: UInt16 = 23234
    private static let udpPort: UInt16 = 23235
    private static let name = "SimpleLive-TV"
    private let deviceID = String(UUID().uuidString.prefix(8))
    private let io = DispatchQueue(label: "simplelive.sync.lan")
    private var listener: NWListener?
    private var discovery: DispatchSourceRead?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var requests: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var chunks = SyncChunks()
    private var generation = UUID()
    @Published private(set) var addresses: [String] = []
    @Published private(set) var status = "准备启动"
    @Published private(set) var progress: String?
    @Published private(set) var ready = false

    func start(selection: @escaping @MainActor () -> SyncSelection, receiver: SyncReceiver) {
        stop()
        let run = generation
        status = "正在启动局域网同步"
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.httpPort)!)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.generation == run else { return }
                    switch state {
                    case .ready:
                        self.ready = true
                        self.addresses = Self.localAddresses()
                        self.status = self.addresses.isEmpty ? "未找到局域网 IPv4 地址" : "等待 Dart 设备发送"
                        do { try self.startDiscovery() }
                        catch { self.status = "UDP 发现不可用。可使用二维码或手动输入地址。" }
                    case .failed, .waiting:
                        self.ready = false
                        self.status = "HTTP 同步服务不可用，请检查局域网权限和端口 23234"
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.generation == run, self.connections.count < 12 else {
                        connection.cancel()
                        return
                    }
                    self.accept(connection, selection: selection, receiver: receiver)
                }
            }
            listener.start(queue: io)
        } catch {
            status = "无法启动 HTTP 同步服务"
        }
    }

    func stop() {
        generation = UUID()
        listener?.cancel()
        listener = nil
        discovery?.cancel()
        discovery = nil
        connections.values.forEach { $0.cancel() }
        requests.values.forEach { $0.cancel() }
        connections.removeAll()
        requests.removeAll()
        chunks = SyncChunks()
        addresses = []
        ready = false
        progress = nil
    }

    private func accept(_ connection: NWConnection, selection: @escaping @MainActor () -> SyncSelection,
                        receiver: SyncReceiver) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.start(queue: io)
        io.asyncAfter(deadline: .now() + 30) { [weak self, weak connection] in
            Task { @MainActor in
                guard let self, let connection, self.connections[id] === connection else { return }
                self.finish(connection)
            }
        }
        read(connection, buffer: Data(), selection: selection, receiver: receiver)
    }

    private func read(_ connection: NWConnection, buffer: Data,
                      selection: @escaping @MainActor () -> SyncSelection, receiver: SyncReceiver) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, ended, error in
            Task { @MainActor in
                guard let self, let connection, self.connections[ObjectIdentifier(connection)] === connection else { return }
                guard error == nil else { self.finish(connection); return }
                var buffer = buffer
                if let data { buffer.append(data) }
                do {
                    if let request = try LANSyncRequest.parse(buffer) {
                        self.requests[ObjectIdentifier(connection)] = Task {
                            let answer = await self.respond(request, peer: Self.peerName(connection.endpoint),
                                                            selection: selection(), receiver: receiver)
                            if !Task.isCancelled { self.send(answer, to: connection) }
                        }
                    } else if !ended {
                        self.read(connection, buffer: buffer, selection: selection, receiver: receiver)
                    } else {
                        self.finish(connection)
                    }
                } catch {
                    self.send(["status": false, "message": error.localizedDescription], to: connection)
                }
            }
        }
    }

    func respond(_ request: LANSyncRequest, peer: String, selection: SyncSelection,
                 receiver: SyncReceiver) async -> [String: Any] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        if request.method == "GET", request.path == "/" {
            return ["status": true, "message": "http server is running...", "type": "tv",
                    "app": "Simple Live TV", "version": version, "platform": "tvos"]
        }
        if request.method == "GET", request.path == "/info" {
            return ["id": deviceID, "name": Self.name, "type": "tv", "version": version,
                    "address": addresses.joined(separator: ";"), "port": Self.httpPort,
                    "supportedAccountTypes": SyncProfile.accountSites.sorted()]
        }
        do {
            guard request.method == "POST" else { throw SyncError.invalidProfile }
            let overlay = request.query["overlay"] ?? "0"
            guard ["0", "1"].contains(overlay) else { throw SyncError.invalidProfile }
            var overwrite = overlay == "1"
            var profile = SyncProfile()
            switch request.path {
            case "/sync/profile":
                profile = try SyncProfile(data: request.body)
            case "/sync/follow", "/sync/history", "/sync/blocked_word", "/sync/tag":
                let categories: [String: SyncCategory] = ["/sync/follow": .follows, "/sync/history": .histories,
                                                           "/sync/blocked_word": .shields]
                let key = peer + request.path
                let chunk: SyncChunk
                do { chunk = try SyncChunk(fields: request.query) } catch {
                    chunks.discard(key)
                    throw error
                }
                if let category = categories[request.path], !selection.categories.contains(category) {
                    chunks.discard(key)
                    throw SyncError.noSelection
                }
                switch try chunks.receive(chunk, data: request.body, overwrite: overwrite, key: key) {
                case let .partial(index, total):
                    progress = "已接收第 \(index)/\(total) 段"
                    return ["status": true, "message": "chunk received"]
                case let .complete(rows, replace):
                    guard let category = categories[request.path] else {
                        return ["status": true, "message": "TV 端暂不使用关注标签"]
                    }
                    profile.values[category] = rows
                    overwrite = replace
                }
            default:
                let prefix = "/sync/account/"
                guard request.path.hasPrefix(prefix),
                      let object = try JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
                    throw SyncError.invalidProfile
                }
                let site = String(request.path.dropFirst(prefix.count))
                profile.values[.accounts] = ["items": [try SyncProfile.accountItem(site: site, object: object)]]
            }
            progress = "正在处理导入"
            let result = try await receiver.receive(profile, selection: selection, overwrite: overwrite,
                                                    reviewTimeout: .seconds(16))
            progress = "已导入 · \(result)"
            return ["status": true, "message": result]
        } catch {
            progress = error.localizedDescription
            return ["status": false, "message": error.localizedDescription]
        }
    }

    private func send(_ response: [String: Any], to connection: NWConnection) {
        guard let json = try? JSONSerialization.data(withJSONObject: response) else { finish(connection); return }
        var bytes = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n".utf8)
        bytes.append(json)
        connection.send(content: bytes, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.finish(connection) }
        })
    }

    private func finish(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        requests.removeValue(forKey: id)?.cancel()
        connections[id] = nil
        connection.cancel()
    }

    private static func peerName(_ endpoint: NWEndpoint) -> String {
        if case let .hostPort(host, _) = endpoint { return "\(host)" }
        return String(describing: endpoint)
    }

    private func startDiscovery() throws {
        discovery?.cancel()
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw SyncError.connectionFailed }
        var enabled: Int32 = 1
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = Self.udpPort.bigEndian
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0
                    && setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0
                    && bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard bound, fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            close(descriptor)
            throw SyncError.connectionFailed
        }
        let read = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: io)
        let reply = (try? JSONSerialization.data(withJSONObject: ["id": deviceID, "type": "tv", "name": Self.name])) ?? Data()
        read.setEventHandler {
            let capacity = 2048
            var buffer = [UInt8](repeating: 0, count: capacity)
            var source = sockaddr_in()
            var size = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &source) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(descriptor, &buffer, capacity, 0, $0, &size)
                }
            }
            guard count > 0 else { return }
            let bytes = Data(buffer.prefix(count))
            let json = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
            guard bytes == Data("Who is SimpleLive?".utf8) || json?["type"] as? String == "hello" else { return }
            var broadcast = source
            broadcast.sin_addr.s_addr = INADDR_BROADCAST
            broadcast.sin_port = UInt16(23235).bigEndian
            // Unicast also covers peers that can reach HTTP but don't receive broadcast replies.
            for var destination in [source, broadcast] {
                withUnsafePointer(to: &destination) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                        reply.withUnsafeBytes { payload in
                            _ = sendto(descriptor, payload.baseAddress, payload.count, 0, addr, size)
                        }
                    }
                }
            }
        }
        read.setCancelHandler { close(descriptor) }
        discovery = read
        read.resume()
    }

    private static func localAddresses() -> [String] {
        var result: [String] = []
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return [] }
        defer { freeifaddrs(interfaces) }
        var next = interfaces
        while let pointer = next {
            let interface = pointer.pointee
            next = interface.ifa_next
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  (interface.ifa_flags & UInt32(IFF_UP)) != 0, (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(NI_MAXHOST), nil, 0, NI_NUMERICHOST) == 0 {
                let address = String(cString: host)
                if !result.contains(address) { result.append(address) }
            }
        }
        return result
    }
}
