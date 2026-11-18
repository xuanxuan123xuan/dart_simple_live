import AVFoundation
import Foundation
import SwiftUI
import UIKit
#if canImport(KSPlayer)
import KSPlayer
#endif
#if canImport(KSPlayerUI)
import KSPlayerUI
#endif

enum StreamProtocol: String {
    case hls
    case flv
    case rtmp
    case unknown
}

struct PlaybackSession {
    let player: AVPlayer?
    #if canImport(KSPlayerUI)
    let nativeView: IOSVideoPlayerView?
    #endif
    let protocolKind: StreamProtocol
}

protocol LivePlaybackEngine {
    func prepare(url: URL, headers: [String: String], protocolKind: StreamProtocol) async throws -> PlaybackSession
    func play()
    func pause()
    func stop()
}

/// Native playback boundary used by the SwiftUI player.
///
@MainActor
final class KSPlayerPlaybackEngine: LivePlaybackEngine, ObservableObject {
    private(set) var session: PlaybackSession?

    func prepare(url: URL, headers: [String: String], protocolKind: StreamProtocol) async throws -> PlaybackSession {
        switch protocolKind {
        case .hls:
            var assetOptions: [String: Any] = [:]
            if !headers.isEmpty {
                assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = headers
            }
            let asset = AVURLAsset(url: url, options: assetOptions)
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            let value = PlaybackSession(
                player: player,
                #if canImport(KSPlayerUI)
                nativeView: nil,
                #endif
                protocolKind: .hls
            )
            session = value
            return value
        case .flv, .rtmp:
            #if canImport(KSPlayer), canImport(KSPlayerUI)
            KSOptions.secondPlayerType = KSMEPlayer.self
            let playerView = IOSVideoPlayerView()
            let options = KSOptions()
            if !headers.isEmpty {
                options.appendHeader(headers)
            }
            let definition = KSPlayerResourceDefinition(
                url: url,
                definition: "直播",
                options: options
            )
            let resource = KSPlayerResource(
                name: url.lastPathComponent,
                definitions: [definition]
            )
            playerView.set(resource: resource)
            let value = PlaybackSession(
                player: nil,
                nativeView: playerView,
                protocolKind: protocolKind
            )
            session = value
            return value
            #else
            throw PlaybackError.backendUnavailable(protocolKind)
            #endif
        case .unknown:
            throw PlaybackError.unsupportedURL
        }
    }

    func play() { session?.player?.play() }
    func pause() { session?.player?.pause() }
    func stop() {
        session?.player?.pause()
        session = nil
    }
}

#if canImport(KSPlayerUI)
struct KSPlayerViewRepresentable: UIViewRepresentable {
    let playerView: IOSVideoPlayerView

    func makeUIView(context: Context) -> IOSVideoPlayerView { playerView }
    func updateUIView(_ uiView: IOSVideoPlayerView, context: Context) {}
}
#endif

enum PlaybackError: LocalizedError {
    case backendUnavailable(StreamProtocol)
    case unsupportedURL

    var errorDescription: String? {
        switch self {
        case let .backendUnavailable(protocolKind):
            "KSPlayer 当前不可用，无法播放 \(protocolKind.rawValue.uppercased())"
        case .unsupportedURL:
            "播放地址协议无法识别"
        }
    }
}
