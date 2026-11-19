import XCTest
@testable import SimpleLiveTVOS

final class SyncRemoteTests: XCTestCase {
    func testWebSocketEnvelopeAndProxyConfiguration() throws {
        let room = try RemoteSyncFrame(#"{"type":"roomCreated","requestId":"1","roomId":"ABC123"}"#)
        guard case .room("ABC123") = room else { return XCTFail("Expected room code") }
        let received = try RemoteSyncFrame(#"{"type":"historyReceived","payload":{"overlay":true,"content":"[]","chunkIndex":1}}"#)
        guard case let .content(category, fields, _) = received else { return XCTFail("Expected history data") }
        XCTAssertEqual(category, .histories)
        XCTAssertEqual(fields["content"] as? String, "[]")
        XCTAssertThrowsError(try RemoteSyncSettings(server: "https://server", proxy: "direct"))
        XCTAssertThrowsError(try RemoteSyncSettings(server: "wss://server/sync", proxy: "host:0"))
        XCTAssertNoThrow(try RemoteSyncSettings(server: "wss://server/sync", proxy: "http://host:51888"))
    }
}
