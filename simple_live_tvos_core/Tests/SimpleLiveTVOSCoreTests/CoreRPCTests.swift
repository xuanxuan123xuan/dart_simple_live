import XCTest
@testable import SimpleLiveTVOSCore

final class CoreRPCTests: XCTestCase {
    func testSuccessfulResponseRoundTrip() throws {
        let response = CoreRPCResponse(
            requestId: "1",
            ok: true,
            data: .object(["provider": .string("bilibili")])
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(CoreRPCResponse.self, from: data)
        XCTAssertEqual(decoded, response)
        XCTAssertNoThrow(try decoded.validate())
    }

    func testFailedResponseRequiresError() {
        let response = CoreRPCResponse(requestId: "1", ok: false)
        XCTAssertThrowsError(try response.validate())
    }
}
