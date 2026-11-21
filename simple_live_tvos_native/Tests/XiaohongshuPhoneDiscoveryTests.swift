import Foundation
import XCTest
@testable import SimpleLiveTVOS

final class XiaohongshuPhoneDiscoveryTests: XCTestCase {
    func testAcceptsOnlySupportedLocalAddressesAndPairingCodes() throws {
        let phone = try XiaohongshuPhoneDiscovery(address: " 192.168.1.20 ", code: "012345")
        XCTAssertEqual(phone.address, "192.168.1.20:23234")
        XCTAssertNoThrow(try XiaohongshuPhoneDiscovery(address: "172.31.1.1:23234", code: "012345"))
        XCTAssertNoThrow(try XiaohongshuPhoneDiscovery(address: "10.0.1.1", code: "012345"))
        for address in ["172.32.1.1", "192.168.01.1", "127.0.0.1", "192.168.1.20:80",
                        "192.168.1.20/rooms", "http://192.168.1.20", "xiaohongshu.com"] {
            XCTAssertThrowsError(try XiaohongshuPhoneDiscovery(address: address, code: "012345"))
        }
        XCTAssertThrowsError(try XiaohongshuPhoneDiscovery(address: "192.168.1.20", code: "１２３４５６"))
    }

    func testDecodesCategoriesAndASecondPageWithOriginalRoomIDs() async throws {
        let phone = try makePhone(code: "012345")
        let categories = try await phone.categories()
        XCTAssertEqual(categories.map(\.categoryId), ["12"])
        XCTAssertEqual(categories.map(\.name), ["游戏"])

        let page = try await phone.rooms(category: "12", page: 2, browseSession: RelayProtocol.browseSession)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.rooms.map(\.roomId), ["570551217706532795"])
        XCTAssertEqual(page.rooms.first?.provider, "xiaohongshu")
        XCTAssertEqual(page.rooms.first?.cover, "https://sns.example.org/cover.jpg")
        XCTAssertEqual(page.rooms.first?.userName, "主播")
        XCTAssertEqual(page.rooms.first?.isLive, true)
    }

    func testDistinguishesExpiredListsAndPairingCodes() async throws {
        let phone = try makePhone(code: "012345")
        do {
            _ = try await phone.rooms(category: "12", page: 2, browseSession: UUID())
            XCTFail("An unknown pagination session should be rejected")
        } catch XiaohongshuPhoneError.expiredList {
        }

        let wrongCode = try makePhone(code: "999999")
        do {
            _ = try await wrongCode.categories()
            XCTFail("An incorrect pairing code should be rejected")
        } catch XiaohongshuPhoneError.rejectedCode {
        }
    }

    private func makePhone(code: String) throws -> XiaohongshuPhoneDiscovery {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RelayProtocol.self]
        return try XiaohongshuPhoneDiscovery(address: "192.168.1.20:23234", code: code,
                                             network: URLSession(configuration: configuration))
    }

    private final class RelayProtocol: URLProtocol, @unchecked Sendable {
        static let browseSession = UUID()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            guard let url = request.url else { return }
            let status: Int
            let data: String
            if request.value(forHTTPHeaderField: "X-SimpleLive-Pairing-Code") != "012345" {
                (status, data) = (401, "{}")
            } else if url.path == "/discovery/xiaohongshu/categories" {
                (status, data) = (200, #"{"categories":[{"id":"0","name":"全部"},{"id":"12","name":"游戏"}]}"#)
            } else if url.path == "/discovery/xiaohongshu/rooms",
                      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      items.contains(URLQueryItem(name: "category", value: "12")),
                      items.contains(URLQueryItem(name: "page", value: "2")),
                      items.contains(URLQueryItem(name: "session", value: Self.browseSession.uuidString)) {
                status = 200
                data = """
                    {"rooms":[{"roomId":"570551217706532795","title":"直播","cover":"//sns.example.org/cover.jpg","userName":"主播"},
                    {"roomId":"invalid","title":"无效房间","cover":"","userName":""}],"hasMore":true}
                    """
            } else {
                (status, data) = (409, "{}")
            }
            let headers = ["Content-Type": "application/json"]
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(data.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}
