import AVKit
import Combine
import SimpleLiveTVOSCore
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("simple_live_tvos.danmaku") private var danmakuEnabled = true

    let room: RoomDescriptor

    @StateObject private var engine = PlaybackEngine()
    @State private var errorMessage: String?
    @State private var danmakuError: String?
    @State private var qualities: [LiveQuality] = []
    @State private var selectedQuality: LiveQuality?
    @State private var danmakuEvents = PassthroughSubject<DanmakuEvent, Never>()
    @State private var retry = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = engine.player {
                VideoPlayer(player: player).ignoresSafeArea()
            } else if let view = engine.nativeView {
                NativeVideoView(view: view).id(ObjectIdentifier(view)).ignoresSafeArea()
                    .onPlayPauseCommand { engine.toggleNativePlayback() }
            }
            if let errorMessage {
                ContentUnavailableView {
                    Label(errorMessage, systemImage: "play.slash")
                } actions: {
                    Button("重试") { retry += 1 }
                }
            } else if engine.state != .playing && engine.state != .paused {
                ProgressView()
            }
            if danmakuEnabled, scenePhase == .active, errorMessage == nil {
                DanmakuOverlay(events: danmakuEvents)
                    .ignoresSafeArea(.container, edges: .horizontal)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .navigationTitle(room.title)
        .toolbar {
            if !qualities.isEmpty {
                ToolbarItem {
                    Menu(selectedQuality?.name ?? "清晰度") {
                        ForEach(qualities) { quality in
                            Button(quality.name) { selectedQuality = quality }
                        }
                    }
                }
            }
            ToolbarItem {
                Button { library.toggleFavorite(room) } label: {
                    Label(library.isFavorite(room) ? "取消收藏" : "收藏", systemImage: library.isFavorite(room) ? "star.fill" : "star")
                }
            }
            if let danmakuError {
                ToolbarItem { Text(danmakuError).font(.caption) }
            }
        }
        .task(id: PlaybackRequest(quality: selectedQuality, retry: retry, active: scenePhase == .active)) {
            guard scenePhase == .active else { engine.stop(); return }
            await startPlayback()
        }
        .task(id: danmakuEnabled && scenePhase == .active) {
            danmakuError = nil
            guard danmakuEnabled, scenePhase == .active else { return }
            do {
                for try await event in try core.danmaku(for: room) {
                    try Task.checkCancellation()
                    if engine.state == .playing { danmakuEvents.send(event) }
                }
            } catch {
                if !Task.isCancelled { danmakuError = "弹幕暂不可用" }
            }
        }
        .onDisappear { engine.stop() }
    }

    private func startPlayback() async {
        errorMessage = nil
        do {
            let service = try core.service(room.provider)
            guard let selectedQuality else {
                let values = try await service.qualities(roomId: room.roomId)
                try Task.checkCancellation()
                qualities = values
                guard let first = values.first else { throw LiveProviderError.noPlayback }
                self.selectedQuality = first
                return
            }
            let resources = try await service.playback(roomId: room.roomId, quality: selectedQuality)
            try Task.checkCancellation()
            let history = Task { @MainActor in
                while !Task.isCancelled {
                    if engine.state == .playing {
                        library.visit(room)
                        return
                    }
                    try await Task.sleep(for: .milliseconds(300))
                }
            }
            defer { history.cancel() }
            do {
                try await engine.run(resources: resources)
            } catch LiveProviderError.noPlayback {
                try Task.checkCancellation()
                let fresh = try await service.playback(roomId: room.roomId, quality: selectedQuality)
                try Task.checkCancellation()
                if fresh == resources { throw LiveProviderError.noPlayback }
                try await engine.run(resources: fresh)
            }
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }
}

private struct NativeVideoView: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct PlaybackRequest: Hashable {
    let quality: LiveQuality?
    let retry: Int
    let active: Bool
}
