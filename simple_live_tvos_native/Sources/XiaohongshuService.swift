import Foundation
import SimpleLiveTVOSCore

actor XiaohongshuService: LiveProviderService, DanmakuService {
    private static let web = "https://www.xiaohongshu.com"
    private static let live = "https://live-room.xiaohongshu.com"
    private static let roomHosts: Set<String> = ["www.xiaohongshu.com", "xiaohongshu.com"]
    private static let shortLinkHosts: Set<String> = ["xhslink.com", "www.xhslink.com"]
    private static let headers = [
        "Referer": web + "/",
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
    ]
    private let http = ProviderHTTP(redirectHosts: roomHosts.union(shortLinkHosts))
    private let accounts: AccountRequestCredentials

    init(accounts: AccountRequestCredentials = AccountRequestCredentials()) {
        self.accounts = accounts
    }

    private var accountHeaders: [String: String] {
        var headers = Self.headers
        headers["Cookie"] = accounts.credential(for: .xiaohongshu)?.cookie
        return headers
    }

    func categories() async throws -> [CategoryDescriptor] { [] }

    func rooms(in listing: RoomListing, page: Int) async throws -> RoomPage {
        throw LiveProviderError.remote("小红书暂可用直播链接进房")
    }

    func resolveRoom(_ input: String) async throws -> RoomDescriptor {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: String
        if let link = URL(string: value), let host = link.host {
            let url: URL
            if Self.shortLinkHosts.contains(host), link.scheme == "https", link.port == nil || link.port == 443 {
                let (_, response) = try await http.response(link.absoluteString, headers: Self.headers)
                guard let redirected = response.url else { throw LiveProviderError.invalidRoom }
                url = redirected
            } else {
                url = link
            }
            let path = url.pathComponents.dropFirst()
            guard path.count == 2, path.first == "livestream" else { throw LiveProviderError.invalidRoom }
            id = try normalizedRoomID(url.absoluteString, hosts: Self.roomHosts)
        } else {
            id = try normalizedRoomID(value, hosts: [])
        }
        let (room, host, data) = try await detail(id)
        let status = room.integer("status") ?? data.integer("status")
        let isLive = status.flatMap { $0 == 2 ? true : [0, 1, 3].contains($0) ? false : nil }
        return RoomDescriptor(provider: "xiaohongshu", roomId: id,
                              title: [room.text("roomTitle"), room.text("title")].first { !$0.isEmpty } ?? id,
                              cover: normalizedImage([room.text("cover"), room.text("roomCover"), host.text("cover")].first { !$0.isEmpty } ?? ""),
                              userName: [host.text("nickname"), host.text("nickName"), host.text("name")].first { !$0.isEmpty } ?? "",
                              isLive: isLive)
    }

    func qualities(roomId: String) async throws -> [LiveQuality] {
        try await variants(roomId).map(\.quality)
    }

    func playback(roomId: String, quality: LiveQuality) async throws -> [PlaybackResource] {
        let values = try await variants(roomId)
        guard let selection = values.first(where: { $0.quality.id == quality.id }) else { throw LiveProviderError.noPlayback }
        var headers = Self.headers
        headers["Referer"] = Self.web + "/livestream/" + roomId
        return selection.resources(headers: headers)
    }

    private func detail(_ id: String) async throws -> (room: JSONObject, host: JSONObject, data: JSONObject) {
        let id = try normalizedRoomID(id, hosts: [])
        var headers = accountHeaders
        headers["xy-common-params"] = "platform=iOS"
        let (bytes, _) = try await http.response(Self.web + "/livestream/" + id, headers: headers)
        let state = try EmbeddedPageData.initialState(in: String(decoding: bytes, as: UTF8.self))
        let requested = state["liveStream"]["roomData"]
        let data = requested.fields.isEmpty ? state["roomData"] : requested
        let room = data["roomInfo"]
        guard !room.fields.isEmpty else { throw LiveProviderError.invalidResponse }
        return (room, data["hostInfo"].fields.isEmpty ? room["hostInfo"] : data["hostInfo"], data)
    }

    private func variants(_ id: String) async throws -> [MediaVariant] {
        let (room, _, data) = try await detail(id)
        let status = room.integer("status") ?? data.integer("status")
        if status == 0 || status == 1 || status == 3 { throw LiveProviderError.offline }
        let raw = data.fields["pullConfig"] ?? room.fields["pullConfig"]
        var byQuality: [String: [(URL, StreamProtocol)]] = [:]
        var order: [String] = []
        var seen = Set<URL>()
        func collect(_ value: Any?, name: String, depth: Int = 0) {
            guard depth < 12 else { return }
            if let string = value as? String, let nested = try? JSONSerialization.jsonObject(with: Data(string.utf8)) {
                collect(nested, name: name, depth: depth + 1)
            } else if let values = value as? [Any] {
                values.forEach { collect($0, name: name, depth: depth + 1) }
            } else if let raw = value as? [String: Any] {
                let node = JSONObject(raw)
                let nextName = ["quality_type_name", "quality_type", "quality", "qualityName", "name"].lazy
                    .map { node.text($0) }.first { !$0.isEmpty } ?? name
                for (key, hint) in [("master_url", StreamProtocol.hls), ("hlsUrl", .hls), ("hls", .hls), ("flvUrl", .flv), ("flv", .flv)] {
                    if let url = MediaVariant.url(node.text(key), hint: hint), seen.insert(url.0).inserted {
                        if byQuality[nextName] == nil { order.append(nextName) }
                        byQuality[nextName, default: []].append(url)
                    }
                }
                if let url = MediaVariant.url(node.text("url")), seen.insert(url.0).inserted {
                    if byQuality[nextName] == nil { order.append(nextName) }
                    byQuality[nextName, default: []].append(url)
                }
                for key in raw.keys.sorted() where !(raw[key] is String) {
                    collect(raw[key], name: nextName, depth: depth + 1)
                }
            }
        }
        collect(raw, name: "默认")
        guard !order.isEmpty else { throw LiveProviderError.noPlayback }
        return order.map { MediaVariant(quality: LiveQuality(id: $0, name: $0), urls: byQuality[$0] ?? []) }
    }

    nonisolated func danmaku(roomId: String) -> AsyncThrowingStream<DanmakuEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
            let task = Task {
                do {
                    var cursor = "0"
                    var seen = Set<String>()
                    var recent: [String] = []
                    while !Task.isCancelled {
                        let data = try await self.comments(roomId, cursor: cursor)
                        for comment in data.objects("comments") {
                            let message = comment.text("desc")
                            let id = comment.text("id")
                            guard !message.isEmpty, !id.isEmpty, seen.insert(id).inserted else { continue }
                            recent.append(id)
                            if recent.count > 300 { seen.remove(recent.removeFirst()) }
                            let author = comment["profile"].text("nickname")
                            continuation.yield(DanmakuEvent(
                                id: id, room: RoomKey(provider: .xiaohongshu, roomId: roomId), userName: author, message: message,
                                color: DanmakuColor(red: 255, green: 255, blue: 255), spans: [.text(message)]
                            ))
                        }
                        if let timestamp = data.integer("endTimestamp"), timestamp > 0 { cursor = String(timestamp) }
                        let interval = data.integer("nextRequestInterval") ?? 5000
                        try await Task.sleep(for: .milliseconds(min(60000, max(1000, interval))))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? nil : error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func comments(_ id: String, cursor: String) async throws -> JSONObject {
        let result = try await http.json(Self.live + "/api/sns/red/live/h5/v1/interaction/get_simple_interaction", query: [
            "roomId": id, "startTimestamp": cursor, "size": "10", "needPraise": "true", "needViewer": "true",
        ], headers: accountHeaders)
        guard result.fields["success"] as? Bool != false, result.fields["data"] is [String: Any] else {
            throw LiveProviderError.authenticationRequired
        }
        return result["data"]
    }
}
