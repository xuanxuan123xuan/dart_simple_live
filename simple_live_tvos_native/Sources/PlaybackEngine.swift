import AVFoundation
import Combine
import Foundation
import KSPlayer
import SimpleLiveTVOSCore
import UIKit

@MainActor
final class PlaybackEngine: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var nativeView: UIView?
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentLine: Int?

    private static let configureLogging: Void = {
        KSOptions.logger = PrivateMediaLogger()
        KSOptions.logLevel = .panic
    }()
    private var failover = PlaybackFailoverController()
    private var runID = UUID()
    private var nativePlayer: KSPlayerLayer?

    func run(resources: [PlaybackResource], preferredLine: Int? = nil) async throws {
        try Task.checkCancellation()
        stop()
        let id = runID
        var attempt = try failover.begin(resources: resources, preferredLine: preferredLine)
        defer {
            if runID == id { stop() }
        }
        while true {
            try Task.checkCancellation()
            guard runID == id else { throw CancellationError() }
            currentLine = attempt.resource.lineIndex
            state = .preparing
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
        let player = AVPlayer(playerItem: item)
        self.player = player
        player.play()
        try await monitor(attempt, id: id) {
            if item.status == .failed || player.status == .failed { throw LiveProviderError.noPlayback }
            return (player.currentTime().seconds, player.timeControlStatus == .paused)
        }
    }

    private func playNative(_ attempt: PlaybackAttempt, id: UUID) async throws {
        _ = Self.configureLogging
        let options = KSOptions()
        options.registerRemoteControll = false
        options.appendHeader(attempt.resource.headers)
        let previousPlayerType = KSOptions.firstPlayerType
        KSOptions.firstPlayerType = KSMEPlayer.self
        let layer = KSPlayerLayer(url: attempt.resource.url, options: options)
        KSOptions.firstPlayerType = previousPlayerType
        nativePlayer = layer
        nativeView = layer.player.view
        try await monitor(attempt, id: id) {
            if layer.state == .error || layer.state == .playedToTheEnd { throw LiveProviderError.noPlayback }
            return (layer.player.currentPlaybackTime, layer.state == .paused)
        }
    }

    func togglePlayback() {
        if let player {
            if player.timeControlStatus == .paused {
                player.play()
            } else {
                player.pause()
            }
            return
        }
        guard let nativePlayer else { return }
        if nativePlayer.state == .paused {
            nativePlayer.play()
        } else if state == .playing || state == .buffering {
            nativePlayer.pause()
        }
    }

    private func monitor(_ attempt: PlaybackAttempt, id: UUID, sample: () throws -> (position: Double, paused: Bool)) async throws {
        let clock = ContinuousClock()
        var lastProgress = clock.now
        var lastTime = 0.0
        var hasStarted = false
        while true {
            try await Task.sleep(for: .milliseconds(350))
            guard id == runID else { throw CancellationError() }
            let (position, paused) = try sample()
            if position.isFinite && abs(position - lastTime) > 0.03 {
                if !hasStarted {
                    try failover.markPlaying(lineIndex: attempt.resource.lineIndex, generation: attempt.generation)
                    hasStarted = true
                }
                lastProgress = clock.now
                lastTime = position
                state = .playing
            } else if hasStarted && paused {
                lastProgress = clock.now
                state = .paused
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
