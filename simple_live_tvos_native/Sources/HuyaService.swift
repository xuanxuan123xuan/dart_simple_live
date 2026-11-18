import CryptoKit
import Foundation
import SimpleLiveTVOSCore

actor HuyaService: LiveProviderService, DanmakuService {
    private static let mobile = "https://m.huya.com/"
    private static let headers = [
        "Referer": mobile,
        "User-Agent": "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36",
    ]

    private let http = ProviderHTTP()

    func categories() async throws -> [CategoryDescriptor] {
        var result: [CategoryDescriptor] = []
        for type in ["1", "2", "8", "3"] {
            let json = try await http.json("https://live.cdn.huya.com/liveconfig/game/bussLive", query: ["bussType": type], headers: Self.headers)
            try Self.checkStatus(json)
            result += json.objects("data").compactMap { item in
                let raw = item.text("gid")
                let id = raw.isEmpty ? item["gid"].text("value").components(separatedBy: ",").first ?? "" : raw
                let name = item.text("gameFullName")
                guard !id.isEmpty, !name.isEmpty else { return nil }
                return CategoryDescriptor(categoryId: id, name: name, parentId: type)
            }
        }
        return result
    }

    func rooms(in listing: RoomListing, page: Int) async throws -> RoomPage {
        switch listing {
        case let .search(keyword):
            let offset = (page - 1) * 20
            let json = try await http.json("https://search.cdn.huya.com/", query: [
                "m": "Search", "do": "getSearchContent", "q": keyword, "uid": "0", "v": "4", "typ": "-5",
                "livestate": "0", "rows": "20", "start": String(offset),
            ], headers: Self.headers)["response"]["3"]
            guard let count = json.integer("numFound") else { throw LiveProviderError.invalidResponse }
            let rooms = json.objects("docs").compactMap {
                Self.room($0, idKey: "room_id", titleKeys: ["game_introduction", "game_roomName"],
                          coverKey: "game_screenshot", nameKey: "game_nick")
            }
            return RoomPage(rooms: rooms, hasMore: count > offset + 20)
        default:
            var query = ["m": "LiveList", "do": "getLiveListByPage", "tagAll": "0", "page": String(page)]
            if case let .category(category) = listing { query["gameId"] = category.categoryId }
            let json = try await http.json("https://www.huya.com/cache.php", query: query, headers: Self.headers)
            try Self.checkStatus(json)
            let data = json["data"]
            guard let total = data.integer("totalPage") else { throw LiveProviderError.invalidResponse }
            let rooms = data.objects("datas").compactMap {
                Self.room($0, idKey: "profileRoom", titleKeys: ["introduction", "roomName"], coverKey: "screenshot", nameKey: "nick")
            }
            return RoomPage(rooms: rooms, hasMore: page < total)
        }
    }

    func resolveRoom(_ input: String) async throws -> RoomDescriptor {
        let id = try normalizedRoomID(input, hosts: ["huya.com", "www.huya.com", "m.huya.com"])
        let data = try await detail(id)
        let live = data["roomInfo"]["tLiveInfo"]
        let title = [live.text("sIntroduction"), live.text("sRoomName")].first { !$0.isEmpty } ?? id
        let resolvedID = live.text("lProfileRoom")
        return RoomDescriptor(provider: "huya", roomId: resolvedID.isEmpty || resolvedID == "0" ? id : resolvedID,
                              title: title, cover: normalizedImage(live.text("sScreenshot")),
                              userName: data["roomInfo"]["tProfileInfo"].text("sNick"))
    }

    func qualities(roomId: String) async throws -> [LiveQuality] {
        let stream = try await liveDetail(roomId)["tLiveStreamInfo"]
        var seen = Set<String>()
        let qualities = stream["vBitRateInfo"].objects("value").compactMap { value -> LiveQuality? in
            let name = value.text("sDisplayName")
            let id = value.text("iBitRate")
            guard !name.isEmpty, !name.contains("HDR"), Int(id) != nil, seen.insert(id).inserted else { return nil }
            return LiveQuality(id: id, name: name)
        }
        return qualities.isEmpty ? [LiveQuality(id: "0", name: "原画")] : qualities
    }

    func playback(roomId: String, quality: LiveQuality) async throws -> [PlaybackResource] {
        let live = try await liveDetail(roomId)
        let stream = live["tLiveStreamInfo"]
        let uid = UInt64(live.text("lYyid")) ?? 0
        var resources: [PlaybackResource] = []
        var seen = Set<URL>()
        for (prefix, kind) in [("Hls", StreamProtocol.hls), ("Flv", .flv)] {
            for line in stream["vStreamInfo"].objects("value") {
                let name = line.text("sStreamName")
                let suffix = line.text("s\(prefix)UrlSuffix")
                let base = normalizedImage(line.text("s\(prefix)Url"))
                guard !name.isEmpty, !suffix.isEmpty, !base.isEmpty,
                      var url = URLComponents(string: "\(base)/\(name).\(suffix)"),
                      let scheme = url.scheme, ["https", "http"].contains(scheme), url.host != nil else { continue }
                url.queryItems = try Self.mediaQuery(line.text("s\(prefix)AntiCode"), stream: name, uid: uid, quality: quality.id)
                guard let resolved = url.url, seen.insert(resolved).inserted else { continue }
                resources.append(PlaybackResource(url: resolved, protocolKind: kind, headers: Self.headers,
                                                  quality: quality.name, lineIndex: resources.count))
            }
        }
        guard !resources.isEmpty else { throw LiveProviderError.noPlayback }
        return resources
    }

    private func liveDetail(_ id: String) async throws -> JSONObject {
        let room = try await detail(id)["roomInfo"]
        guard room.integer("eLiveStatus") == 2 else { throw LiveProviderError.offline }
        return room["tLiveInfo"]
    }

    private func detail(_ id: String) async throws -> JSONObject {
        let room = try normalizedRoomID(id, hosts: [])
        let (data, _) = try await http.response(Self.mobile + room, headers: Self.headers)
        guard let html = String(data: data, encoding: .utf8),
              let marker = html.range(of: #"window\.HNF_GLOBAL_INIT\s*=\s*"#, options: .regularExpression),
              let end = html.range(of: "</script>", range: marker.upperBound..<html.endIndex) else {
            throw LiveProviderError.invalidResponse
        }
        let source = html[marker.upperBound..<end.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: ";").union(.whitespacesAndNewlines))
            .replacingOccurrences(of: #"function.*?\(.*?\)\s*\{[\s\S]*?\}"#, with: "\"\"", options: .regularExpression)
        var parsed = try JSONObject.decode(Data(source.utf8)).fields
        for (key, name) in [("lChannelId", "_topSid"), ("lSubChannelId", "_subSid")] {
            let pattern = "\"" + key + "\"\\s*:\\s*(\\d+)"
            if let range = html.range(of: pattern, options: .regularExpression),
               let number = html[range].components(separatedBy: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                parsed[name] = number
            }
        }
        let result = JSONObject(parsed)
        guard !result["roomInfo"].fields.isEmpty else { throw LiveProviderError.invalidRoom }
        return result
    }

    nonisolated func danmaku(roomId: String) -> AsyncThrowingStream<DanmakuEvent, Error> {
        DanmakuConnection.stream { try await self.danmakuConnection(roomId) }
    }

    private func danmakuConnection(_ id: String) async throws -> DanmakuConnection {
        let detail = try await detail(id)
        let live = detail["roomInfo"]["tLiveInfo"]
        let uid = Int64(live.text("lYyid")) ?? 0
        let channel = Int64(detail.text("_topSid")) ?? Int64(live.text("lChannelId")) ?? 0
        let sub = Int64(detail.text("_subSid")) ?? channel
        guard channel > 0, let url = URL(string: "wss://cdnws.api.huya.com") else { throw LiveProviderError.invalidResponse }
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = Self.headers
        return DanmakuConnection(request: request, initialFrames: [HuyaDanmaku.join(uid: uid, channel: channel, subchannel: sub)],
            heartbeatInterval: .seconds(60), heartbeat: { Data([0, 20, 29, 0, 12, 44, 54, 0, 76]) }
        ) { bytes in
            (try HuyaDanmaku.decode(bytes, roomID: id).map { [$0] } ?? [], nil)
        }
    }

    private static func checkStatus(_ json: JSONObject) throws {
        guard json.integer("status") == 200 else { throw LiveProviderError.invalidResponse }
    }

    private static func room(_ data: JSONObject, idKey: String, titleKeys: [String], coverKey: String, nameKey: String) -> RoomDescriptor? {
        let id = data.text(idKey)
        guard !id.isEmpty else { return nil }
        let title = titleKeys.lazy.map { data.text($0) }.first { !$0.isEmpty } ?? id
        return RoomDescriptor(provider: "huya", roomId: id, title: title, cover: normalizedImage(data.text(coverKey)), userName: data.text(nameKey))
    }

    private static func mediaQuery(_ antiCode: String, stream: String, uid: UInt64, quality: String) throws -> [URLQueryItem] {
        var components = URLComponents()
        components.percentEncodedQuery = antiCode.replacingOccurrences(of: "&amp;", with: "&")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(CharacterSet(charactersIn: "%"))) ?? ""
        var query = (components.queryItems ?? []).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }

        if let fm = query["fm"], let time = query["wsTime"], let data = Data(base64Encoded: fm.removingPercentEncoding ?? fm),
           let prefix = String(data: data, encoding: .utf8)?.split(separator: "_").first {
            let ctype = query["ctype"] ?? "huya_pc_exe"
            let type = query["t"] ?? "0"
            let now = UInt64(Date().timeIntervalSince1970 * 1000)
            let sequence = uid + now
            let rotated = (uid & ~0xffffffff) | UInt64(UInt32(truncatingIfNeeded: uid) << 8 | UInt32(truncatingIfNeeded: uid) >> 24)
            let account = type == "103" ? uid : rotated
            let intermediate = md5("\(sequence)|\(ctype)|\(type)")
            query["wsSecret"] = md5("\(prefix)_\(account)_\(stream)_\(intermediate)_\(time)")
            query["seqid"] = String(sequence)
            query["ver"] = "1"
            if type == "103" {
                query["uid"] = String(uid)
                query["uuid"] = String(UInt32.random(in: 1...UInt32.max))
            } else {
                query["u"] = String(account)
            }
        }
        query["codec"] = "264"
        if let rate = Int(quality), rate > 0 { query["ratio"] = quality }
        return query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }

    private static func md5(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
