import Foundation
import SimpleLiveTVOSCore

actor KuaishouService: LiveProviderService, DanmakuService {
    private static let origin = "https://live.kuaishou.com"
    private static let headers = [
        "Referer": origin + "/",
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
    ]
    private let http = ProviderHTTP()

    func categories() async throws -> [CategoryDescriptor] {
        let names = ["热门", "网游", "单机", "手游", "棋牌", "娱乐", "综合", "文化"]
        var categories: [CategoryDescriptor] = []
        for (index, name) in names.enumerated() {
            let type = String(index + 1)
            var children: [CategoryDescriptor] = []
            for page in 1...10 {
                try Task.checkCancellation()
                let data = try await request("/live_api/category/data", ["type": type, "page": String(page), "size": "50"])
                guard data.fields["list"] is [Any], let more = data.integer("hasMore"), (0...1).contains(more) else {
                    throw LiveProviderError.invalidResponse
                }
                children += data.objects("list").compactMap {
                    let id = $0.text("id")
                    let name = $0.text("name")
                    guard !id.isEmpty, !name.isEmpty else { return nil }
                    return CategoryDescriptor(categoryId: id, name: name, parentId: type)
                }
                if more == 0 { break }
                if page == 10 { throw LiveProviderError.remote("快手分区目录超过分页上限") }
            }
            categories.append(.group(type, name: name, children: children))
        }
        return categories
    }

    func rooms(in listing: RoomListing, page: Int) async throws -> RoomPage {
        let items: [JSONObject]
        let more: Bool
        switch listing {
        case .recommended:
            let data = try await request("/live_api/home/list")
            items = data.objects("list").flatMap { $0.objects("gameLiveInfo") }.flatMap { $0.objects("liveInfo") }
            more = false
        case let .category(category):
            guard let parent = Int(category.parentId), (1...8).contains(parent) else { throw LiveProviderError.invalidResponse }
            let board = parent <= 5 ? "gameboard" : "non-gameboard"
            let data = try await request("/live_api/\(board)/list", [
                "filterType": "0", "pageSize": "20", "gameId": category.categoryId, "page": String(page),
            ])
            items = data.objects("list")
            more = data.integer("hasMore") == 1
        case let .search(keyword, mode):
            if mode == .anchors { return try await searchAnchors(keyword, page: page) }
            let data = try await request("/live_api/search/liveStream", [
                "keyword": keyword, "page": String(page), "count": "20", "ussid": "",
            ])
            guard data.integer("result") == 1, data.fields["list"] is [Any] else { throw LiveProviderError.authenticationRequired }
            items = data.objects("list")
            more = data.integer("hasMore").map { $0 == 1 } ?? (items.count >= 20)
        }
        return RoomPage(rooms: items.compactMap(Self.room), hasMore: more)
    }

    private func searchAnchors(_ keyword: String, page: Int) async throws -> RoomPage {
        let items: [JSONObject]
        let more: Bool
        do {
            let data = try await request("/live_api/search/author", [
                "key": keyword, "keyword": keyword, "page": String(page), "count": "15", "ussid": "", "lssid": "",
            ])
            guard data.integer("result") == 1, data.fields["list"] is [Any] else { throw LiveProviderError.invalidResponse }
            items = data.objects("list")
            let flags = ["hasMore", "hasNext", "hasNextPage"].compactMap { data.bool($0) }
            let totals = ["totalPage", "pageCount", "totalPages"].compactMap { data.integer($0) }
            let counts = ["total", "totalCount", "totalSize"].compactMap { data.integer($0) }
            more = flags.first ?? data.integer("nextPage").map { $0 > page }
                ?? totals.first.map { page < $0 } ?? counts.first.map { page * 15 < $0 } ?? false
        } catch {
            try Task.checkCancellation()
            guard page == 1 else { throw error }
            let overview = try await request("/live_api/search/overview", ["keyword": keyword, "ussid": ""])
            guard overview.fields["list"] is [Any] else { throw LiveProviderError.invalidResponse }
            let section = overview.objects("list").first { $0.text("type") == "authors" }
            if let section, !(section.fields["list"] is [Any]) { throw LiveProviderError.invalidResponse }
            items = section?.objects("list") ?? []
            more = false
        }
        return RoomPage(rooms: items.compactMap {
            RoomDescriptor.anchor(provider: "kuaishou", id: $0.text("id"), name: $0.text("name"),
                                  avatar: $0.text("avatar"), isLive: $0.bool("living"))
        }, hasMore: more)
    }

    func resolveRoom(_ input: String) async throws -> RoomDescriptor {
        let id = try normalizedRoomID(input, hosts: ["live.kuaishou.com"])
        guard let room = Self.room(try await detail(id)) else { throw LiveProviderError.invalidRoom }
        return room
    }

    func qualities(roomId: String) async throws -> [LiveQuality] {
        try await variants(roomId).map(\.quality)
    }

    func playback(roomId: String, quality: LiveQuality) async throws -> [PlaybackResource] {
        let values = try await variants(roomId)
        guard let selection = values.first(where: { $0.quality.id == quality.id }) else { throw LiveProviderError.noPlayback }
        return selection.resources(headers: Self.headers)
    }

    private func request(_ path: String, _ query: [String: String] = [:]) async throws -> JSONObject {
        let result = try await http.json(Self.origin + path, query: query, headers: Self.headers)
        guard result.fields["data"] is [String: Any] else { throw LiveProviderError.invalidResponse }
        return result["data"]
    }

    private func detail(_ id: String) async throws -> JSONObject {
        let verified = try normalizedRoomID(id, hosts: [])
        let (data, _) = try await http.response(Self.origin + "/u/" + verified, headers: Self.headers)
        let html = String(decoding: data, as: UTF8.self)
        let state = try EmbeddedPageData.initialState(in: html)
        let rooms = state["liveroom"].objects("playList")
        guard let room = rooms.first(where: { [$0["author"].text("id"), $0.text("authorId"), $0.text("userId")].contains(id) }) else {
            throw LiveProviderError.invalidRoom
        }
        return room
    }

    nonisolated func danmaku(roomId: String) -> AsyncThrowingStream<DanmakuEvent, Error> {
        DanmakuConnection.stream { try await self.danmakuConnection(roomId) }
    }

    private func danmakuConnection(_ id: String) async throws -> DanmakuConnection {
        let room = try await detail(id)
        let live = room["liveStream"]
        let stream = live.text("id")
        guard !stream.isEmpty else { throw LiveProviderError.authenticationRequired }
        let info = try await request("/live_api/liveroom/websocketinfo", ["liveStreamId": stream])
        let nested = info["websocketInfo"]
        let token = [info.text("token"), info.text("websocketToken"), nested.text("token")].first { !$0.isEmpty }
        let candidates = info.values("websocketUrls") + info.values("websocketAddresses") + nested.values("websocketUrls")
        let url = candidates.compactMap { ($0 as? String).flatMap(URL.init(string:)) }.first {
            guard let host = $0.host else { return false }
            return $0.scheme == "wss" && $0.user == nil && $0.password == nil &&
                (host.hasSuffix(".kuaishou.com") || host.hasSuffix(".ksapisrv.com") ||
                 host.hasSuffix(".gifshow.com") || host.hasSuffix(".kwai.com"))
        }
        guard let token, let url else { throw LiveProviderError.authenticationRequired }
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = Self.headers
        request.setValue(Self.origin, forHTTPHeaderField: "Origin")
        return DanmakuConnection(request: request,
            initialFrames: [KuaishouDanmaku.join(token: token, stream: stream, expTag: live.text("expTag"), attach: room.text("expTag"))],
            heartbeatInterval: .seconds(20), heartbeat: KuaishouDanmaku.heartbeat
        ) { bytes in
            (try KuaishouDanmaku.decode(bytes, roomID: id), nil)
        }
    }

    private static func room(_ item: JSONObject) -> RoomDescriptor? {
        let author = item["author"]
        let stream = item["liveStream"]
        let id = [author.text("id"), item.text("authorId"), item.text("userId")].first { !$0.isEmpty }
        guard let id else { return nil }
        let title = [item.text("caption"), stream.text("caption"), item.text("title"), author.text("name")].first { !$0.isEmpty } ?? id
        let cover = [stream.text("poster"), item.text("poster"), item.text("coverUrl"), item["gameInfo"].text("poster")].first { !$0.isEmpty } ?? ""
        return RoomDescriptor(provider: "kuaishou", roomId: id, title: title, cover: normalizedImage(cover), userName: author.text("name"))
    }

    private func variants(_ id: String) async throws -> [MediaVariant] {
        let detail = try await detail(id)
        let playURLs = detail["liveStream"].fields["playUrls"] ?? detail.fields["playUrls"]
        let preferred = (playURLs as? [String: Any])?["h264"] ?? playURLs
        var byQuality: [LiveQuality: [(URL, StreamProtocol)]] = [:]
        var seen = Set<URL>()
        func collect(_ value: Any?, name: String, level: String, depth: Int = 0) {
            guard depth < 12 else { return }
            switch value {
            case let value as String:
                guard let entry = MediaVariant.url(value), seen.insert(entry.0).inserted else { return }
                byQuality[LiveQuality(id: level + ":" + name, name: name), default: []].append(entry)
            case let values as [Any]:
                values.forEach { collect($0, name: name, level: level, depth: depth + 1) }
            case let raw as [String: Any]:
                let value = JSONObject(raw)
                let nextName = [value.text("name"), value.text("shortName"), name].first { !$0.isEmpty } ?? name
                let nextLevel = value.text("level").isEmpty ? level : value.text("level")
                for key in raw.keys.sorted() {
                    collect(raw[key], name: nextName, level: nextLevel, depth: depth + 1)
                }
            default: break
            }
        }
        collect(preferred, name: "默认", level: "0")
        if byQuality.isEmpty { collect(playURLs, name: "默认", level: "0") }
        guard !byQuality.isEmpty else { throw LiveProviderError.noPlayback }
        return byQuality.keys.sorted {
            let a = Int($0.id.split(separator: ":").first ?? "") ?? 0
            let b = Int($1.id.split(separator: ":").first ?? "") ?? 0
            return a == b ? $0.id < $1.id : a > b
        }.map { MediaVariant(quality: $0, urls: byQuality[$0] ?? []) }
    }
}
