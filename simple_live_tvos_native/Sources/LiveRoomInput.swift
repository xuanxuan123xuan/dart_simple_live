import Foundation

struct LiveRoomTarget: Equatable {
    let provider: String
    let roomID: String
    var isDouyinReflow = false
    var douyinUserID: String? = nil
}

/// Shared by all room-entry surfaces. Requests are made only for recognized short-link origins.
struct LiveRoomInput {
    private enum Link {
        case room(LiveRoomTarget)
        case redirect(provider: String, url: URL)
    }

    private static let hostProviders = [
        "live.bilibili.com": "bilibili", "b23.tv": "bilibili", "www.b23.tv": "bilibili",
        "douyu.com": "douyu", "www.douyu.com": "douyu", "m.douyu.com": "douyu",
        "huya.com": "huya", "www.huya.com": "huya", "m.huya.com": "huya",
        "live.douyin.com": "douyin", "www.douyin.com": "douyin", "douyin.com": "douyin",
        "webcast.amemv.com": "douyin", "v.douyin.com": "douyin",
        "live.kuaishou.com": "kuaishou", "v.kuaishou.com": "kuaishou", "m.chenzhongtech.com": "kuaishou",
        "xiaohongshu.com": "xiaohongshu", "www.xiaohongshu.com": "xiaohongshu", "live-room.xiaohongshu.com": "xiaohongshu",
        "xhslink.com": "xiaohongshu", "www.xhslink.com": "xiaohongshu",
    ]

    private let follow: (URL) async throws -> URL

    init(follow: @escaping (URL) async throws -> URL) {
        self.follow = follow
    }

    func resolve(_ input: String, defaultProvider: String) async throws -> LiveRoomTarget {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 16_384 else { throw LiveProviderError.invalidRoom }
        let urlPattern = #"(?i)https?://[^\s<>"“”，。！？、；：]+"#
        guard let urlRange = text.range(of: urlPattern, options: .regularExpression) else {
            return try Self.target(defaultProvider, id: text)
        }
        let raw = String(text[urlRange]).trimmingCharacters(in: CharacterSet(charactersIn: ",;:!?)]}）】》」』"))
        guard var url = URL(string: raw) else { throw LiveProviderError.invalidRoom }
        var expectedProvider: String?
        for hop in 0...5 {
            try Task.checkCancellation()
            switch try Self.link(url, expectedProvider: expectedProvider) {
            case let .room(target): return target
            case let .redirect(provider, shortURL):
                guard hop < 5 else { throw LiveProviderError.invalidRoom }
                expectedProvider = provider
                url = try await follow(shortURL)
            }
        }
        throw LiveProviderError.invalidRoom
    }

    private static func link(_ url: URL, expectedProvider: String?) throws -> Link {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              parts.user == nil, parts.password == nil, let host = parts.host?.lowercased(),
              parts.port == nil || parts.port == (scheme == "https" ? 443 : 80) else { throw LiveProviderError.invalidRoom }
        let kuaishouMobile = host == "m.chenzhongtech.com" || host.hasSuffix(".m.chenzhongtech.com")
        guard let provider = hostProviders[host] ?? (kuaishouMobile ? "kuaishou" : nil),
              expectedProvider == nil || expectedProvider == provider else { throw LiveProviderError.invalidRoom }
        // Split encoded components first so encoded slashes cannot change the route structure.
        let segments = parts.percentEncodedPath.split(separator: "/").map { String($0).removingPercentEncoding ?? "" }
        let id: String
        switch host {
        case "b23.tv", "www.b23.tv", "v.douyin.com", "v.kuaishou.com", "xhslink.com", "www.xhslink.com":
            guard !segments.isEmpty else { throw LiveProviderError.invalidRoom }
            parts.scheme = "https"
            parts.port = nil
            parts.fragment = nil
            guard let endpoint = parts.url else { throw LiveProviderError.invalidRoom }
            return .redirect(provider: provider, url: endpoint)
        case "live.douyin.com", "live.bilibili.com", "huya.com", "www.huya.com", "m.huya.com":
            id = segments.first ?? ""
        case "douyu.com", "www.douyu.com", "m.douyu.com":
            id = segments.contains("topic") ? parts.queryItems?.first(where: { $0.name == "rid" })?.value ?? "" : segments.first ?? ""
        case "www.douyin.com", "douyin.com":
            if segments.count == 2, segments[0] == "live" { id = segments[1] }
            else if segments.count == 3, segments.prefix(2).elementsEqual(["follow", "live"]) { id = segments[2] }
            else { throw LiveProviderError.invalidRoom }
        case "webcast.amemv.com":
            guard let index = segments.firstIndex(of: "reflow"), index + 1 < segments.count else {
                throw LiveProviderError.invalidRoom
            }
            var target = try target(provider, id: segments[index + 1])
            target.isDouyinReflow = true
            target.douyinUserID = parts.queryItems?.first(where: { $0.name == "sec_user_id" })?.value
            return .room(target)
        case "live.kuaishou.com":
            guard segments.count == 2, segments[0] == "u" else { throw LiveProviderError.invalidRoom }
            id = segments[1]
        case "xiaohongshu.com", "www.xiaohongshu.com", "live-room.xiaohongshu.com":
            if (2...3).contains(segments.count), segments[0] == "livestream" { id = segments.last ?? "" }
            else if segments.count == 4, segments.prefix(2).elementsEqual(["hina", "livestream"]),
                    segments[3].range(of: #"^\d+$"#, options: .regularExpression) != nil { id = segments[2] }
            else { throw LiveProviderError.invalidRoom }
        default:
            guard kuaishouMobile, segments.count == 3, segments.prefix(2).elementsEqual(["fw", "live"]) else {
                throw LiveProviderError.invalidRoom
            }
            id = segments[2]
        }
        let cleaned = provider == "douyin" ? id : id.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return .room(try target(provider, id: cleaned))
    }

    private static func target(_ provider: String, id: String) throws -> LiveRoomTarget {
        let roomID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern: String
        switch provider {
        case "bilibili": pattern = #"^[0-9]{1,20}$"#
        case "xiaohongshu": pattern = #"^[0-9]{8,32}$"#
        case "douyin": pattern = #"^[a-zA-Z0-9_.-]{1,128}$"#
        case "huya", "douyu", "kuaishou": pattern = #"^[a-zA-Z0-9_-]{1,128}$"#
        default: throw LiveProviderError.unsupported
        }
        guard roomID.range(of: pattern, options: .regularExpression) != nil,
              roomID.range(of: #"[a-zA-Z0-9]"#, options: .regularExpression) != nil else { throw LiveProviderError.invalidRoom }
        return LiveRoomTarget(provider: provider, roomID: roomID)
    }
}
