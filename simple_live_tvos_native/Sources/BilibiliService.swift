import Compression
import CryptoKit
import Foundation
import SimpleLiveTVOSCore

actor BilibiliService: LiveProviderService, ProviderSessionService, DanmakuService {
    private static let web = "https://api.bilibili.com"
    private static let live = "https://api.live.bilibili.com"
    private static let passport = "https://passport.bilibili.com/x/passport-login/web/qrcode"
    private static let mediaHeaders = [
        "Referer": "https://live.bilibili.com/",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
    ]
    private static let keyOrder = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
    ]

    private let http = ProviderHTTP()
    private let accounts: AccountRequestCredentials
    private var cookie: String? { accounts.credential(for: .bilibili)?.cookie }
    private var deviceCookies: [String] = []
    private var mixin: (key: String, expiration: Date, cookie: String?)?

    init(accounts: AccountRequestCredentials = AccountRequestCredentials()) {
        self.accounts = accounts
    }

    func validate(_ cookie: String) async throws -> String {
        guard try AccountCookie(cookie)["SESSDATA"] != nil else {
            throw LiveProviderError.authenticationRequired
        }
        var headers = Self.mediaHeaders
        headers["Cookie"] = cookie
        let result = try await http.json(Self.web + "/x/web-interface/nav", headers: headers)
        guard result["data"].fields["isLogin"] as? Bool == true else {
            throw LiveProviderError.authenticationRequired
        }
        return cookie
    }

    func makeLoginChallenge() async throws -> LoginChallenge {
        let data = try Self.payload(await http.json(Self.passport + "/generate", headers: Self.mediaHeaders))
        let key = data.text("qrcode_key")
        guard !key.isEmpty, let url = URL(string: data.text("url")), url.scheme == "https",
              let host = url.host, ["account.bilibili.com", "passport.bilibili.com"].contains(host),
              url.user == nil, url.password == nil else { throw LiveProviderError.invalidResponse }
        return LoginChallenge(url: url, key: key, expiration: Date().addingTimeInterval(180))
    }

    func pollLogin(_ challenge: LoginChallenge) async throws -> LoginResult {
        guard challenge.expiration > Date() else { throw LiveProviderError.expired }
        let (body, response) = try await http.response(
            Self.passport + "/poll", query: ["qrcode_key": challenge.key], headers: Self.mediaHeaders
        )
        let data = try Self.payload(JSONObject.decode(body))
        switch data.integer("code") {
        case 86101: return .waiting
        case 86090: return .scanned
        case 86038: throw LiveProviderError.expired
        case 0:
            let cookies = receivedCookies(response, allowedDomains: ["bilibili.com", "passport.bilibili.com", "account.bilibili.com"])
            guard cookies.contains(where: { $0.name == "SESSDATA" && !$0.value.isEmpty }) else {
                throw LiveProviderError.authenticationRequired
            }
            return .authorized(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
        default: throw LiveProviderError.invalidResponse
        }
    }

    func categories() async throws -> [CategoryDescriptor] {
        let result = try await request(Self.live + "/room/v1/Area/getList", ["need_entrance": "1", "parent_id": "0"])
        _ = try Self.payload(result)
        return result.objects("data").compactMap { parent in
            let parentID = parent.text("id")
            let parentName = parent.text("name")
            guard !parentID.isEmpty, !parentName.isEmpty else { return nil }
            let children = parent.objects("list").compactMap { child -> CategoryDescriptor? in
                let id = child.text("id")
                let name = child.text("name")
                guard !id.isEmpty, !name.isEmpty else { return nil }
                return CategoryDescriptor(categoryId: id, name: name, parentId: parentID)
            }
            return .group(parentID, name: parentName, children: children)
        }
    }

    func rooms(in listing: RoomListing, page: Int) async throws -> RoomPage {
        let query = ["platform": "web", "page_size": "30", "page": String(page)]
        let items: [JSONObject]
        let limit: Int
        switch listing {
        case .recommended:
            let signed = try await sign(query.merging(["sort": "online"]) { _, new in new })
            items = try Self.payload(await request(Self.live + "/xlive/web-interface/v1/second/getListByArea", signed)).objects("list")
            limit = 30
        case let .category(category):
            let result = try await request(Self.live + "/room/v1/Area/getRoomList", query.merging([
                "area_id": category.categoryId, "parent_area_id": category.parentId,
            ]) { _, new in new })
            _ = try Self.payload(result)
            items = result.objects("data")
            limit = 30
        case let .search(keyword, mode):
            if mode == .anchors {
                let data = try Self.payload(await request(Self.web + "/x/web-interface/search/type", [
                    "search_type": "live_user", "cover_type": "user_cover", "keyword": keyword,
                    "page": String(page), "highlight": "0",
                ]))
                let items = data.objects("result")
                let rooms = items.compactMap {
                    RoomDescriptor.anchor(provider: "bilibili", id: $0.text("roomid"), name: $0.text("uname"),
                                          avatar: $0.text("uface"), isLive: $0.bool("is_live"))
                }
                return RoomPage(rooms: rooms, hasMore: data.integer("numPages").map { page < $0 } ?? (items.count >= 40))
            }
            let result = try Self.payload(await request(Self.web + "/x/web-interface/search/type", [
                "search_type": "live", "cover_type": "user_cover", "keyword": keyword,
                "page": String(page), "highlight": "0",
            ]))
            items = result["result"].objects("live_room")
            limit = 40
        }
        return RoomPage(rooms: items.compactMap {
            let id = $0.text("roomid")
            guard !id.isEmpty else { return nil }
            let cover = [$0.text("cover"), $0.text("user_cover"), $0.text("system_cover")].first { !$0.isEmpty } ?? ""
            return RoomDescriptor(provider: "bilibili", roomId: id, title: $0.text("title")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression),
                cover: normalizedImage(cover), userName: $0.text("uname"))
        }, hasMore: items.count >= limit)
    }

    func resolveRoom(_ input: String) async throws -> RoomDescriptor {
        let id = try normalizedRoomID(input, hosts: ["live.bilibili.com"])
        guard Int(id).map({ $0 > 0 }) == true else { throw LiveProviderError.invalidRoom }
        let data = try await detail(id)
        let room = data["room_info"]
        let realID = room.text("room_id")
        guard !realID.isEmpty else { throw LiveProviderError.invalidRoom }
        return RoomDescriptor(provider: "bilibili", roomId: realID, title: room.text("title"),
                              cover: normalizedImage(room.text("cover")), userName: data["anchor_info"]["base_info"].text("uname"),
                              isLive: room.integer("live_status").flatMap { [0, 1, 2].contains($0) ? $0 == 1 : nil })
    }

    func qualities(roomId: String) async throws -> [LiveQuality] {
        let play = try await playInfo(roomId, qn: nil)
        let accepted = Set(play.objects("stream").flatMap { $0.objects("format") }
            .flatMap { $0.objects("codec") }.flatMap { $0.values("accept_qn") }
            .compactMap { ($0 as? NSNumber)?.stringValue ?? $0 as? String })
        let ordered = play.objects("g_qn_desc").compactMap { entry -> LiveQuality? in
            let qn = entry.text("qn")
            guard accepted.contains(qn) else { return nil }
            return LiveQuality(id: qn, name: entry.text("desc"), recoveryRank: Int(qn))
        }
        guard !ordered.isEmpty else { throw LiveProviderError.noPlayback }
        return ordered
    }

    func playback(roomId: String, quality: LiveQuality) async throws -> [PlaybackResource] {
        let play = try await playInfo(roomId, qn: quality.id)
        let formats = play.objects("stream").flatMap { $0.objects("format") }
        var urls: [(URL, StreamProtocol)] = []
        var seen = Set<URL>()
        for format in formats {
            let kind: StreamProtocol
            switch format.text("format_name") {
            case "ts", "fmp4": kind = .hls
            case "flv": kind = .flv
            default: continue
            }
            for codec in format.objects("codec") {
                let path = codec.text("base_url")
                guard !path.isEmpty else { continue }
                for line in codec.objects("url_info") {
                    guard let url = URL(string: line.text("host") + path + line.text("extra")),
                          let scheme = url.scheme, ["http", "https"].contains(scheme),
                          url.host != nil, seen.insert(url).inserted else { continue }
                    urls.append((url, kind))
                }
            }
        }
        let sorted = urls.enumerated().sorted { lhs, rhs in
            let left = (lhs.element.1 == .hls ? 0 : 1, lhs.element.0.host?.contains("mcdn") == true ? 1 : 0, lhs.offset)
            let right = (rhs.element.1 == .hls ? 0 : 1, rhs.element.0.host?.contains("mcdn") == true ? 1 : 0, rhs.offset)
            return left < right
        }
        guard !sorted.isEmpty else { throw LiveProviderError.noPlayback }
        return sorted.enumerated().map { index, item in
            PlaybackResource(url: item.element.0, protocolKind: item.element.1, headers: Self.mediaHeaders, quality: quality.name, lineIndex: index)
        }
    }

    nonisolated func danmaku(roomId: String) -> AsyncThrowingStream<DanmakuEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
            let task = Task {
                for attempt in 0..<3 {
                    do {
                        try Task.checkCancellation()
                        try await receiveDanmaku(roomId: roomId, continuation: continuation)
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        continuation.finish()
                        return
                    } catch {
                        if attempt == 2 {
                            continuation.finish(throwing: error)
                        } else {
                            do { try await Task.sleep(for: .seconds(2 << attempt)) }
                            catch { continuation.finish(); return }
                        }
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func receiveDanmaku(roomId: String, continuation: AsyncThrowingStream<DanmakuEvent, Error>.Continuation) async throws {
        let query = try await sign(["id": roomId, "type": "0"])
        let data = try Self.payload(await request(Self.live + "/xlive/web-room/v1/index/getDanmuInfo", query))
        let token = data.text("token")
        let host = data.objects("host_list").map { $0.text("host") }.first { $0.hasSuffix(".bilibili.com") }
        guard !token.isEmpty, let host, let url = URL(string: "wss://\(host)/sub"),
              url.host == host, let id = Int(roomId) else { throw LiveProviderError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("https://live.bilibili.com", forHTTPHeaderField: "Origin")
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.maximumMessageSize = 4 * 1024 * 1024
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        let buvid = cookieValue("buvid3") ?? deviceCookies.first { $0.hasPrefix("buvid3=") }
            .map { String($0.dropFirst("buvid3=".count)) } ?? ""
        let join = try JSONSerialization.data(withJSONObject: [
            "roomid": id, "uid": Int(cookieValue("DedeUserID") ?? "") ?? 0,
            "protover": 2, "platform": "web", "type": 2, "buvid": buvid, "key": token,
        ])
        try await socket.send(.data(BilibiliPacket.make(operation: 7, body: join)))
        let heartbeat = Task {
            while !Task.isCancelled {
                try await socket.send(.data(BilibiliPacket.make(operation: 2)))
                try await Task.sleep(for: .seconds(30))
            }
        }
        defer { heartbeat.cancel() }
        try await withTaskCancellationHandler {
            while !Task.isCancelled {
                if case let .data(body) = try await socket.receive() {
                    for message in BilibiliPacket.messages(body, room: RoomKey(provider: .bilibili, roomId: roomId)) {
                        continuation.yield(message)
                    }
                }
            }
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    private func cookieValue(_ key: String) -> String? {
        cookie?.split(separator: ";").lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) }
    }

    private func detail(_ roomID: String) async throws -> JSONObject {
        let query = try await sign(["room_id": roomID])
        return try Self.payload(await request(Self.live + "/xlive/web-room/v1/index/getInfoByRoom", query))
    }

    private func playInfo(_ roomId: String, qn: String?) async throws -> JSONObject {
        var query = ["room_id": roomId, "platform": "web", "protocol": "0,1", "format": "0,1,2", "codec": "0,1"]
        query["qn"] = qn
        let data = try Self.payload(await request(Self.live + "/xlive/web-room/v2/index/getRoomPlayInfo", query))
        if let status = data.integer("live_status"), status == 0 || status == 2 { throw LiveProviderError.offline }
        let play = data["playurl_info"]["playurl"]
        guard !play.fields.isEmpty else { throw LiveProviderError.noPlayback }
        return play
    }

    private func request(_ endpoint: String, _ query: [String: String] = [:]) async throws -> JSONObject {
        try await http.json(endpoint, query: query, headers: headers())
    }

    private func headers() async throws -> [String: String] {
        var headers = Self.mediaHeaders
        if deviceCookies.isEmpty, cookieValue("buvid3") == nil {
            do {
                let response = try await http.json(Self.web + "/x/frontend/finger/spi", headers: headers)
                for (key, name) in [("b_3", "buvid3"), ("b_4", "buvid4")] {
                    let value = response["data"].text(key)
                    if !value.isEmpty, value.rangeOfCharacter(from: .newlines) == nil { deviceCookies.append("\(name)=\(value)") }
                }
            } catch {
                try Task.checkCancellation()
            }
        }
        let components = (cookie.map { [$0] } ?? []) + deviceCookies.filter {
            guard let name = $0.split(separator: "=", maxSplits: 1).first else { return false }
            return cookieValue(String(name)) == nil
        }
        if !components.isEmpty { headers["Cookie"] = components.joined(separator: "; ") }
        return headers
    }

    private func sign(_ input: [String: String]) async throws -> [String: String] {
        let now = Date()
        let key: String
        let accountCookie = cookie
        if let mixin, mixin.expiration > now, mixin.cookie == accountCookie {
            key = mixin.key
        } else {
            let data = try await request(Self.web + "/x/web-interface/nav")
            let wbi = data["data"]["wbi_img"]
            let bytes = ["img_url", "sub_url"].compactMap { URL(string: wbi.text($0))?.deletingPathExtension().lastPathComponent }.joined().utf8
            guard bytes.count >= 64 else { throw LiveProviderError.invalidResponse }
            let values = Array(bytes)
            key = String(decoding: Self.keyOrder.map { values[$0] }, as: UTF8.self)
            mixin = (key, now.addingTimeInterval(1800), accountCookie)
        }
        var query = input.mapValues { $0.filter { !"!'()*".contains($0) } }
        query["wts"] = String(Int(now.timeIntervalSince1970))
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")
        let canonical = query.sorted { $0.key < $1.key }.map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
        query["w_rid"] = Insecure.MD5.hash(data: Data((canonical + key).utf8)).map { String(format: "%02x", $0) }.joined()
        return query
    }

    private static func payload(_ response: JSONObject) throws -> JSONObject {
        switch response.integer("code") {
        case 0: return response["data"]
        case -101, -403, -352: throw LiveProviderError.authenticationRequired
        case -412, -509: throw LiveProviderError.rateLimited
        default: throw LiveProviderError.invalidResponse
        }
    }
}

enum BilibiliPacket {
    static func make(operation: UInt32, body: Data = Data()) -> Data {
        var data = Data()
        for value in [UInt32(16 + body.count), 0x00100001, operation, 1] {
            var number = value.bigEndian
            withUnsafeBytes(of: &number) { data.append(contentsOf: $0) }
        }
        data.append(body)
        return data
    }

    static func messages(_ data: Data, room: RoomKey, depth: Int = 0) -> [DanmakuEvent] {
        guard depth < 3, data.count <= 4 * 1024 * 1024 else { return [] }
        let bytes = Array(data)
        func number(_ at: Int, count: Int) -> Int {
            bytes[at..<at + count].reduce(0) { ($0 << 8) | Int($1) }
        }
        var cursor = 0
        var events: [DanmakuEvent] = []
        while bytes.count - cursor >= 16 {
            let length = number(cursor, count: 4)
            let header = number(cursor + 4, count: 2)
            guard header >= 16, length >= header, length <= bytes.count - cursor else { break }
            let version = number(cursor + 6, count: 2)
            let operation = number(cursor + 8, count: 4)
            let body = Data(bytes[cursor + header..<cursor + length])
            cursor += length
            guard operation == 5 else { continue }
            if version == 2, let inflated = inflate(body) {
                events.append(contentsOf: messages(inflated, room: room, depth: depth + 1))
            } else if version <= 1, let json = try? JSONObject.decode(body),
                      json.text("cmd").hasPrefix("DANMU_MSG"),
                      case let info = json.values("info"), info.count >= 3,
                      let message = info[1] as? String, !message.isEmpty,
                      let author = info[2] as? [Any], author.count >= 2, let name = author[1] as? String {
                let attributes = info[0] as? [Any] ?? []
                let color = attributes.count > 3 ? (attributes[3] as? Int ?? 0xffffff) : 0xffffff
                events.append(DanmakuEvent(id: UUID().uuidString, room: room, userName: name, message: message,
                                           color: DanmakuColor(red: (color >> 16) & 255, green: (color >> 8) & 255, blue: color & 255),
                                           spans: stickerSpans(message: message, attributes: attributes)))
            }
            if events.count >= 128 { return Array(events.prefix(128)) }
        }
        return events
    }

    static func stickerSpans(message: String, attributes: [Any]) -> [DanmakuSpan] {
        var stickers: [String: URL] = [:]
        if attributes.count > 13, message.hasPrefix("["), message.hasSuffix("]"),
           let direct = (attributes[13] as? [String: Any])?["url"] as? String,
           let url = DanmakuStickerURL.bilibili(direct) {
            stickers[message] = url
        }
        if attributes.count > 15, let extra = (attributes[15] as? [String: Any])?["extra"] as? String,
           extra.utf8.count < 16 * 1024, let metadata = try? JSONObject.decode(Data(extra.utf8)) {
            for (key, entry) in metadata["emots"].fields.prefix(32) {
                guard !key.isEmpty, key.count < 64, message.contains(key),
                      let url = DanmakuStickerURL.bilibili(JSONObject(entry as? [String: Any] ?? [:]).text("url")) else { continue }
                stickers[key] = url
            }
        }
        guard !stickers.isEmpty else { return [.text(message)] }
        var spans = [DanmakuSpan]()
        var cursor = message.startIndex
        while cursor < message.endIndex, spans.count < 24 {
            let matches = stickers.keys.compactMap { key in message.range(of: key, range: cursor..<message.endIndex).map { (key, $0) } }
            guard let (key, range) = matches.min(by: {
                $0.1.lowerBound == $1.1.lowerBound ? $0.0.count > $1.0.count : $0.1.lowerBound < $1.1.lowerBound
            }), let url = stickers[key] else { break }
            if cursor < range.lowerBound { spans.append(.text(String(message[cursor..<range.lowerBound]))) }
            spans.append(.image(url: url, fallbackText: key))
            cursor = range.upperBound
        }
        if cursor < message.endIndex { spans.append(.text(String(message[cursor...]))) }
        return spans
    }

    private static func inflate(_ data: Data) -> Data? {
        guard data.count > 6, data.first == 0x78 else { return nil }
        let raw = Data(data.dropFirst(2).dropLast(4))
        let capacity = 4 * 1024 * 1024
        var output = Data(count: capacity)
        let decoded = output.withUnsafeMutableBytes { destination in
            raw.withUnsafeBytes { input in
                guard let source = input.bindMemory(to: UInt8.self).baseAddress,
                      let target = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(target, capacity, source, raw.count, nil, COMPRESSION_ZLIB)
            }
        }
        return decoded > 0 && decoded < capacity ? Data(output.prefix(decoded)) : nil
    }
}
