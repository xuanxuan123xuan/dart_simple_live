import Foundation

enum XiaohongshuPhoneError: LocalizedError {
    case invalidAddress
    case invalidCode
    case disconnected
    case rejectedCode
    case expiredList
    case upstreamUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "请输入手机显示的局域网 IPv4 地址。"
        case .invalidCode: "请输入手机显示的六位连接码。"
        case .disconnected: "请让手机和 Apple TV 保持在同一局域网，并打开手机上的「小红书直播发现」。"
        case .rejectedCode: "连接码已失效，请用手机当前显示的连接码重新连接。"
        case .expiredList: "列表分页已失效，请刷新列表。"
        case .upstreamUnavailable: "手机暂时无法读取小红书列表，请稍后重试。"
        }
    }
}

struct XiaohongshuPhoneDiscovery: Sendable {
    private static let port = 23234
    private static let network: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 50
        return URLSession(configuration: configuration)
    }()
    private static let redirects = RejectRedirects()

    private let host: String
    private let code: String
    private let network: URLSession
    var address: String { "\(host):\(Self.port)" }

    init(address: String, code: String, network: URLSession? = nil) throws {
        let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = input.split(separator: ":", omittingEmptySubsequences: false)
        guard let host = fields.first,
              fields.count == 1 || (fields.count == 2 && fields[1] == String(Self.port)) else {
            throw XiaohongshuPhoneError.invalidAddress
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        guard parts.count == 4, octets.count == 4,
              octets.map(String.init).joined(separator: ".") == host,
              octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1]))
                || (octets[0] == 192 && octets[1] == 168) else {
            throw XiaohongshuPhoneError.invalidAddress
        }
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.utf8.count == 6, code.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw XiaohongshuPhoneError.invalidCode
        }
        self.host = String(host)
        self.code = code
        self.network = network ?? Self.network
    }

    func categories() async throws -> [CategoryDescriptor] {
        let payload: CategoryResponse = try await fetch("categories")
        return payload.categories.compactMap { category in
            guard category.id != "0", Self.isNumeric(category.id, length: 1...32),
                  !category.name.isEmpty else { return nil }
            return CategoryDescriptor(categoryId: category.id, name: category.name, parentId: "xiaohongshu")
        }
    }

    func rooms(category: String, page: Int, browseSession: UUID) async throws -> RoomPage {
        guard page > 0, Self.isNumeric(category, length: 1...32) else {
            throw LiveProviderError.invalidResponse
        }
        let payload: RoomResponse = try await fetch("rooms", query: [
            URLQueryItem(name: "category", value: category),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "session", value: browseSession.uuidString),
        ])
        let rooms = payload.rooms.compactMap { room -> RoomDescriptor? in
            guard Self.isNumeric(room.roomId, length: 8...32) else { return nil }
            var cover = URLComponents(string: normalizedImage(room.cover))
            if cover?.scheme == "http" { cover?.scheme = "https" }
            let image = cover.flatMap { url -> String? in
                guard url.scheme == "https", let host = url.host, !host.isEmpty,
                      url.user == nil, url.password == nil else { return nil }
                return url.url?.absoluteString
            }
            return RoomDescriptor(provider: "xiaohongshu", roomId: room.roomId,
                                  title: room.title, cover: image ?? "", userName: room.userName, isLive: true)
        }
        return RoomPage(rooms: rooms, hasMore: payload.hasMore)
    }

    private func fetch<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Self.port
        components.path = "/discovery/xiaohongshu/" + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw LiveProviderError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(code, forHTTPHeaderField: "X-SimpleLive-Pairing-Code")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result: (URLSession.AsyncBytes, URLResponse)
        do {
            result = try await network.bytes(for: request, delegate: Self.redirects)
        } catch {
            try Task.checkCancellation()
            throw XiaohongshuPhoneError.disconnected
        }
        defer { result.0.task.cancel() }
        guard let response = result.1 as? HTTPURLResponse else { throw LiveProviderError.invalidResponse }
        switch response.statusCode {
        case 200: break
        case 401: throw XiaohongshuPhoneError.rejectedCode
        case 409: throw XiaohongshuPhoneError.expiredList
        case 404, 503: throw XiaohongshuPhoneError.disconnected
        case 429, 502, 504: throw XiaohongshuPhoneError.upstreamUnavailable
        default: throw LiveProviderError.invalidResponse
        }
        var data = Data()
        do {
            for try await byte in result.0 {
                guard data.count < 256 * 1024 else { throw LiveProviderError.invalidResponse }
                data.append(byte)
            }
        } catch {
            try Task.checkCancellation()
            if let error = error as? LiveProviderError { throw error }
            throw XiaohongshuPhoneError.disconnected
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw LiveProviderError.invalidResponse
        }
    }

    private static func isNumeric(_ value: String, length: ClosedRange<Int>) -> Bool {
        length.contains(value.utf8.count) && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private struct CategoryResponse: Decodable {
        struct Category: Decodable {
            let id: String
            let name: String
        }
        let categories: [Category]
    }

    private struct RoomResponse: Decodable {
        struct Room: Decodable {
            let roomId: String
            let title: String
            let cover: String
            let userName: String
        }
        let rooms: [Room]
        let hasMore: Bool
    }

    private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
