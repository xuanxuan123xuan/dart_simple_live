@testable import SimpleLiveTVOS
import XCTest

final class PlaybackTuningTests: XCTestCase {
    func testNewSessionsReadNativePlaybackSettingsAndSelectOnlyRankedQualities() throws {
        let name = "playback-tuning-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertNil(PlaybackTuning(defaults: defaults).buffering.seconds)
        defaults.set(false, forKey: PlaybackPreferences.hardwareDecode)
        defaults.set(PlaybackBuffering.stable.rawValue, forKey: PlaybackPreferences.buffering)
        defaults.set(PlaybackQualityPreference.lowest.rawValue, forKey: PlaybackPreferences.defaultQuality)
        defaults.set(70, forKey: PlaybackPreferences.initialVolume)
        let tuning = PlaybackTuning(defaults: defaults)
        XCTAssertFalse(tuning.hardwareDecode)
        XCTAssertEqual(tuning.initialVolume, 70)
        XCTAssertEqual(tuning.buffering.seconds, 8)
        let unknown = LiveQuality(id: "default", name: "默认")
        let original = LiveQuality(id: "orig", name: "原画", recoveryRank: 4_000)
        let low = LiveQuality(id: "low", name: "流畅", recoveryRank: 800)
        XCTAssertEqual(tuning.defaultQuality.select(from: [unknown, original, low]), low)
        XCTAssertEqual(tuning.defaultQuality.select(from: [unknown]), unknown)
    }

    @MainActor
    func testStoppingAndRestartingPlayerKeepsExplicitAudioAndPauseIntent() {
        let session = PlaybackEngine(initialVolume: 70)
        let other = PlaybackEngine(initialVolume: 100)
        session.setPaused(true)
        session.setMuted(true)
        session.setVolume(60)
        session.stop()
        XCTAssertTrue(session.pausedByUser)
        XCTAssertTrue(session.isMuted)
        XCTAssertEqual(session.volume, 60)
        XCTAssertFalse(other.pausedByUser)
        XCTAssertFalse(other.isMuted)
        XCTAssertEqual(other.volume, 100)
    }
}
