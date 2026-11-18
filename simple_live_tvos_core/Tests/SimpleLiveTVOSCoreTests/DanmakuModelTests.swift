import XCTest
@testable import SimpleLiveTVOSCore

final class DanmakuModelTests: XCTestCase {
    func testColorIsClamped() {
        let color = DanmakuColor(red: -1, green: 128, blue: 300)
        XCTAssertEqual(color, DanmakuColor(red: 0, green: 128, blue: 255))
    }

    func testMixedSpansRoundTrip() throws {
        let event = DanmakuEvent(
            id: "m1",
            room: RoomKey(provider: .bilibili, roomId: "100"),
            userName: "user",
            message: "hello",
            color: DanmakuColor(red: 255, green: 255, blue: 255),
            spans: [.text("hello"), .image(url: URL(string: "https://img.example/a.png")!, fallbackText: "[表情]")]
        )
        let encoded = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(DanmakuEvent.self, from: encoded), event)
    }
}
