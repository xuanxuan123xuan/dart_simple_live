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
    @State private var controlsVisible = true
    @State private var controlsActivity = 0
    @State private var isChoosingQuality = false
    @FocusState private var focusedControl: PlayerFocus?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = engine.player {
                HLSVideoView(player: player).ignoresSafeArea()
            } else if let view = engine.nativeView {
                NativeVideoView(view: view).id(ObjectIdentifier(view)).ignoresSafeArea()
            }
            if !controlsVisible && errorMessage == nil {
                Button(action: showControls) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .focused($focusedControl, equals: .video)
                .onMoveCommand { if $0 == .up { showControls() } }
                .accessibilityLabel("显示播放控制")
                .accessibilityIdentifier("player-video-controls")
            }
            if let errorMessage {
                ContentUnavailableView {
                    Label(errorMessage, systemImage: "play.slash")
                } actions: {
                    Button("重试") { retry += 1 }
                        .focused($focusedControl, equals: .retry)
                        .onMoveCommand(perform: controlsVisible ? nil : { if $0 == .up { showControls() } })
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
        .overlay(alignment: .top) {
            if controlsVisible {
                playerControls
                    .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .defaultFocus($focusedControl, preferredFocus)
        .onPlayPauseCommand { engine.togglePlayback() }
        .onChange(of: focusedControl) { _, _ in controlsActivity += 1 }
        .onChange(of: errorMessage) { _, message in
            if message != nil { focusedControl = .retry }
            else if focusedControl == .retry { focusedControl = .video }
        }
        .task(id: autoHideActivity) {
            guard let activity = autoHideActivity else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, autoHideActivity == activity else { return }
            withAnimation(.easeOut(duration: 0.2), completionCriteria: .removed) {
                controlsVisible = false
            } completion: {
                if !controlsVisible { focusedControl = preferredFocus }
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

    private var autoHideActivity: Int? {
        controlsVisible && !isChoosingQuality && scenePhase == .active ? controlsActivity : nil
    }

    private var firstControl: PlayerFocus { qualities.isEmpty ? .favorite : .quality }

    private var preferredFocus: PlayerFocus {
        if errorMessage != nil { return .retry }
        return controlsVisible ? firstControl : .video
    }

    private var playerControls: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(room.title).font(.headline).lineLimit(1)
                if let danmakuError { Text(danmakuError).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 24)
            if !qualities.isEmpty {
                Button(selectedQuality?.name ?? "清晰度") { isChoosingQuality = true }
                    .focused($focusedControl, equals: .quality)
                    .accessibilityLabel("清晰度")
                    .accessibilityValue(selectedQuality?.name ?? "")
                    .accessibilityIdentifier("player-quality")
                    .confirmationDialog("清晰度", isPresented: $isChoosingQuality, titleVisibility: .visible) {
                        ForEach(qualities) { quality in
                            Button(quality.name) { selectedQuality = quality }
                        }
                    }
            }
            let isFavorite = library.isFavorite(room)
            Button {
                library.toggleFavorite(room)
                controlsActivity += 1
            } label: {
                Label(isFavorite ? "取消收藏" : "收藏", systemImage: isFavorite ? "star.fill" : "star")
            }
            .focused($focusedControl, equals: .favorite)
            .accessibilityIdentifier("player-favorite")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .background {
            LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: [.top, .horizontal])
        }
        .environment(\.colorScheme, .dark)
        .focusSection()
    }

    private func showControls() {
        controlsActivity += 1
        withAnimation(.easeOut(duration: 0.2), completionCriteria: .removed) {
            controlsVisible = true
        } completion: {
            if controlsVisible { focusedControl = firstControl }
        }
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

private enum PlayerFocus: Hashable {
    case video, quality, favorite, retry
}

private struct HLSVideoView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.view.isUserInteractionEnabled = false
        controller.player = player
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
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
