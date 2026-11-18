@testable import SimpleLiveTVOS
import Foundation
import XCTest

final class PlaybackRecoveryTests: XCTestCase {
    @MainActor
    func testMissingStreamOnlyMeansOfflineWithExplicitPresence() async {
        let offline = await PlaybackIssue.classify(LiveProviderError.noPlayback) { false }
        let live = await PlaybackIssue.classify(LiveProviderError.noPlayback) { true }
        let unknown = await PlaybackIssue.classify(LiveProviderError.noPlayback) { nil }
        let networkFailure = await PlaybackIssue.classify(LiveProviderError.noPlayback) { throw URLError(.timedOut) }
        XCTAssertEqual(offline, .offline)
        for issue in [live, unknown, networkFailure] {
            XCTAssertEqual(issue, .failed(LiveProviderError.noPlayback.localizedDescription))
        }
        let explicitOffline = await PlaybackIssue.classify(LiveProviderError.offline) {
            XCTFail("Explicit provider state should not trigger a second request")
            return nil
        }
        XCTAssertEqual(explicitOffline, .offline)
    }

    func testCountdownRoundsUpAndStopsAtZero() {
        let now = Date(timeIntervalSince1970: 5_000)
        XCTAssertEqual(SleepTimerDisplay.remaining(until: now.addingTimeInterval(60.2), now: now), "1:01")
        XCTAssertEqual(SleepTimerDisplay.remaining(until: now.addingTimeInterval(0.01), now: now), "0:01")
        XCTAssertEqual(SleepTimerDisplay.remaining(until: now.addingTimeInterval(-90), now: now), "0:00")
    }
}
