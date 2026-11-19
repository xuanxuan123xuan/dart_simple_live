import AVKit
import SwiftUI

struct RoomVideoView: View {
    let engine: PlaybackEngine

    var body: some View {
        ZStack {
            Color.black
            if let player = engine.player {
                HLSVideoView(player: player)
            } else if let view = engine.nativeView {
                NativeVideoView(view: view).id(ObjectIdentifier(view))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HLSVideoView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.view.isUserInteractionEnabled = false
        controller.player = player
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Void) {
        controller.player = nil
    }
}

private struct NativeVideoView: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
