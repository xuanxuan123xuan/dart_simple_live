import CryptoKit
import Foundation
import JavaScriptCore
import SimpleLiveTVOSCore

actor DouyinService: LiveProviderService, DanmakuService {
    private static let live = "https://live.douyin.com"
    private static let web = "https://www.douyin.com"
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
    private static let baseQuery = [
        "aid": "6383", "app_name": "douyin_web", "live_id": "1", "device_platform": "web",
        "language": "zh-CN", "browser_language": "zh-CN", "browser_platform": "Win32",
        "browser_name": "Chrome", "browser_version": "125.0.0.0", "cookie_enabled": "true",
        "screen_width": "1920", "screen_height": "1080", "browser_online": "true",
    ]

    private var signer: JSContext?
    private var webcastSigner: JSContext?
    private var deviceCookies: [String: String] = [:]
    private var guestToken = ""
    private let http = ProviderHTTP()

    func categories() async throws -> [CategoryDescriptor] {
        let (data, _) = try await http.response(Self.live + "/", headers: headers())
        let html = String(decoding: data, as: UTF8.self)
        guard let marker = html.range(of: #"\"categoryData\":"#),
              let start = html[marker.upperBound...].firstIndex(of: "["),
              let array = Self.partitionArray(in: html[start...]) else { throw LiveProviderError.invalidResponse }
        let dataRoot = try JSONObject.decode(Data(("{\"categories\":" + array + "}").utf8))
        return Self.parseCategories(dataRoot.objects("categories"))
    }

    func rooms(in listing: RoomListing, page: Int) async throws -> RoomPage {
        switch listing {
        case let .search(keyword, mode):
            let result = try await signedRequest(Self.web + "/aweme/v1/web/live/search/", query: [
                "device_platform": "webapp", "channel": "channel_pc_web", "search_channel": "aweme_live",
                "search_source": "switch_tab", "query_correct_type": "1", "is_filter_search": "0",
                "keyword": keyword, "offset": String((page - 1) * 10), "count": "10", "from_group_id": "",
                "need_filter_settings": page == 1 ? "1" : "0", "list_type": "single", "pc_client_type": "1",
                "version_code": "170400", "version_name": "17.4.0", "update_version_code": "170400",
            ], path: "/")
            guard result.fields["data"] is [Any] else { throw LiveProviderError.authenticationRequired }
            let items = result.objects("data")
            let rooms = items.compactMap { item -> RoomDescriptor? in
                guard let raw = try? JSONObject.decode(Data(item["lives"].text("rawdata").utf8)) else { return nil }
                return Self.room(raw, author: raw["owner"], id: raw["owner"].text("web_rid"))
            }
            let results: [RoomDescriptor]
            if mode == .anchors {
                let matching = rooms.filter { $0.userName.localizedCaseInsensitiveContains(keyword) }
                let other = rooms.filter { !$0.userName.localizedCaseInsensitiveContains(keyword) }
                results = (matching + other).compactMap {
                    RoomDescriptor.anchor(provider: $0.provider, id: $0.roomId, name: $0.userName, avatar: "", isLive: true)
                }
            } else {
                results = rooms
            }
            return RoomPage(rooms: results, hasMore: result.integer("has_more").map { $0 > 0 } ?? (items.count >= 10))
        default:
            var partition = ["720", "1"]
            if case let .category(category) = listing { partition = category.categoryId.components(separatedBy: ",") }
            guard partition.count == 2, partition.allSatisfy({ Int($0).map { $0 > 0 } == true }) else {
                throw LiveProviderError.invalidResponse
            }
            let result = try await signedRequest(Self.live + "/webcast/web/partition/detail/room/v2/", query: [
                "enter_from": "link_share", "count": "15", "offset": String((page - 1) * 15),
                "partition": partition[0], "partition_type": partition[1], "req_from": "2",
            ])
            let data = result["data"]
            guard data.fields["data"] is [Any] else { throw LiveProviderError.authenticationRequired }
            let items = data.objects("data")
            let rooms = items.compactMap { Self.room($0["room"], author: $0["room"]["owner"], id: $0.text("web_rid")) }
            return RoomPage(rooms: rooms, hasMore: items.count >= 15)
        }
    }

    func resolveRoom(_ input: String) async throws -> RoomDescriptor {
        let id = try normalizedRoomID(input, hosts: ["live.douyin.com"])
        let detail = try await detail(id)
        guard let room = Self.room(detail.room, author: detail.author, id: id) else { throw LiveProviderError.invalidRoom }
        return room
    }

    func resolveReflow(_ roomID: String, secUserID: String?) async throws -> RoomDescriptor {
        guard roomID.range(of: #"^[0-9]{1,32}$"#, options: .regularExpression) != nil else {
            throw LiveProviderError.invalidRoom
        }
        let response = try await http.json("https://webcast.amemv.com/webcast/room/reflow/info/", query: [
            "type_id": "0", "live_id": "1", "room_id": roomID, "sec_user_id": secUserID ?? "",
            "version_code": "99.99.99", "app_id": "6383",
        ], headers: ["User-Agent": Self.userAgent, "Referer": Self.live + "/"])
        guard (response.integer("status_code") ?? 0) == 0 else { throw LiveProviderError.serviceUnavailable }
        let webID = response["data"]["room"]["owner"].text("web_rid")
        guard !webID.isEmpty else { throw LiveProviderError.invalidRoom }
        return try await resolveRoom(webID)
    }

    func qualities(roomId: String) async throws -> [LiveQuality] {
        try await variants(roomId).map(\.quality)
    }

    func playback(roomId: String, quality: LiveQuality) async throws -> [PlaybackResource] {
        let values = try await variants(roomId)
        guard let selection = values.first(where: { $0.quality.id == quality.id }) else { throw LiveProviderError.noPlayback }
        return selection.resources(headers: ["User-Agent": Self.userAgent, "Referer": Self.live + "/" + roomId])
    }

    private func detail(_ id: String) async throws -> (room: JSONObject, author: JSONObject) {
        let roomID = try normalizedRoomID(id, hosts: [])
        let response = try await signedRequest(Self.live + "/webcast/room/web/enter/", query: ["web_rid": roomID], path: "/" + roomID)
        let data = response["data"]
        let room = data.objects("data").first ?? JSONObject()
        let owner = room["owner"]
        let author = owner.text("nickname").isEmpty ? data["user"] : owner
        guard !room.fields.isEmpty || !author.fields.isEmpty else { throw LiveProviderError.invalidRoom }
        return (room, author)
    }

    private func variants(_ id: String) async throws -> [MediaVariant] {
        let (room, _) = try await detail(id)
        if room.integer("status") == 4 { throw LiveProviderError.offline }
        let streams = room["stream_url"]
        let pull = streams["live_core_sdk_data"]["pull_data"]
        let encoded = pull.text("stream_data")
        let sources = (try? JSONObject.decode(Data(encoded.utf8)))?["data"] ?? JSONObject()
        var seen = Set<String>()
        var result: [(Int, MediaVariant)] = []
        for quality in pull["options"].objects("qualities") {
            let key = quality.text("sdk_key")
            let name = quality.text("name")
            guard !key.isEmpty, !name.isEmpty, seen.insert(key).inserted else { continue }
            let main = sources[key]["main"]
            let urls = [MediaVariant.url(main.text("hls"), hint: .hls), MediaVariant.url(main.text("flv"), hint: .flv)].compactMap { $0 }
            if !urls.isEmpty {
                result.append((quality.integer("level") ?? 0, MediaVariant(quality: LiveQuality(id: key, name: name), urls: urls)))
            }
        }
        if result.isEmpty {
            let hls = streams["hls_pull_url_map"]
            let flv = streams["flv_pull_url"]
            for key in Set(hls.fields.keys).union(flv.fields.keys).sorted() {
                let values = [MediaVariant.url(hls.text(key), hint: .hls), MediaVariant.url(flv.text(key), hint: .flv)].compactMap { $0 }
                if !values.isEmpty { result.append((0, MediaVariant(quality: LiveQuality(id: key, name: key), urls: values))) }
            }
        }
        guard !result.isEmpty else { throw LiveProviderError.noPlayback }
        return result.sorted { $0.0 > $1.0 }.map(\.1)
    }

    private func signedURL(_ endpoint: String, query: [String: String]) async throws -> String {
        guard var url = URLComponents(string: endpoint) else { throw LiveProviderError.invalidResponse }
        if deviceCookies.isEmpty {
            do {
                let (_, response) = try await http.response(Self.live + "/", headers: headers())
                let values = receivedCookies(response, allowedDomains: ["douyin.com", "live.douyin.com"])
                for cookie in values where ["ttwid", "msToken"].contains(cookie.name) {
                    deviceCookies[cookie.name] = cookie.value
                }
            } catch {
                try Task.checkCancellation()
            }
        }
        var params = Self.baseQuery.merging(query) { _, new in new }
        if guestToken.isEmpty {
            let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
            guestToken = String((0..<107).compactMap { _ in alphabet.randomElement() })
        }
        params["msToken"] = deviceCookies["msToken"] ?? guestToken
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")
        let canonical = params.sorted { $0.key < $1.key }.map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
        if signer == nil {
            guard let script = Bundle.main.url(forResource: "DouyinABogus", withExtension: "js"), let context = JSContext() else {
                throw LiveProviderError.invalidResponse
            }
            context.evaluateScript(try String(contentsOf: script, encoding: .utf8))
            guard context.exception == nil else { throw LiveProviderError.invalidResponse }
            signer = context
        }
        guard let value = signer?.objectForKeyedSubscript("getABogus")?.call(withArguments: [canonical, Self.userAgent]),
              value.isString, let signed = value.toString(), !signed.isEmpty,
              let encoded = signed.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw LiveProviderError.invalidResponse
        }
        url.percentEncodedQuery = canonical + "&a_bogus=" + encoded
        guard let signed = url.url?.absoluteString else { throw LiveProviderError.invalidResponse }
        return signed
    }

    private func signedRequest(_ endpoint: String, query: [String: String], path: String = "/") async throws -> JSONObject {
        let url = try await signedURL(endpoint, query: query)
        let result = try await http.json(url, headers: headers(path: path, origin: endpoint.hasPrefix(Self.web) ? Self.web : Self.live))
        if let status = result.integer("status_code"), status != 0 { throw LiveProviderError.authenticationRequired }
        return result
    }

    nonisolated func danmaku(roomId: String) -> AsyncThrowingStream<DanmakuEvent, Error> {
        DanmakuConnection.stream { try await self.danmakuConnection(roomId) }
    }

    private func danmakuConnection(_ webID: String) async throws -> DanmakuConnection {
        let (room, _) = try await detail(webID)
        let id = room.text("id_str").isEmpty ? room.text("id") : room.text("id_str")
        guard UInt64(id) != nil else { throw LiveProviderError.invalidResponse }
        let uniqueID = String(UInt64.random(in: 100_000_000_000...999_999_999_999))
        let path = "/" + webID
        let time = Int(Date().timeIntervalSince1970 * 1000)
        var query = Self.baseQuery.merging([
            "version_code": "180800", "webcast_sdk_version": "1.3.0", "update_version_code": "1.3.0",
            "compress": "gzip", "resp_content_type": "protobuf", "cursor": "h-1_t-\(time)_r-1_d-1_u-1",
            "host": Self.live, "did_rule": "3", "debug": "false", "maxCacheMessageNumber": "20",
            "endpoint": "live_pc", "support_wrds": "1", "im_path": "/webcast/im/fetch/",
            "user_unique_id": uniqueID, "room_id": id, "identity": "audience", "heartbeatDuration": "0",
            "browser_name": "Mozilla", "browser_version": Self.userAgent.replacingOccurrences(of: "Mozilla/", with: ""),
            "tz_name": "Asia/Shanghai", "signature": try webcastSignature(room: id, user: uniqueID),
        ]) { _, new in new }
        var socketBase = "wss://webcast3-ws-web-lq.douyin.com/webcast/im/push/v2/"
        var heartbeat = 10_000
        do {
            let endpoint = try await signedURL(Self.live + "/webcast/im/fetch/", query: query)
            let (data, _) = try await http.response(endpoint, headers: headers(path: path))
            let content = data.starts(with: [0x1f, 0x8b]) ? try DanmakuCompression.inflate(data) : data
            let context = try ProtoMessage(content)
            let cursor = context.text(2).isEmpty ? context.text(11) : context.text(2)
            if !cursor.isEmpty {
                query["cursor"] = cursor
                if !context.text(5).isEmpty { query["internal_ext"] = context.text(5) }
            }
            let rate = context.number(8)
            if rate > 0 {
                heartbeat = Int(min(120_000, max(1_000, rate)))
                query["heartbeatDuration"] = String(heartbeat)
            }
            let server = context.text(10)
            if !server.isEmpty, let dynamic = URL(string: server.contains("://") ? server : "wss://" + server),
               dynamic.scheme == "wss", dynamic.user == nil, dynamic.password == nil,
               let host = dynamic.host, host.hasSuffix(".douyin.com") {
                socketBase = dynamic.path.isEmpty || dynamic.path == "/" ? "wss://\(host)/webcast/im/push/v2/" : dynamic.absoluteString
            }
        } catch {
            try Task.checkCancellation()
        }
        guard var parts = URLComponents(string: socketBase) else { throw LiveProviderError.invalidResponse }
        parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let socketURL = parts.url else { throw LiveProviderError.invalidResponse }
        var request = URLRequest(url: socketURL)
        request.allHTTPHeaderFields = headers(path: path)
        request.setValue(Self.live, forHTTPHeaderField: "Origin")
        return DanmakuConnection(request: request, initialFrames: [], heartbeatInterval: .milliseconds(heartbeat),
                                 heartbeat: DouyinDanmaku.heartbeat) { bytes in
            try DouyinDanmaku.decode(bytes, webID: webID)
        }
    }

    private func webcastSignature(room: String, user: String) throws -> String {
        if webcastSigner == nil {
            guard let source = Bundle.main.url(forResource: "DouyinWebcast", withExtension: "js"), let context = JSContext() else {
                throw LiveProviderError.invalidResponse
            }
            context.evaluateScript(try String(contentsOf: source, encoding: .utf8))
            guard context.exception == nil else { throw LiveProviderError.invalidResponse }
            webcastSigner = context
        }
        let fields = [
            "live_id=1", "aid=6383", "version_code=180800", "webcast_sdk_version=1.3.0",
            "room_id=\(room)", "sub_room_id=", "sub_channel_id=", "did_rule=3", "user_unique_id=\(user)",
            "device_platform=web", "device_type=", "ac=", "identity=audience",
        ].joined(separator: ",")
        let hash = Insecure.MD5.hash(data: Data(fields.utf8)).map { String(format: "%02x", $0) }.joined()
        guard let function = webcastSigner?.objectForKeyedSubscript("getMSSDKSignature") else {
            throw LiveProviderError.invalidResponse
        }
        var last: String?
        for _ in 0..<6 {
            guard let value = function.call(withArguments: [hash, Self.userAgent]),
                  value.isString, let text = value.toString(), !text.isEmpty else { throw LiveProviderError.invalidResponse }
            if !text.contains("-"), !text.contains("=") { return text }
            last = text
        }
        guard let last else { throw LiveProviderError.invalidResponse }
        return last
    }

    private func headers(path: String = "/", origin: String = DouyinService.live) -> [String: String] {
        var headers = ["Referer": origin + path, "User-Agent": Self.userAgent, "Accept": "application/json, text/plain, */*"]
        if !deviceCookies.isEmpty {
            headers["Cookie"] = deviceCookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        }
        return headers
    }

    private static func room(_ room: JSONObject, author: JSONObject, id: String) -> RoomDescriptor? {
        guard !id.isEmpty else { return nil }
        return RoomDescriptor(provider: "douyin", roomId: id, title: room.text("title"),
                              cover: normalizedImage(room["cover"].values("url_list").first as? String ?? ""),
                              userName: author.text("nickname"))
    }

    static func parseCategories(_ nodes: [JSONObject], parent: String = "", depth: Int = 0) -> [CategoryDescriptor] {
        guard depth < 16 else { return [] }
        return nodes.compactMap { node in
            let partition = node["partition"]
            let id = partition.text("id_str").isEmpty ? partition.text("id") : partition.text("id_str")
            let type = partition.text("type")
            let name = [partition.text("title"), partition.text("name"), partition.text("partition_name")].first { !$0.isEmpty } ?? ""
            guard Int(id) != nil, Int(type) != nil, !name.isEmpty else { return nil }
            let key = id + "," + type
            let children = parseCategories(node.objects("sub_partition"), parent: key, depth: depth + 1)
            return CategoryDescriptor(categoryId: key, name: name, parentId: parent, children: children)
        }
    }

    private static func partitionArray(in source: Substring) -> String? {
        var depth = 0
        var quoted = false
        var slashes = 0
        for index in source.indices {
            let character = source[index]
            if character == "\\" { slashes += 1; continue }
            if character == "\"" && slashes == 1 { quoted.toggle() }
            slashes = 0
            guard !quoted else { continue }
            if character == "[" { depth += 1 }
            if character == "]" {
                depth -= 1
                if depth == 0 {
                    return String(source[...index]).replacingOccurrences(of: #"\""#, with: "\"")
                        .replacingOccurrences(of: #"\/"#, with: "/").replacingOccurrences(of: #"\\"#, with: "\\")
                }
            }
        }
        return nil
    }
}
