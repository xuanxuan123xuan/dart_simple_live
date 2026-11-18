import Foundation
import SimpleLiveTVOSCore

struct ProviderDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let supportLabel: String
}

struct CategoryDescriptor: Identifiable, Hashable {
    let categoryId: String
    let name: String
    let parentId: String
    let children: [CategoryDescriptor]
    let canBrowseRooms: Bool
    var id: String { "\(parentId):\(categoryId)" }

    init(categoryId: String, name: String, parentId: String, children: [Self] = [], canBrowseRooms: Bool = true) {
        self.categoryId = categoryId
        self.name = name
        self.parentId = parentId
        var seen = Set<String>()
        self.children = children.filter { seen.insert($0.id).inserted }
        self.canBrowseRooms = canBrowseRooms
    }

    static func group(_ id: String, name: String, children: [Self]) -> Self {
        Self(categoryId: id, name: name, parentId: "", children: children, canBrowseRooms: false)
    }
}

struct RoomDescriptor: Identifiable, Hashable, Codable {
    let provider: String
    let roomId: String
    let title: String
    let cover: String
    let userName: String

    var id: String { key }
    var key: String { "\(provider):\(roomId)" }
}

struct RoomPage {
    let rooms: [RoomDescriptor]
    let hasMore: Bool
}

struct LiveQuality: Identifiable, Hashable {
    let id: String
    let name: String
}

enum LiveProviderError: LocalizedError {
    case unsupported
    case invalidResponse
    case invalidRoom
    case offline
    case authenticationRequired
    case rateLimited
    case serviceUnavailable
    case noPlayback
    case expired
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .unsupported: "此平台的相应功能尚未适配"
        case .invalidResponse: "平台返回的数据格式异常"
        case .invalidRoom: "请输入有效的直播间号或直播链接"
        case .offline: "直播间当前未开播"
        case .authenticationRequired: "平台要求登录或重新验证"
        case .rateLimited: "请求过于频繁，请稍后重试"
        case .serviceUnavailable: "暂时无法连接直播平台，请稍后重试"
        case .noPlayback: "平台没有返回可播放的线路"
        case .expired: "二维码已过期，请刷新后重试"
        case let .remote(message): message
        }
    }
}

enum RoomListing: Hashable {
    case recommended
    case category(CategoryDescriptor)
    case search(String)
}

protocol LiveProviderService: Sendable {
    func categories() async throws -> [CategoryDescriptor]
    func rooms(in listing: RoomListing, page: Int) async throws -> RoomPage
    func resolveRoom(_ input: String) async throws -> RoomDescriptor
    func qualities(roomId: String) async throws -> [LiveQuality]
    func playback(roomId: String, quality: LiveQuality) async throws -> [PlaybackResource]
}

protocol ProviderSessionService: Sendable {
    func restore(_ cookie: String?) async throws
    func validate(_ cookie: String) async throws
    func setVerifiedCookie(_ cookie: String?) async
    func makeLoginChallenge() async throws -> LoginChallenge
    func pollLogin(_ challenge: LoginChallenge) async throws -> LoginResult
}

struct LoginChallenge {
    let url: URL
    let key: String
    let expiration: Date
}

enum LoginResult {
    case waiting
    case scanned
    case authorized(String)
}

protocol DanmakuService: Sendable {
    func danmaku(roomId: String) -> AsyncThrowingStream<DanmakuEvent, Error>
}

final class ProviderHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let session: URLSession
    private let redirectHosts: Set<String>

    init(redirectHosts: Set<String> = []) {
        self.redirectHosts = redirectHosts
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }

    func response(_ endpoint: String, query: [String: String] = [:], headers: [String: String] = [:],
                  form: [String: String]? = nil) async throws -> (Data, HTTPURLResponse) {
        guard var parts = URLComponents(string: endpoint), parts.scheme == "https", parts.host != nil,
              parts.user == nil, parts.password == nil else {
            throw LiveProviderError.invalidResponse
        }
        if !query.isEmpty {
            parts.queryItems = (parts.queryItems ?? []) + query.sorted(by: { $0.key < $1.key }).map {
                URLQueryItem(name: $0.key, value: $0.value)
            }
            parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = parts.url else { throw LiveProviderError.invalidResponse }
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = headers
        if let form {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(form.sorted { $0.key < $1.key }.map {
                let name = $0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                let value = $0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                return "\(name)=\(value)"
            }.joined(separator: "&").utf8)
        }
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request, delegate: self)
        } catch {
            try Task.checkCancellation()
            throw LiveProviderError.serviceUnavailable
        }
        guard let response = result.1 as? HTTPURLResponse else { throw LiveProviderError.invalidResponse }
        switch response.statusCode {
        case 200..<300: return (result.0, response)
        case 401, 403, 406: throw LiveProviderError.authenticationRequired
        case 412, 429: throw LiveProviderError.rateLimited
        default: throw LiveProviderError.serviceUnavailable
        }
    }

    func json(_ endpoint: String, query: [String: String] = [:], headers: [String: String] = [:],
              form: [String: String]? = nil) async throws -> JSONObject {
        let (data, _) = try await response(endpoint, query: query, headers: headers, form: form)
        return try JSONObject.decode(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let destination = request.url, destination.scheme == "https",
              destination.user == nil, destination.password == nil,
              let host = destination.host?.lowercased() else {
            completionHandler(nil)
            return
        }
        if host == response.url?.host?.lowercased() {
            completionHandler(request)
        } else if redirectHosts.contains(host), destination.port == nil || destination.port == 443 {
            // Shared links are public. Start a fresh request across origins so credentials cannot follow the redirect.
            completionHandler(URLRequest(url: destination))
        } else {
            completionHandler(nil)
        }
    }
}

func receivedCookies(_ response: HTTPURLResponse, allowedDomains: Set<String>) -> [HTTPCookie] {
    guard let origin = response.url else { return [] }
    let fields = response.allHeaderFields.reduce(into: [String: String]()) { output, field in
        if let key = field.key as? String, let value = field.value as? String { output[key] = value }
    }
    return HTTPCookie.cookies(withResponseHeaderFields: fields, for: origin).filter {
        let domain = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return allowedDomains.contains(domain.lowercased()) && $0.value.rangeOfCharacter(from: .newlines) == nil
    }
}

func cookiePairs(_ header: String) -> [String: String] {
    header.split(separator: ";").reduce(into: [:]) { result, part in
        let pair = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        if pair.count == 2, !pair[0].isEmpty { result[String(pair[0]).lowercased()] = String(pair[1]) }
    }
}

struct JSONObject {
    let fields: [String: Any]

    init(_ fields: [String: Any] = [:]) {
        self.fields = fields
    }

    static func decode(_ data: Data) throws -> JSONObject {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LiveProviderError.invalidResponse
        }
        return JSONObject(object)
    }

    subscript(_ key: String) -> JSONObject { JSONObject(fields[key] as? [String: Any] ?? [:]) }
    func objects(_ key: String) -> [JSONObject] { (fields[key] as? [[String: Any]] ?? []).map(JSONObject.init) }
    func text(_ key: String) -> String {
        if let value = fields[key] as? String { return value }
        return (fields[key] as? NSNumber)?.stringValue ?? ""
    }
    func integer(_ key: String) -> Int? { Int(text(key)) }
    func values(_ key: String) -> [Any] { fields[key] as? [Any] ?? [] }
}

func normalizedRoomID(_ input: String, hosts: Set<String>) throws -> String {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let id: String
    if let url = URL(string: value), let host = url.host?.lowercased(),
       url.scheme == "https" || url.scheme == "http", url.user == nil, url.password == nil,
       hosts.contains(host) {
        id = url.pathComponents.last ?? ""
    } else {
        id = value
    }
    guard !id.isEmpty, id.utf8.count <= 64,
          id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
        throw LiveProviderError.invalidRoom
    }
    return id
}

func normalizedImage(_ value: String) -> String {
    value.hasPrefix("//") ? "https:" + value : value
}
