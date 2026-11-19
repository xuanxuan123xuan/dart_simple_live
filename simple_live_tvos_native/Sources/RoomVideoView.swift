import AVFoundation
import SwiftUI

struct RoomVideoView: View {
    @AppStorage(PlaybackPreferences.aspect) private var aspect = PlaybackAspect.fit

    let engine: PlaybackEngine

    var body: some View {
        ZStack {
            Color.black
            if let ratio = aspect.ratio {
                GeometryReader { geometry in
                    let width = min(geometry.size.width, geometry.size.height * ratio)
                    video.frame(width: width, height: width / ratio)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            } else {
                video
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var video: some View {
        if let player = engine.player {
            HLSVideoView(player: player, gravity: aspect.videoGravity)
        } else if let view = engine.nativeView {
            NativeVideoView(view: view, mode: aspect.contentMode).id(ObjectIdentifier(view))
        }
    }
}

private extension PlaybackAspect {
    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fit: .resizeAspect
        case .fill: .resizeAspectFill
        case .stretch, .wide, .standard: .resize
        }
    }

    var contentMode: UIView.ContentMode {
        switch self {
        case .fit: .scaleAspectFit
        case .fill: .scaleAspectFill
        case .stretch, .wide, .standard: .scaleToFill
        }
    }
}

private struct HLSVideoView: UIViewRepresentable {
    let player: AVPlayer
    let gravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> Surface { Surface() }

    func updateUIView(_ uiView: Surface, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
        uiView.playerLayer.videoGravity = gravity
    }

    static func dismantleUIView(_ uiView: Surface, coordinator: Void) {
        uiView.playerLayer.player = nil
    }

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

private struct NativeVideoView: UIViewRepresentable {
    let view: UIView
    let mode: UIView.ContentMode

    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {
        if uiView.contentMode != mode { uiView.contentMode = mode }
    }
}
