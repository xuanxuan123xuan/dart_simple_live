import Foundation
import Security

struct WebDAVCredentials: Codable, Equatable {
    var address: String = ""
    var user: String = ""
    var password: String = ""

    func endpoint() throws -> URL {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme ?? ""), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw SyncError.invalidAddress
        }
        return url
    }
}

struct WebDAVCredentialStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.xuanxuan.simplelive.tvos.webdav",
         kSecAttrAccount as String: "connection"]
    }

    func read() throws -> WebDAVCredentials? {
        var fields = query
        fields[kSecReturnData as String] = true
        fields[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(fields as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status) }
        guard let data = result as? Data else { throw KeychainError(errSecDecode) }
        return try JSONDecoder().decode(WebDAVCredentials.self, from: data)
    }

    func save(_ credentials: WebDAVCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecItemNotFound {
            var fields = query
            fields[kSecValueData as String] = data
            fields[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(fields as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(added) }
        } else if updated != errSecSuccess {
            throw KeychainError(updated)
        }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }
}

final class WebDAVSync {
    private let root: URL
    private let collection: URL
    private let backup: URL
    private let session: URLSession

    init(credentials: WebDAVCredentials) throws {
        root = try credentials.endpoint()
        collection = root.appendingPathComponent("simple_live_app", isDirectory: false)
        backup = collection.appendingPathComponent("backup.zip", isDirectory: false)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        session = URLSession(configuration: config, delegate: WebDAVAuthentication(credentials), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func verify() async throws {
        var request = URLRequest(url: root)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("<?xml version=\"1.0\"?><propfind xmlns=\"DAV:\"><propname/></propfind>".utf8)
        try await requireSuccess(request)
    }

    func upload(_ data: Data) async throws {
        guard data.count <= SyncProfile.maxBytes else { throw SyncError.tooLarge }
        var mkdir = URLRequest(url: collection)
        mkdir.httpMethod = "MKCOL"
        try await requireSuccess(mkdir, also: [405])
        var put = URLRequest(url: backup)
        put.httpMethod = "PUT"
        put.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: put, from: data)
        try Self.check(response)
    }

    func download() async throws -> Data {
        let (bytes, response) = try await session.bytes(from: backup)
        try Self.check(response)
        guard response.expectedContentLength <= SyncProfile.maxBytes else { throw SyncError.tooLarge }
        var data = Data()
        if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
        for try await byte in bytes {
            guard data.count < SyncProfile.maxBytes else { throw SyncError.tooLarge }
            data.append(byte)
        }
        return data
    }

    private func requireSuccess(_ request: URLRequest, also: Set<Int> = []) async throws {
        let (_, response) = try await session.bytes(for: request)
        try Self.check(response, also: also)
    }

    private static func check(_ response: URLResponse, also: Set<Int> = []) throws {
        guard let reply = response as? HTTPURLResponse else { throw SyncError.connectionFailed }
        guard (200..<300).contains(reply.statusCode) || also.contains(reply.statusCode) else {
            throw SyncError.httpStatus(reply.statusCode)
        }
    }
}

private final class WebDAVAuthentication: NSObject, URLSessionTaskDelegate {
    private let credentials: WebDAVCredentials

    init(_ credentials: WebDAVCredentials) { self.credentials = credentials }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest].contains(space.authenticationMethod),
              !space.isProxy(), challenge.previousFailureCount == 0,
              space.host.lowercased() == (try? credentials.endpoint().host?.lowercased()) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(user: credentials.user, password: credentials.password, persistence: .none))
    }
}
