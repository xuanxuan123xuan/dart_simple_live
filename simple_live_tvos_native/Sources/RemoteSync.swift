import Combine
import Foundation
import Network

struct RemoteSyncSettings {
    static let domestic = "wss://june6699.top/sync"
    static let cloudflare = "wss://simple-live-sync.3439394104.workers.dev/sync"

    let url: URL
    let configuration: URLSessionConfiguration

    init(server: String, proxy: String) throws {
        guard let url = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["wss", "ws"].contains(url.scheme ?? ""), url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil else { throw SyncError.invalidAddress }
        self.url = url
        configuration = .ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.httpShouldSetCookies = false
        let text = proxy.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased() == "direct" {
            configuration.connectionProxyDictionary = [:]
        } else if !text.isEmpty {
            let address = text.contains("://") ? text : "http://\(text)"
            guard let proxyURL = URLComponents(string: address),
                  ["http", "https"].contains(proxyURL.scheme ?? ""), let host = proxyURL.host,
                  let number = proxyURL.port, let port = UInt16(exactly: number).flatMap(NWEndpoint.Port.init(rawValue:)),
                  port.rawValue > 0, proxyURL.user == nil, proxyURL.password == nil,
                  proxyURL.path.isEmpty, proxyURL.query == nil, proxyURL.fragment == nil else {
                throw SyncError.invalidAddress
            }
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)
            let tls = proxyURL.scheme == "https" ? NWProtocolTLS.Options() : nil
            var proxyConfig = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: tls)
            proxyConfig.allowFailover = false
            configuration.proxyConfigurations = [proxyConfig]
        }
    }
}

/// Shared by the two clients that connect to addresses supplied by the user.
final class SyncNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum RemoteSyncFrame {
    case room(String)
    case closed
    case failure
    case peers(Int)
    case content(category: SyncCategory, fields: [String: Any], sender: String)
    case ignored

    init(_ raw: String) throws {
        guard let frame = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let type = frame["type"] as? String else { throw SyncError.invalidProfile }
        switch type {
        case "roomCreated":
            guard frame["requestId"] as? String == "1", let room = frame["roomId"] as? String,
                  room.utf8.count == 6, room.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else {
                throw SyncError.invalidProfile
            }
            self = .room(room)
        case "roomDestroyed": self = .closed
        case "error": self = frame["requestId"] as? String == "1" ? .failure : .ignored
        case "userUpdated":
            self = .peers((frame["users"] as? [[String: Any]] ?? []).filter { $0["isSelf"] as? Bool != true }.count)
        default:
            let types: [String: SyncCategory] = ["favoriteReceived": .follows, "historyReceived": .histories,
                "shieldWordReceived": .shields, "biliAccountReceived": .accounts,
                "douyinAccountReceived": .accounts, "kuaishouAccountReceived": .accounts]
            guard let category = types[type] else { self = .ignored; return }
            guard var payload = frame["payload"] as? [String: Any] else { throw SyncError.invalidCategory(category) }
            if type == "douyinAccountReceived" { payload["accountType"] = "douyin" }
            if type == "kuaishouAccountReceived" { payload["accountType"] = "kuaishou" }
            let sender = frame["senderId"] as? String ?? frame["connectionId"] as? String
                ?? (frame["from"] as? [String: Any])?["connectionId"] as? String ?? ""
            self = .content(category: category, fields: payload, sender: sender)
        }
    }
}

@MainActor
final class RemoteSync: ObservableObject {
    @Published private(set) var room: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var peerCount = 0
    @Published private(set) var status = "准备连接"
    private var chunks = SyncChunks()

    func run(settings: RemoteSyncSettings, selection: @escaping @MainActor () -> SyncSelection,
             receiver: SyncReceiver) async {
        room = nil
        expiresAt = nil
        peerCount = 0
        chunks = SyncChunks()
        status = "正在连接"
        let session = URLSession(configuration: settings.configuration, delegate: SyncNoRedirect(), delegateQueue: nil)
        let socket = session.webSocketTask(with: settings.url)
        socket.maximumMessageSize = SyncProfile.maxBytes
        socket.resume()
        defer {
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            room = nil
            expiresAt = nil
            peerCount = 0
            chunks = SyncChunks()
        }

        let timeout = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(15))
                if room == nil { socket.cancel() }
            } catch {}
        }
        let heartbeat = Task { @MainActor in
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(20))
                    guard let expiresAt else { continue }
                    if Date() >= expiresAt { socket.cancel(); return }
                    try await Self.send(["type": "ping", "requestId": "ping_\(UUID())"], to: socket)
                }
            } catch {
                if !Task.isCancelled { socket.cancel() }
            }
        }
        defer {
            timeout.cancel()
            heartbeat.cancel()
        }

        do {
            try await withTaskCancellationHandler {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                try await Self.send(["type": "createRoom", "requestId": "1", "payload":
                    // Dart's legacy sender gates the extended account envelope on this protocol version.
                    ["app": "Simple Live TV", "platform": "tv", "version": "1.8.0", "nativeVersion": version]], to: socket)
                while !Task.isCancelled {
                    guard case let .string(raw) = try await socket.receive() else { continue }
                    switch try RemoteSyncFrame(raw) {
                    case let .room(code):
                        guard room == nil else { continue }
                        room = code
                        expiresAt = Date().addingTimeInterval(600)
                        status = "等待 Dart 设备发送"
                    case .closed:
                        status = "同步房间已关闭，请重新连接"
                        return
                    case .failure: throw SyncError.connectionFailed
                    case let .peers(count): peerCount = count
                    case .ignored: continue
                    case let .content(category, fields, sender):
                        guard room != nil, let expiresAt, expiresAt > Date() else { continue }
                        do {
                            try await importContent(category, fields: fields, sender: sender,
                                                    selection: selection(), receiver: receiver)
                        } catch {
                            status = error.localizedDescription
                        }
                    }
                }
            } onCancel: {
                socket.cancel(with: .goingAway, reason: nil)
            }
        } catch {
            guard !Task.isCancelled else { return }
            status = if let expiresAt, expiresAt <= Date() {
                "同步房间已过期，请重新连接"
            } else {
                room == nil ? SyncError.connectionFailed.localizedDescription : "同步连接已断开，请重新连接"
            }
        }
    }

    private func importContent(_ category: SyncCategory, fields: [String: Any], sender: String,
                               selection: SyncSelection, receiver: SyncReceiver) async throws {
        guard selection.categories.contains(category) else { throw SyncError.noSelection }
        guard let content = fields["content"] as? String else { throw SyncError.invalidCategory(category) }
        let data = Data(content.utf8)
        let overwrite = fields["overlay"] as? Bool == true
        var profile = SyncProfile()
        if category == .accounts {
            guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SyncError.invalidCategory(.accounts)
            }
            let type = (fields["accountType"] as? String ?? row["accountType"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let item = try SyncProfile.accountItem(site: type.isEmpty ? "bilibili" : type, object: row)
            profile.values[category] = ["items": [item]]
            _ = try await receiver.receive(profile, selection: selection, overwrite: overwrite)
            return
        }
        let key = "\(sender)/\(category.rawValue)"
        let chunk: SyncChunk
        do { chunk = try SyncChunk(fields: fields) } catch {
            chunks.discard(key)
            throw error
        }
        switch try chunks.receive(chunk, data: data, overwrite: overwrite, key: key) {
        case let .partial(index, total):
            status = "接收\(category.title)第 \(index)/\(total) 段"
        case let .complete(rows, overwrite):
            profile.values[category] = rows
            status = "已导入 · " + (try await receiver.receive(profile, selection: selection, overwrite: overwrite))
        }
    }

    private static func send(_ fields: [String: Any], to socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: fields)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
}
