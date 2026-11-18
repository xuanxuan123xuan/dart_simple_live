import Foundation
import Flutter
import Combine
import WebKit

@MainActor
final class NativeCoreClient: ObservableObject {
    @Published private(set) var providers: [ProviderDescriptor] = []
    @Published private(set) var categories: [CategoryDescriptor] = []
    @Published private(set) var danmakuMessages: [DanmakuDescriptor] = []
    @Published private(set) var rooms: [RoomDescriptor] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var engine: FlutterEngine?
    private var channel: FlutterMethodChannel?
    private let keychain = KeychainSessionStore()
    private let webSession = WebSessionCoordinator()
    private var sequence = 0

    func start() async {
        guard engine == nil else { return }
        let engine = FlutterEngine(
            name: "SimpleLiveCore",
            project: nil,
            allowHeadlessExecution: true
        )
        guard engine.run(withEntrypoint: "tvosCoreEntrypoint") else {
            errorMessage = "无法启动直播核心服务"
            return
        }
        self.engine = engine
        let channel = FlutterMethodChannel(
            name: "simple_live/tvos_core",
            binaryMessenger: engine.binaryMessenger
        )
        self.channel = channel
        installNativeChannels(on: engine)
        do {
            let raw = try await request(method: "site.providers", payload: [:])
            providers = try Self.decodeProviders(raw)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var loginWebView: WKWebView? { webSession.webView }

    func prepareXiaohongshuLogin() {
        _ = webSession.prepareLoginWebView()
    }

    func loginXiaohongshu() async throws {
        let cookie = try await webSession.loginXiaohongshu()
        try keychain.saveCookie(provider: "xiaohongshu", cookie: cookie)
        _ = try await request(method: "session.setCookie", payload: [
            "provider": "xiaohongshu",
            "cookie": cookie,
        ])
    }

    func closeWebLogin() {
        webSession.close()
    }

    private func installNativeChannels(on engine: FlutterEngine) {
        let danmakuChannel = FlutterBasicMessageChannel(
            name: "simple_live/tvos_danmaku_events",
            binaryMessenger: engine.binaryMessenger,
            codec: FlutterStandardMessageCodec.sharedInstance()
        )
        danmakuChannel.setMessageHandler { [weak self] message, reply in
            if let event = message as? [String: Any],
               event["kind"] as? String == "message",
               let userName = event["userName"] as? String,
               let text = event["message"] as? String {
                let color = event["color"] as? [String: Any]
                let value = DanmakuDescriptor(
                    id: UUID().uuidString,
                    userName: userName,
                    message: text,
                    red: color?["r"] as? Int ?? 255,
                    green: color?["g"] as? Int ?? 255,
                    blue: color?["b"] as? Int ?? 255,
                    imageURLs: event["imageUrls"] as? [String] ?? []
                )
                self?.danmakuMessages = Array((self?.danmakuMessages ?? []) + [value].suffix(36))
            }
            reply(nil)
        }

        let sessionChannel = FlutterMethodChannel(
            name: "simple_live/tvos_session",
            binaryMessenger: engine.binaryMessenger
        )
        sessionChannel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return result(FlutterError(code: "closed", message: "session host is closed", details: nil)) }
            let provider = (call.arguments as? [String: Any])?["provider"] as? String ?? ""
            do {
                switch call.method {
                case "readCookie":
                    result(try self.keychain.readCookie(provider: provider))
                case "saveCookie":
                    let cookie = (call.arguments as? [String: Any])?["cookie"] as? String ?? ""
                    try self.keychain.saveCookie(provider: provider, cookie: cookie)
                    result(nil)
                case "clearCookie":
                    try self.keychain.clearCookie(provider: provider)
                    result(nil)
                default:
                    result(FlutterMethodNotImplemented)
                }
            } catch {
                result(FlutterError(code: "keychain", message: error.localizedDescription, details: nil))
            }
        }

        let webChannel = FlutterMethodChannel(
            name: "simple_live/tvos_web",
            binaryMessenger: engine.binaryMessenger
        )
        webChannel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return result(FlutterError(code: "closed", message: "web host is closed", details: nil)) }
            switch call.method {
            case "login":
                Task { @MainActor in
                    do {
                        let cookie = try await self.webSession.loginXiaohongshu()
                        result(["provider": "xiaohongshu", "cookie": cookie])
                    } catch {
                        result(FlutterError(code: "web_login", message: error.localizedDescription, details: nil))
                    }
                }
            case "close":
                self.webSession.close()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func loadRecommend(provider: String, page: Int = 1) async {
        await loadRooms(method: "site.recommend", payload: [
            "provider": provider,
            "page": page,
        ])
    }

    func search(provider: String, keyword: String, page: Int = 1) async {
        await loadRooms(method: "site.search", payload: [
            "provider": provider,
            "keyword": keyword,
            "page": page,
        ])
    }

    func loadCategories(provider: String) async {
        do {
            let raw = try await request(method: "site.categories", payload: [
                "provider": provider,
            ])
            categories = Self.decodeCategories(raw)
        } catch {
            categories = []
            errorMessage = error.localizedDescription
        }
    }

    func loadCategory(
        provider: String,
        categoryId: String,
        categoryName: String,
        parentId: String,
        page: Int = 1
    ) async {
        await loadRooms(method: "site.categoryRooms", payload: [
            "provider": provider,
            "categoryId": categoryId,
            "categoryName": categoryName,
            "parentId": parentId,
            "page": page,
        ])
    }

    func firstPlayback(provider: String, roomId: String) async throws -> PlaybackDescriptor {
        let qualities = try await qualityNames(provider: provider, roomId: roomId)
        guard let quality = qualities.first else {
            throw NativeCoreError.remote("直播间没有返回清晰度")
        }
        return try await playback(
            provider: provider,
            roomId: roomId,
            quality: quality
        )
    }

    func qualityNames(provider: String, roomId: String) async throws -> [String] {
        let qualities = try await request(method: "room.qualities", payload: [
            "provider": provider,
            "roomId": roomId,
        ]) as? [[String: Any]] ?? []
        return qualities.compactMap { $0["quality"] as? String }
    }

    func playback(
        provider: String,
        roomId: String,
        quality: String
    ) async throws -> PlaybackDescriptor {
        let raw = try await request(method: "room.playUrls", payload: [
            "provider": provider,
            "roomId": roomId,
            "quality": quality
        ])
        guard let data = raw as? [String: Any],
              let urls = data["urls"] as? [String] else {
            throw NativeCoreError.invalidResponse
        }
        return PlaybackDescriptor(
            urls: urls.compactMap(URL.init(string:)),
            headers: data["headers"] as? [String: String] ?? [:],
            protocols: data["protocols"] as? [String] ?? []
        )
    }

    func startDanmaku(provider: String, roomId: String) async {
        danmakuMessages.removeAll()
        try? await request(method: "danmaku.start", payload: [
            "provider": provider,
            "roomId": roomId,
        ])
    }

    func stopDanmaku(provider: String, roomId: String) async {
        try? await request(method: "danmaku.stop", payload: [
            "provider": provider,
            "roomId": roomId,
        ])
        danmakuMessages.removeAll()
    }

    private func loadRooms(method: String, payload: [String: Any]) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let raw = try await request(method: method, payload: payload)
            rooms = try Self.decodeRooms(
                raw,
                provider: payload["provider"] as? String ?? ""
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func request(method: String, payload: [String: Any]) async throws -> Any {
        guard let channel else { throw NativeCoreError.notStarted }
        sequence += 1
        let requestId = "tvos-\(sequence)"
        let arguments: [String: Any] = [
            "requestId": requestId,
            "method": method,
            "payload": payload,
        ]
        return try await withCheckedThrowingContinuation { continuation in
            channel.invokeMethod("request", arguments: arguments) { result in
                switch result {
                case let value as [String: Any] where value["ok"] as? Bool == true:
                    continuation.resume(returning: value["data"] as Any)
                case let value as [String: Any]:
                    let error = value["error"] as? [String: Any]
                    continuation.resume(throwing: NativeCoreError.remote(
                        error?["message"] as? String ?? "核心服务请求失败"
                    ))
                case let error as Error:
                    continuation.resume(throwing: error)
                default:
                    continuation.resume(throwing: NativeCoreError.invalidResponse)
                }
            }
        }
    }

    private static func decodeProviders(_ value: Any) throws -> [ProviderDescriptor] {
        guard let items = value as? [[String: Any]] else { throw NativeCoreError.invalidResponse }
        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let title = item["title"] as? String else { return nil }
            return ProviderDescriptor(
                id: id,
                title: title,
                supportLabel: item["supportLabel"] as? String ?? ""
            )
        }
    }

    private static func decodeCategories(_ value: Any) -> [CategoryDescriptor] {
        guard let items = value as? [[String: Any]] else { return [] }
        var result: [CategoryDescriptor] = []
        func append(_ item: [String: Any]) {
            guard let id = item["id"] as? String,
                  let name = item["name"] as? String else { return }
            result.append(CategoryDescriptor(
                id: id,
                name: name,
                parentId: item["parentId"] as? String ?? ""
            ))
            for child in item["children"] as? [[String: Any]] ?? [] {
                append(child)
            }
        }
        items.forEach(append)
        return result
    }

    private static func decodeRooms(_ value: Any, provider: String) throws -> [RoomDescriptor] {
        guard let result = value as? [String: Any],
              let items = result["items"] as? [[String: Any]] else {
            throw NativeCoreError.invalidResponse
        }
        return items.compactMap { item in
            guard let roomId = item["roomId"] as? String,
                  let title = item["title"] as? String else { return nil }
            return RoomDescriptor(
                provider: provider,
                roomId: roomId,
                title: title,
                cover: item["cover"] as? String ?? "",
                userName: item["userName"] as? String ?? ""
            )
        }
    }
}

struct ProviderDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let supportLabel: String
}

struct CategoryDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let parentId: String
}

struct RoomDescriptor: Identifiable, Hashable {
    let provider: String
    let roomId: String
    let title: String
    let cover: String
    let userName: String
    var id: String { roomId }
    var key: String { "\(provider):\(roomId)" }
}

struct PlaybackDescriptor {
    let urls: [URL]
    let headers: [String: String]
    let protocols: [String]
}

struct DanmakuDescriptor: Identifiable, Hashable {
    let id: String
    let userName: String
    let message: String
    let red: Int
    let green: Int
    let blue: Int
    let imageURLs: [String]
}

enum NativeCoreError: LocalizedError {
    case notStarted
    case invalidResponse
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .notStarted: "直播核心尚未启动"
        case .invalidResponse: "直播核心返回了无效数据"
        case let .remote(message): message
        }
    }
}
