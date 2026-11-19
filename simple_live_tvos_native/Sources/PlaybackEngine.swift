import AVFoundation
import Foundation
import KSPlayer
import Observation
import SimpleLiveTVOSCore
import UIKit

@MainActor
@Observable
final class PlaybackEngine {
    private(set) var player: AVPlayer?
    private(set) var nativeView: UIView?
    private(set) var state: PlaybackState = .idle
    private(set) var currentLine: Int?
    private(set) var pausedByUser = false
    private(set) var volume: Int
    private(set) var isMuted = false
    private(set) var isAudioSuppressed = false

    var isEffectivelyMuted: Bool { isMuted || isAudioSuppressed }

    private static let configureLogging: Void = {
        KSOptions.logger = PrivateMediaLogger()
        KSOptions.logLevel = .panic
    }()
    private var failover = PlaybackFailoverController()
    private var runID = UUID()
    private var nativePlayer: KSPlayerLayer?
    private let defaults: UserDefaults

    init(initialVolume: Int? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        volume = min(100, max(0, initialVolume ?? PlaybackTuning(defaults: defaults).initialVolume))
    }

    func run(resources: [PlaybackResource], preferredLine: Int? = nil) async throws {
        try Task.checkCancellation()
        stop()
        let id = runID
        defer {
            if runID == id { stop() }
        }
        var attempt = try failover.begin(resources: resources, preferredLine: preferredLine)
        while true {
            try Task.checkCancellation()
            guard runID == id else { throw CancellationError() }
            currentLine = attempt.resource.lineIndex
            state = pausedByUser ? .paused : .preparing
            do {
                try await play(attempt, id: id)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard runID == id, !Task.isCancelled else { throw CancellationError() }
                releaseBackend()
                do {
                    attempt = try failover.failCurrent(generation: attempt.generation)
                } catch {
                    throw LiveProviderError.noPlayback
                }
            }
        }
    }

    func stop() {
        runID = UUID()
        releaseBackend()
        failover.stop()
        currentLine = nil
        state = .stopped
    }

    private func releaseBackend() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        nativePlayer?.pause()
        nativePlayer?.stop()
        nativePlayer = nil
        nativeView = nil
    }

    private func play(_ attempt: PlaybackAttempt, id: UUID) async throws {
        let resource = attempt.resource
        switch resource.protocolKind {
        case .hls where resource.url.scheme == "https":
            try await playHLS(attempt, id: id)
        case .hls, .flv, .rtmp:
            try await playNative(attempt, id: id)
        case .unknown: throw LiveProviderError.unsupported
        }
    }

    private func playHLS(_ attempt: PlaybackAttempt, id: UUID) async throws {
        let resource = attempt.resource
        let asset = AVURLAsset(url: resource.url, options: ["AVURLAssetHTTPHeaderFieldsKey": resource.headers])
        let item = AVPlayerItem(asset: asset)
        let buffering = PlaybackTuning(defaults: defaults).buffering
        if let buffer = buffering.seconds { item.preferredForwardBufferDuration = buffer }
        let player = AVPlayer(playerItem: item)
        if buffering == .lowLatency { player.automaticallyWaitsToMinimizeStalling = false }
        self.player = player
        applyAudio()
        if !pausedByUser { player.play() }
        try await monitor(attempt, id: id) {
            if item.status == .failed || player.status == .failed { throw LiveProviderError.noPlayback }
            return player.currentTime().seconds
        }
    }

    private func playNative(_ attempt: PlaybackAttempt, id: UUID) async throws {
        _ = Self.configureLogging
        let options = KSOptions()
        let tuning = PlaybackTuning(defaults: defaults)
        options.hardwareDecode = tuning.hardwareDecode
        if let buffer = tuning.buffering.seconds {
            options.preferredForwardBufferDuration = buffer
            options.maxBufferDuration = max(buffer * 3, 10)
        }
        options.registerRemoteControll = false
        options.appendHeader(attempt.resource.headers)
        let previousPlayerType = KSOptions.firstPlayerType
        KSOptions.firstPlayerType = KSMEPlayer.self
        let layer = KSPlayerLayer(url: attempt.resource.url, isAutoPlay: false, options: options)
        KSOptions.firstPlayerType = previousPlayerType
        nativePlayer = layer
        nativeView = layer.player.view
        applyAudio()
        if !pausedByUser { layer.play() }
        try await monitor(attempt, id: id) {
            if layer.state == .error || layer.state == .playedToTheEnd { throw LiveProviderError.noPlayback }
            return layer.player.currentPlaybackTime
        }
    }

    func togglePlayback() { setPaused(!pausedByUser) }

    func setPaused(_ paused: Bool) {
        guard pausedByUser != paused else { return }
        pausedByUser = paused
        if paused {
            player?.pause()
            nativePlayer?.pause()
            state = .paused
        } else {
            player?.play()
            nativePlayer?.play()
            state = .preparing
        }
    }

    func setVolume(_ value: Int) {
        volume = min(100, max(0, value))
        applyAudio()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        applyAudio()
    }

    func setAudioSuppressed(_ suppressed: Bool) {
        guard isAudioSuppressed != suppressed else { return }
        isAudioSuppressed = suppressed
        applyAudio()
    }

    private func applyAudio() {
        let gain = Float(volume) / 100
        player?.volume = gain
        player?.isMuted = isEffectivelyMuted
        nativePlayer?.player.playbackVolume = gain
        nativePlayer?.player.isMuted = isEffectivelyMuted
    }

    private func monitor(_ attempt: PlaybackAttempt, id: UUID, sample: () throws -> Double) async throws {
        let clock = ContinuousClock()
        var lastProgress = clock.now
        var lastTime = 0.0
        var hasStarted = false
        while true {
            try await Task.sleep(for: .milliseconds(350))
            guard id == runID else { throw CancellationError() }
            if pausedByUser {
                lastProgress = clock.now
                state = .paused
                continue
            }
            let position = try sample()
            if position.isFinite && abs(position - lastTime) > 0.03 {
                if !hasStarted {
                    try failover.markPlaying(lineIndex: attempt.resource.lineIndex, generation: attempt.generation)
                    hasStarted = true
                }
                lastProgress = clock.now
                lastTime = position
                state = .playing

            } else {
                state = hasStarted ? .buffering : .preparing
                if lastProgress.duration(to: clock.now) > .seconds(15) { throw LiveProviderError.noPlayback }
            }
        }
    }
}

private struct PrivateMediaLogger: LogHandler {
    // FFmpeg diagnostic messages can include temporary CDN credentials.
    func log(level: KSPlayer.LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt) {}
}
