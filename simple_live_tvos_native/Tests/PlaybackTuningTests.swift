import AVFoundation
import SimpleLiveTVOSCore
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
        let medium = LiveQuality(id: "medium", name: "清晰", recoveryRank: 1_500)
        let low = LiveQuality(id: "low", name: "流畅", recoveryRank: 800)
        XCTAssertEqual(tuning.defaultQuality.select(from: [unknown, original, low]), low)
        XCTAssertEqual(tuning.defaultQuality.select(from: [unknown]), unknown)
        XCTAssertEqual(PlaybackQualityPreference.middle.select(from: [unknown, original, medium, low]), medium)
    }

    @MainActor
    func testPlaybackSettingsReachAVPlayerAndAreRereadOnNextConnection() async throws {
        let name = "playback-av-buffer-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(65, forKey: PlaybackPreferences.initialVolume)
        defaults.set(PlaybackBuffering.stable.rawValue, forKey: PlaybackPreferences.buffering)
        let engine = PlaybackEngine(defaults: defaults)
        engine.setPaused(true)
        let url = try XCTUnwrap(URL(string: "https://127.0.0.1:1/fixture.m3u8"))
        let resource = PlaybackResource(url: url, protocolKind: .hls)
        let stable = Task { try await engine.run(resources: [resource]) }
        defer { stable.cancel(); engine.stop() }
        let stablePlayer = try await preparedPlayer(engine)
        XCTAssertEqual(stablePlayer.currentItem?.preferredForwardBufferDuration, 8)
        XCTAssertTrue(stablePlayer.automaticallyWaitsToMinimizeStalling)
        XCTAssertEqual(stablePlayer.volume, 0.65)
        engine.stop()
        _ = await stable.result

        defaults.set(PlaybackBuffering.lowLatency.rawValue, forKey: PlaybackPreferences.buffering)
        let lowLatency = Task { try await engine.run(resources: [resource]) }
        defer { lowLatency.cancel(); engine.stop() }
        let lowLatencyPlayer = try await preparedPlayer(engine)
        XCTAssertEqual(lowLatencyPlayer.currentItem?.preferredForwardBufferDuration, 1.5)
        XCTAssertFalse(lowLatencyPlayer.automaticallyWaitsToMinimizeStalling)
        XCTAssertEqual(lowLatencyPlayer.volume, 0.65)
    }

    @MainActor
    private func preparedPlayer(_ engine: PlaybackEngine) async throws -> AVPlayer {
        for _ in 0..<40 {
            if let player = engine.player { return player }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try XCTUnwrap(engine.player)
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
