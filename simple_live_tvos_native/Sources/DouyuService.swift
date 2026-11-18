import CryptoKit
import Foundation
import SimpleLiveTVOSCore

actor DouyuService: LiveProviderService, ProviderSessionService, DanmakuService {
    private static let web = "https://www.douyu.com"
    private static let passport = "https://passport.douyu.com"
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    private let http = ProviderHTTP()
    private let guestID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    private var cookie: String?
    private var challengeCookies: [String: String] = [:]
    private var challengeID: UUID?
    private var activeCode: String?

    func categories() async throws -> [CategoryDescriptor] {
        let data = try Self.payload(await http.json("https://m.douyu.com/api/cate/list"))
        return data.objects("cate2Info").compactMap {
            let id = $0.text("cate2Id")
            let name = $0.text("cate2Name")
            guard Int(id) != nil, !name.isEmpty else { return nil }
            return CategoryDescriptor(categoryId: id, name: name, parentId: $0.text("cate1Id"))
        }
    }

    func rooms(in listing: RoomListing, page: Int) async throws -> RoomPage {
        if case let .search(keyword) = listing {
            let data = try Self.payload(await http.json(Self.web + "/japi/search/api/searchShow", query: [
                "kw": keyword, "page": String(page), "pageSize": "20",
            ], headers: headers(path: "/search/")))
            guard data.fields["relateShow"] is [Any] else { throw LiveProviderError.invalidResponse }
            let items = data.objects("relateShow")
            return RoomPage(rooms: items.compactMap { Self.room($0, title: "roomName", cover: "roomSrc", name: "nickName") },
                            hasMore: items.count >= 20)
        }
        let path: String
        if case let .category(category) = listing {
            guard Int(category.categoryId) != nil else { throw LiveProviderError.invalidResponse }
            path = "/gapi/rkc/directory/mixList/2_\(category.categoryId)/\(page)"
        } else {
            path = "/japi/weblist/apinc/allpage/6/\(page)"
        }
        let data = try Self.payload(await http.json(Self.web + path, headers: headers()))
        guard let pages = data.integer("pgcnt") else { throw LiveProviderError.invalidResponse }
        return RoomPage(rooms: data.objects("rl").filter { $0.integer("type") == 1 }
            .compactMap { Self.room($0, title: "rn", cover: "rs16", name: "nn") }, hasMore: page < pages)
    }

    func resolveRoom(_ input: String) async throws -> RoomDescriptor {
        let id = try normalizedRoomID(input, hosts: ["www.douyu.com", "douyu.com", "m.douyu.com"])
        let data = try await http.json(Self.web + "/betard/" + id, headers: headers(path: "/" + id))["room"]
        let realID = data.text("room_id")
        guard let roomID = Int(realID), roomID > 0 else { throw LiveProviderError.invalidRoom }
        return RoomDescriptor(provider: "douyu", roomId: realID, title: data.text("room_name"),
                              cover: normalizedImage(data.text("room_pic")), userName: data.text("owner_name"))
    }

    func qualities(roomId: String) async throws -> [LiveQuality] {
        let credentials = credentials(for: roomId)
        let encryption = try await encryptionKey(credentials)
        let data = try await playInfo(roomId, rate: "-1", cdn: "", credentials: credentials, encryption: encryption)
        var seen = Set<String>()
        let result = data.objects("multirates").compactMap { item -> LiveQuality? in
            let id = item.text("rate")
            let name = item.text("name")
            guard Int(id) != nil, !name.isEmpty, seen.insert(id).inserted else { return nil }
            return LiveQuality(id: id, name: name)
        }
        guard !result.isEmpty else { throw LiveProviderError.noPlayback }
        return result
    }

    func playback(roomId: String, quality: LiveQuality) async throws -> [PlaybackResource] {
        let credentials = credentials(for: roomId)
        let encryption = try await encryptionKey(credentials)
        let first = try await playInfo(roomId, rate: quality.id, cdn: "", credentials: credentials, encryption: encryption)
        var resources: [PlaybackResource] = []
        var seen = Set<URL>()
        func append(_ data: JSONObject) {
            let base = data.text("rtmp_url").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let stream = data.text("rtmp_live").replacingOccurrences(of: "&amp;", with: "&")
            guard !base.isEmpty, !stream.isEmpty, let url = URL(string: base + "/" + stream),
                  let scheme = url.scheme, url.host != nil, seen.insert(url).inserted else { return }
            let kind: StreamProtocol
            switch (scheme, url.pathExtension.lowercased()) {
            case ("rtmp", _), ("rtmps", _): kind = .rtmp
            case ("http", "flv"), ("https", "flv"): kind = .flv
            case ("http", "m3u8"), ("https", "m3u8"): kind = .hls
            default: return
            }
            resources.append(PlaybackResource(url: url, protocolKind: kind,
                                              headers: ["Referer": Self.web + "/", "User-Agent": Self.userAgent],
                                              quality: quality.name, lineIndex: resources.count))
        }
        append(first)
        for cdn in first.objects("cdnsWithName").map({ $0.text("cdn") }).filter({ !$0.isEmpty && $0 != first.text("cdn") }).prefix(4) {
            do {
                append(try await playInfo(roomId, rate: quality.id, cdn: cdn, credentials: credentials, encryption: encryption))
            } catch {
                try Task.checkCancellation()
            }
        }
        guard !resources.isEmpty else { throw LiveProviderError.noPlayback }
        return resources
    }

    func restore(_ cookie: String?) async throws {
        if let cookie { try await validate(cookie) }
        setVerifiedCookie(cookie)
    }

    func setVerifiedCookie(_ cookie: String?) { self.cookie = cookie }

    func validate(_ cookie: String) async throws {
        let pairs = cookiePairs(cookie)
        guard cookie.rangeOfCharacter(from: .newlines) == nil,
              let id = pairs["dy_did"], !id.isEmpty, let token = pairs["ltp0"], !token.isEmpty else {
            throw LiveProviderError.authenticationRequired
        }
        let now = String(Int(Date().timeIntervalSince1970 * 1000))
        let (_, response) = try await http.response(Self.passport + "/lapi/passport/iframe/safeAuth",
            query: ["client_id": "1", "t": now, "_": now, "callback": "axiosJsonpCallback"],
            headers: ["Referer": Self.web + "/", "User-Agent": Self.userAgent, "Cookie": "dy_did=\(id); LTP0=\(token)"])
        let refreshed = receivedCookies(response, allowedDomains: ["passport.douyu.com", "douyu.com"])
        guard refreshed.contains(where: { $0.name.lowercased() == "acf_jwt_token" && !$0.value.isEmpty && ($0.expiresDate ?? .distantFuture) > Date() }) else {
            throw LiveProviderError.authenticationRequired
        }
    }

    func makeLoginChallenge() async throws -> LoginChallenge {
        let id = UUID()
        challengeID = id
        challengeCookies = [:]
        activeCode = nil
        let device = try await passportRequest("/lapi/did/api/get", id: id, query: ["client_id": "1", "callback": "slive_did"])
        let did = device["data"].text("did")
        if !did.isEmpty, did.rangeOfCharacter(from: .newlines) == nil { challengeCookies["dy_did"] = did }
        let result = try Self.payload(await passportRequest("/scan/generateCode", id: id, form: [
            "client_id": "1", "isMultiAccount": "0",
        ]))
        let code = result.text("code")
        guard !code.isEmpty, let url = URL(string: result.text("url")), let scheme = url.scheme,
              ["https", "douyu"].contains(scheme) else { throw LiveProviderError.invalidResponse }
        activeCode = code
        return LoginChallenge(url: url, key: code, expiration: Date().addingTimeInterval(180))
    }

    func pollLogin(_ challenge: LoginChallenge) async throws -> LoginResult {
        guard challenge.expiration > Date(), activeCode == challenge.key, let id = challengeID else {
            throw LiveProviderError.expired
        }
        let result = try await passportRequest("/japi/scan/auth", id: id,
            query: ["code": challenge.key, "time": String(Int(Date().timeIntervalSince1970 * 1000))])
        switch result.integer("error") {
        case -2: return .waiting
        case 1: return .scanned
        case -1: throw LiveProviderError.expired
        case 0:
            let confirmation = try await passportRequest(result["data"].text("url"), id: id,
                                                        query: ["callback": "appClient_json_callback"])
            _ = try Self.payload(confirmation)
            guard challengeCookies["dy_did"]?.isEmpty == false, challengeCookies["ltp0"]?.isEmpty == false else {
                throw LiveProviderError.authenticationRequired
            }
            let header = cookieHeader(challengeCookies)
            challengeID = nil
            challengeCookies = [:]
            activeCode = nil
            return .authorized(header)
        default: throw LiveProviderError.invalidResponse
        }
    }

    private func passportRequest(_ path: String, id: UUID, query: [String: String] = [:], form: [String: String]? = nil) async throws -> JSONObject {
        guard !path.isEmpty, let url = URL(string: path, relativeTo: URL(string: Self.passport + "/"))?.absoluteURL,
              url.scheme == "https", url.host == "passport.douyu.com" else { throw LiveProviderError.invalidResponse }
        let (bytes, response) = try await http.response(url.absoluteString, query: query, headers: [
            "Referer": Self.passport + "/", "Origin": Self.passport, "User-Agent": Self.userAgent,
            "Cookie": cookieHeader(challengeCookies),
        ], form: form)
        try Task.checkCancellation()
        guard challengeID == id else { throw CancellationError() }
        for cookie in receivedCookies(response, allowedDomains: ["passport.douyu.com", "douyu.com"]) {
            challengeCookies[cookie.name.lowercased()] = (cookie.expiresDate ?? .distantFuture) > Date() ? cookie.value : nil
        }
        if let result = try? JSONObject.decode(bytes) { return result }
        guard let source = String(data: bytes, encoding: .utf8),
              let start = source.firstIndex(of: "("), let end = source.lastIndex(of: ")"), start < end else {
            throw LiveProviderError.invalidResponse
        }
        return try JSONObject.decode(Data(source[source.index(after: start)..<end].utf8))
    }

    private func cookieHeader(_ cookies: [String: String]) -> String {
        cookies.sorted { $0.key < $1.key }.map { name, value in
            "\(name == "ltp0" ? "LTP0" : name)=\(value)"
        }.joined(separator: "; ")
    }

    private func headers(path: String = "/") -> [String: String] {
        var pairs = cookiePairs(cookie ?? "")
        if pairs["dy_did"]?.isEmpty != false { pairs["dy_did"] = guestID }
        if pairs["acf_did"]?.isEmpty != false { pairs["acf_did"] = pairs["dy_did"] }
        return ["Referer": Self.web + path, "User-Agent": Self.userAgent, "Cookie": cookieHeader(pairs), "Origin": Self.web]
    }

    private func credentials(for room: String) -> (did: String, headers: [String: String]) {
        (cookiePairs(cookie ?? "")["dy_did"] ?? guestID, headers(path: "/" + room))
    }

    private func encryptionKey(_ credentials: (did: String, headers: [String: String])) async throws -> JSONObject {
        try Self.payload(await http.json(Self.web + "/wgapi/livenc/liveweb/websec/getEncryption", query: [
            "did": credentials.did,
        ], headers: credentials.headers))
    }

    private func playInfo(_ room: String, rate: String, cdn: String, credentials: (did: String, headers: [String: String]), encryption: JSONObject) async throws -> JSONObject {
        let now = Int(Date().timeIntervalSince1970)
        let key = encryption.text("key")
        var secret = encryption.text("rand_str")
        let encData = encryption.text("enc_data")
        guard Int(room).map({ $0 > 0 }) == true, !key.isEmpty, !secret.isEmpty, !encData.isEmpty,
              let rounds = encryption.integer("enc_time"), (1...4096).contains(rounds),
              let expiration = encryption.integer("expire_at"), expiration > now else { throw LiveProviderError.invalidResponse }
        for _ in 0..<rounds { secret = Self.md5(secret + key) }
        let suffix = encryption.integer("is_special") == 1 ? "" : room + String(now)
        let form = ["enc_data": encData, "tt": String(now), "did": credentials.did, "auth": Self.md5(secret + key + suffix),
                    "cdn": cdn, "ver": "Douyu_new", "rate": rate, "hevc": "0", "ive": "0", "fa": "0"]
        return try Self.payload(await http.json(Self.web + "/lapi/live/getH5PlayV1/" + room, headers: credentials.headers, form: form))
    }

    private static func payload(_ response: JSONObject) throws -> JSONObject {
        guard response.integer("error") == 0 else { throw LiveProviderError.invalidResponse }
        return response["data"]
    }

    private static func room(_ item: JSONObject, title: String, cover: String, name: String) -> RoomDescriptor? {
        let id = item.text("rid")
        guard Int(id).map({ $0 > 0 }) == true else { return nil }
        return RoomDescriptor(provider: "douyu", roomId: id, title: item.text(title), cover: normalizedImage(item.text(cover)), userName: item.text(name))
    }

    private static func md5(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated func danmaku(roomId: String) -> AsyncThrowingStream<DanmakuEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
            let task = Task {
                for port in 8501...8503 {
                    do {
                        try Task.checkCancellation()
                        try await Self.receiveDanmaku(roomId: roomId, port: port, continuation: continuation)
                        continuation.finish()
                        return
                    } catch {
                        if Task.isCancelled { continuation.finish(); return }
                        if port == 8503 { continuation.finish(throwing: error) }
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func receiveDanmaku(roomId: String, port: Int, continuation: AsyncThrowingStream<DanmakuEvent, Error>.Continuation) async throws {
        guard Int(roomId).map({ $0 > 0 }) == true, let url = URL(string: "wss://danmuproxy.douyu.com:\(port)") else {
            throw LiveProviderError.invalidRoom
        }
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.maximumMessageSize = 256 * 1024
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        try await withTaskCancellationHandler {
            try await socket.send(.data(DouyuPackets.make("type@=loginreq/roomid@=\(roomId)/")))
            try await socket.send(.data(DouyuPackets.make("type@=joingroup/rid@=\(roomId)/gid@=-9999/")))
            let heartbeat = Task {
                while !Task.isCancelled {
                    try await socket.send(.data(DouyuPackets.make("type@=mrkl/")))
                    try await Task.sleep(for: .seconds(45))
                }
            }
            defer { heartbeat.cancel() }
            while !Task.isCancelled {
                if case let .data(bytes) = try await socket.receive() {
                    for message in DouyuPackets.messages(bytes, room: RoomKey(provider: .douyu, roomId: roomId)) {
                        continuation.yield(message)
                    }
                }
            }
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }
}

enum DouyuPackets {
    static func make(_ body: String) -> Data {
        let bytes = Data(body.utf8)
        let length = UInt32(bytes.count + 9)
        var data = Data()
        for value in [length, length, 689] {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(bytes)
        data.append(0)
        return data
    }

    static func messages(_ data: Data, room: RoomKey) -> [DanmakuEvent] {
        let bytes = Array(data)
        var result: [DanmakuEvent] = []
        var cursor = 0
        while bytes.count - cursor >= 13 {
            let length = (0..<4).reduce(0) { $0 | (Int(bytes[cursor + $1]) << (8 * $1)) }
            guard length >= 9, length <= bytes.count - cursor - 4 else { break }
            let end = cursor + 4 + length
            let text = String(decoding: bytes[(cursor + 12)..<(end - 1)], as: UTF8.self)
            cursor = end
            var fields: [String: String] = [:]
            for part in text.split(separator: "/") {
                guard let delimiter = part.range(of: "@=") else { continue }
                fields[String(part[..<delimiter.lowerBound])] = part[delimiter.upperBound...]
                    .replacingOccurrences(of: "@S", with: "/").replacingOccurrences(of: "@A", with: "@")
            }
            guard fields["type"] == "chatmsg", fields["dms"] != nil, let message = fields["txt"], !message.isEmpty else { continue }
            result.append(DanmakuEvent(id: UUID().uuidString, room: room, userName: fields["nn"] ?? "",
                                       message: message, color: DanmakuColor(red: 255, green: 255, blue: 255), spans: [.text(message)]))
        }
        return result
    }
}
