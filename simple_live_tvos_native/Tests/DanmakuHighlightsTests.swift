@testable import SimpleLiveTVOS
import XCTest

final class DanmakuHighlightsTests: XCTestCase {
    func testRanksFrequentMessagesAndExpiresByCountAndDisplayWindows() {
        var items = DanmakuHighlights()
        let settings = DanmakuHighlightsConfiguration(enabled: true, window: 30, displayTime: 10, minimumCount: 2)
        items.record("甲", now: 40, window: 30)
        items.record("甲", now: 58, window: 30)
        items.record("乙", now: 61, window: 30)
        items.record("乙", now: 63, window: 30)
        items.record("甲", now: 65, window: 30)
        items.record("只有一次", now: 66, window: 30)
        XCTAssertEqual(items.summaries(now: 68, settings: settings).map(\.text), ["甲", "乙"])
        XCTAssertEqual(items.summaries(now: 74, settings: settings).map(\.count), [2])
        XCTAssertTrue(items.summaries(now: 76, settings: settings).isEmpty)
    }
}
