@testable import SimpleLiveTVOS
import XCTest

final class AutoQualityRecoveryTests: XCTestCase {
    func testOnlyDistinctStallsAfterWarmupTriggerWithinWindow() {
        let start = ContinuousClock.now
        func time(_ s: Int) -> ContinuousClock.Instant { start.advanced(by: .seconds(s)) }
        var recovery = AutoQualityRecovery()
        XCTAssertFalse(recovery.observe(.preparing, now: time(0)))
        XCTAssertFalse(recovery.observe(.playing, now: time(1)))
        XCTAssertFalse(recovery.observe(.buffering, now: time(3)))
        XCTAssertFalse(recovery.observe(.buffering, now: time(10)))
        XCTAssertFalse(recovery.observe(.playing, now: time(11)))
        XCTAssertFalse(recovery.observe(.buffering, now: time(12)))
        XCTAssertFalse(recovery.observe(.playing, now: time(13)))
        XCTAssertTrue(recovery.observe(.buffering, now: time(14)))
        recovery.markDowngraded(at: time(14))
        XCTAssertFalse(recovery.observe(.paused, now: time(15)))
        XCTAssertFalse(recovery.observe(.playing, now: time(20)))
        XCTAssertFalse(recovery.observe(.buffering, now: time(30)))
        XCTAssertFalse(recovery.observe(.playing, now: time(31)))
        XCTAssertFalse(recovery.observe(.buffering, now: time(34))) // Cooldown
        XCTAssertFalse(recovery.observe(.playing, now: time(35)))
        XCTAssertFalse(recovery.observe(.buffering, now: time(70))) // Old stall out of window
    }

    func testChoosesOnlyClosestKnownLowerTierEvenIfProviderOrderIsMixed() {
        let unknown = LiveQuality(id: "?", name: "未标明")
        let original = LiveQuality(id: "0", name: "原画", recoveryRank: Int.max)
        let high = LiveQuality(id: "4000", name: "高清", recoveryRank: 4_000)
        let low = LiveQuality(id: "800", name: "流畅", recoveryRank: 800)
        let mixed = [low, unknown, original, high]
        XCTAssertEqual(AutoQualityRecovery.nextLower(from: original, choices: mixed), high)
        XCTAssertEqual(AutoQualityRecovery.nextLower(from: high, choices: mixed), low)
        XCTAssertNil(AutoQualityRecovery.nextLower(from: low, choices: mixed))
        XCTAssertNil(AutoQualityRecovery.nextLower(from: unknown, choices: mixed))
    }
}
