import Foundation
import XCTest
@testable import SimpleLiveTVOS

@MainActor
final class ProviderQRLoginTests: XCTestCase {
    func testBilibiliSavesCookiesFromTicketRedirectAndRestoresAccount() async throws {
        let http = loginHTTP { request in
            switch request.url?.path {
            case "/x/passport-login/web/qrcode/poll":
                return .init(body: #"{"code":0,"data":{"code":0,"url":"https://passport.biligame.com/x/passport-login/web/crossDomain?ticket=fixture"}}"#)
            case "/x/passport-login/web/crossDomain":
                XCTAssertEqual(request.url?.host, "passport.biligame.com")
                XCTAssertEqual(request.url?.query, "ticket=fixture")
                XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
                return .init(status: 302, headers: ["Location": "https://passport.bilibili.com/complete"])
            case "/complete":
                XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
                return .init(status: 302, headers: [
                    "Set-Cookie": "DedeUserID=42; Domain=.bilibili.com; Path=/,SESSDATA=token%2Cpart%3D; Expires=Thu, 01 Jan 2099 10:00:00 GMT; Domain=.bilibili.com; Path=/,bili_jct=csrf; Domain=.bilibili.com; Path=/",
                    "Location": "https://www.bilibili.com/",
                ])
            default: return unexpectedRequest()
            }
        }
        let result = try await BilibiliService(loginHTTP: http).pollLogin(bilibiliChallenge())
        guard case let .authorized(cookie) = result else { return XCTFail("Expected a session") }
        let expected = "bili_jct=csrf; DedeUserID=42; SESSDATA=token%2Cpart%3D"
        let store = MemoryAccountStore()
        let core = NativeCoreClient(accountStore: store) { _, credential in
            XCTAssertEqual(credential.cookie, expected)
            return credential
        }
        try await core.finishLogin(cookie: cookie, provider: "bilibili")
        XCTAssertEqual(store.values[.bilibili]?.cookie, expected)

        let credentials = AccountRequestCredentials()
        let restarted = NativeCoreClient(accountStore: store, requestCredentials: credentials) { _, credential in credential }
        await restarted.start()
        XCTAssertEqual(restarted.accountStatus(.bilibili), .verified)
        XCTAssertEqual(credentials.credential(for: .bilibili)?.cookie, expected)
    }

    func testBilibiliUsesDirectPollCookieWithoutOpeningCallback() async throws {
        let http = loginHTTP { request in
            guard request.url?.path.hasSuffix("/poll") == true else { return unexpectedRequest() }
            return .init(
                headers: ["Set-Cookie": "SESSDATA=direct; Domain=.bilibili.com; Path=/"],
                body: #"{"code":0,"data":{"code":0,"url":"https://passport.biligame.com/crossDomain"}}"#
            )
        }
        guard case let .authorized(cookie) = try await BilibiliService(loginHTTP: http).pollLogin(bilibiliChallenge())
        else { return XCTFail("Expected a session") }
        XCTAssertEqual(cookie, "SESSDATA=direct")
    }

    func testBilibiliAcceptsSessionFromGamePassport() async throws {
        let http = loginHTTP { request in
            switch request.url?.host {
            case "passport.bilibili.com":
                return .init(body: #"{"code":0,"data":{"code":0,"url":"https://passport.biligame.com/x/passport-login/web/crossDomain?ticket=fixture"}}"#)
            case "passport.biligame.com":
                return .init(status: 302, headers: [
                    "Set-Cookie": "SESSDATA=from-ticket; Domain=.biligame.com; Path=/",
                    "Location": "https://www.bilibili.com/",
                ])
            default: return unexpectedRequest()
            }
        }
        guard case let .authorized(cookie) = try await BilibiliService(loginHTTP: http).pollLogin(bilibiliChallenge())
        else { return XCTFail("Expected a session") }
        XCTAssertEqual(cookie, "SESSDATA=from-ticket")
    }

    func testBilibiliRejectsRedirectOutsideLoginHosts() async throws {
        let http = loginHTTP { request in
            switch request.url?.host {
            case "passport.bilibili.com":
                return .init(body: #"{"code":0,"data":{"code":0,"url":"https://passport.biligame.com/crossDomain?ticket=fixture"}}"#)
            case "passport.biligame.com":
                return .init(status: 302, headers: ["Location": "https://example.com/complete"])
            default: return unexpectedRequest()
            }
        }
        do {
            _ = try await BilibiliService(loginHTTP: http).pollLogin(bilibiliChallenge())
            XCTFail("Accepted a redirect to an unrelated host")
        } catch LiveProviderError.invalidResponse {}
    }

    func testDouyuCarriesConfirmationCookiesAcrossRedirectsAndCollectsRefreshedToken() async throws {
        let http = loginHTTP { request in
            let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
            switch request.url?.path {
            case "/lapi/did/api/get":
                return .init(body: #"{"data":{"did":"device"}}"#)
            case "/scan/generateCode":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(cookie, "dy_did=device")
                return .init(body: #"{"error":0,"data":{"code":"fixture","url":"douyu://login"}}"#)
            case "/japi/scan/auth":
                return .init(body: #"{"error":0,"data":{"url":"/confirm"}}"#)
            case "/confirm":
                return .init(status: 302, headers: [
                    "Location": "/complete",
                    "Set-Cookie": "LTP0=refresh; Domain=.douyu.com; Path=/",
                ])
            case "/complete":
                XCTAssertEqual(cookie, "dy_did=device; LTP0=refresh")
                return .init(body: #"appClient_json_callback({"error":0});"#)
            case "/lapi/passport/iframe/safeAuth":
                XCTAssertEqual(cookie, "dy_did=device; LTP0=refresh")
                return .init(status: 302, headers: [
                    "Location": "/refreshed",
                    "Set-Cookie": "acf_jwt_token=new; Domain=.douyu.com; Path=/",
                ])
            default: return unexpectedRequest()
            }
        }
        let service = DouyuService(loginHTTP: http)
        let challenge = try await service.makeLoginChallenge()
        guard case let .authorized(cookie) = try await service.pollLogin(challenge)
        else { return XCTFail("Expected a session") }
        let validated = try await service.validate(cookie)
        XCTAssertEqual(validated, "acf_jwt_token=new; dy_did=device; LTP0=refresh")
    }

    private func bilibiliChallenge() -> LoginChallenge {
        LoginChallenge(url: URL(string: "https://account.bilibili.com")!, key: "fixture",
                       expiration: Date().addingTimeInterval(60))
    }

    private func loginHTTP(_ reply: @escaping (URLRequest) -> QRLoginURLProtocol.Reply) -> ProviderHTTP {
        QRLoginURLProtocol.reply = reply
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QRLoginURLProtocol.self]
        return ProviderHTTP(followsRedirects: false, configuration: configuration)
    }
}

private func unexpectedRequest() -> QRLoginURLProtocol.Reply {
    XCTFail("Unexpected QR login request")
    return .init(status: 500)
}

private final class QRLoginURLProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = ""
    }

    static var reply: ((URLRequest) -> Reply)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.reply?(request) ?? unexpectedRequest()
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                             headerFields: reply.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
