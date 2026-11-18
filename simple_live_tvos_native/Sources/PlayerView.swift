import AVKit
import Combine
import SimpleLiveTVOSCore
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @AppStorage("simple_live_tvos.danmaku") private var danmakuEnabled = true
    @AppStorage(PlaybackPreferences.autoQuality) private var autoQuality = true

    let room: RoomDescriptor
    let queue: ChannelQueue
    @Binding var sleepDeadline: Date?
    let openChannel: (RoomDescriptor) -> Void

    @StateObject private var engine = PlaybackEngine()
    @State private var playbackIssue: PlaybackIssue?
    @State private var sleepExpired = false
    @State private var qualityRecovery = AutoQualityRecovery()
    @State private var qualityRecoveryMessage: String?
    @State private var danmakuError: String?
    @State private var qualities: [LiveQuality] = []
    @State private var selectedQuality: LiveQuality?
    @State private var playbackResources: [PlaybackResource] = []
    @State private var preferredLine: Int?
    @State private var danmakuEvents = PassthroughSubject<DanmakuEvent, Never>()
    @State private var retry = 0
    @State private var controlsVisible = true
    @State private var controlsActivity = 0
    @State private var selectionMenu: PlayerMenu?
    @State private var activeSheet: PlayerSheet?
    @FocusState private var focusedControl: PlayerFocus?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = engine.player {
                HLSVideoView(player: player).ignoresSafeArea()
            } else if let view = engine.nativeView {
                NativeVideoView(view: view).id(ObjectIdentifier(view)).ignoresSafeArea()
            }
            if !controlsVisible && playbackIssue == nil && !sleepExpired {
                Button(action: showControls) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .focused($focusedControl, equals: .video)
                .onMoveCommand { direction in
                    switch direction {
                    case .up: showControls()
                    case .left: switchChannel(-1)
                    case .right: switchChannel(1)
                    default: break
                    }
                }
                .accessibilityLabel("显示播放控制")
                .accessibilityIdentifier("player-video-controls")
            }
            if sleepExpired {
                ContentUnavailableView {
                    Label("定时关闭已停止播放", systemImage: "moon.zzz")
                } actions: {
                    Button("返回") { dismiss() }
                        .focused($focusedControl, equals: .sleepExit)
                }
            } else if let playbackIssue {
                ContentUnavailableView {
                    Label(playbackIssue.title, systemImage: playbackIssue == .offline ? "dot.radiowaves.left.and.right" : "play.slash")
                } description: {
                    if case let .failed(message) = playbackIssue { Text(message) }
                } actions: {
                    Button("重试", action: refreshPlayback)
                        .focused($focusedControl, equals: .retry)
                        .onMoveCommand(perform: controlsVisible ? nil : { if $0 == .up { showControls() } })
                }
            } else if engine.state != .playing && engine.state != .paused {
                ProgressView()
            }
            if danmakuEnabled, scenePhase == .active, playbackIssue == nil, !sleepExpired {
                DanmakuOverlay(events: danmakuEvents)
                    .ignoresSafeArea(.container, edges: .horizontal)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .top) {
            if controlsVisible && !sleepExpired {
                playerControls
                    .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .defaultFocus($focusedControl, preferredFocus)
        .onPlayPauseCommand(perform: togglePlayback)
        .sheet(item: $activeSheet, onDismiss: { controlsActivity += 1 }) { sheet in
            switch sheet {
            case .channels:
                PlayerChannelList(current: room, queue: queue, select: openChannel)
            case .favorites:
                PlayerChannelList(current: room, rooms: library.favorites, title: "收藏列表", select: openChannel)
            case .settings:
                PlayerRoomSettingsView(engine: engine, danmakuEnabled: $danmakuEnabled,
                                       sleepDeadline: $sleepDeadline)
            }
        }
        .onChange(of: engine.state) { _, state in observeQualityRecovery(state) }
        .onChange(of: autoQuality) { _, _ in qualityRecovery = AutoQualityRecovery() }
        .onChange(of: focusedControl) { _, _ in controlsActivity += 1 }
        .onChange(of: playbackIssue) { _, issue in
            if sleepExpired { focusedControl = .sleepExit }
            else if issue != nil { focusedControl = .retry }
            else if focusedControl == .retry { focusedControl = preferredFocus }
        }
        .task(id: sleepDeadline) {
            guard let deadline = sleepDeadline else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                try Task.checkCancellation()
                if sleepDeadline == deadline { stopForSleepTimer() }
            } catch { return }
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
        .task(id: PlaybackRequest(quality: selectedQuality, retry: retry, active: scenePhase == .active && !sleepExpired)) {
            if let deadline = sleepDeadline, deadline <= .now {
                stopForSleepTimer()
                return
            }
            guard scenePhase == .active, !sleepExpired else {
                engine.stop()
                playbackResources = []
                return
            }
            await startPlayback()
        }
        .task(id: danmakuEnabled && scenePhase == .active && !sleepExpired) {
            danmakuError = nil
            guard danmakuEnabled, scenePhase == .active, !sleepExpired else { return }
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
        controlsVisible && !sleepExpired && selectionMenu == nil && activeSheet == nil && scenePhase == .active ? controlsActivity : nil
    }

    private var firstControl: PlayerFocus { .playPause }

    private var availableLines: [Int] {
        Set(playbackResources.map(\.lineIndex)).sorted()
    }

    private var preferredFocus: PlayerFocus {
        if sleepExpired { return .sleepExit }
        if playbackIssue != nil { return .retry }
        return controlsVisible ? firstControl : .video
    }

    private var playerControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(room.title).font(.headline).lineLimit(1)
                Text(playbackStatus).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("player-status")
                if let sleepDeadline {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("定时关闭 \(SleepTimerDisplay.remaining(until: sleepDeadline, now: context.date))")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if let qualityRecoveryMessage { Text(qualityRecoveryMessage).font(.caption).foregroundStyle(.secondary) }
                if let danmakuError { Text(danmakuError).font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            playbackActions
            roomActions
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .background {
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: [.top, .horizontal])
        }
        .environment(\.colorScheme, .dark)
        .focusSection()
    }

    private var playbackActions: some View {
        HStack(spacing: 16) {
            Button(engine.pausedByUser ? "继续" : "暂停", action: togglePlayback)
                .disabled(playbackIssue != nil)
                .focused($focusedControl, equals: .playPause)
                .accessibilityIdentifier("player-play-pause")
            Button("刷新", action: refreshPlayback)
                .focused($focusedControl, equals: .refresh)
                .accessibilityIdentifier("player-refresh")
            if queue.rooms.count > 1 {
                Button("换台") { activeSheet = .channels }
                    .focused($focusedControl, equals: .channels)
                    .accessibilityIdentifier("player-channels")
            }
            if !qualities.isEmpty {
                Button(selectedQuality?.name ?? "清晰度") { selectionMenu = .quality }
                    .focused($focusedControl, equals: .quality)
                    .accessibilityLabel("清晰度")
                    .accessibilityValue(selectedQuality?.name ?? "")
                    .accessibilityIdentifier("player-quality")
                    .confirmationDialog("清晰度", isPresented: menuIsPresented(.quality), titleVisibility: .visible) {
                        ForEach(qualities) { quality in
                            Button(quality.name) { selectQuality(quality) }
                        }
                    }
            }
            Button(engine.currentLine.map(lineTitle) ?? "线路") { selectionMenu = .line }
                .disabled(availableLines.isEmpty)
                .focused($focusedControl, equals: .line)
                .accessibilityLabel("线路")
                .accessibilityValue(engine.currentLine.map(lineTitle) ?? "")
                .accessibilityIdentifier("player-line")
                .confirmationDialog("选择线路", isPresented: menuIsPresented(.line), titleVisibility: .visible) {
                    ForEach(availableLines, id: \.self) { line in
                        Button(line == engine.currentLine ? "\(lineTitle(line))（当前）" : lineTitle(line)) {
                            guard line != engine.currentLine else { return }
                            preferredLine = line
                            retry += 1
                        }
                    }
                }
        }
    }

    private var roomActions: some View {
        HStack(spacing: 16) {
            Button {
                danmakuEnabled.toggle()
                controlsActivity += 1
            } label: {
                Label(danmakuEnabled ? "弹幕开" : "弹幕关", systemImage: danmakuEnabled ? "text.bubble.fill" : "text.bubble")
            }
            .focused($focusedControl, equals: .danmaku)
            .accessibilityLabel("弹幕")
            .accessibilityValue(danmakuEnabled ? "开" : "关")
            .accessibilityIdentifier("player-danmaku")
            let isFavorite = library.isFavorite(room)
            Button {
                library.toggleFavorite(room)
                controlsActivity += 1
            } label: {
                Label(isFavorite ? "取消收藏" : "收藏", systemImage: isFavorite ? "star.fill" : "star")
            }
            .focused($focusedControl, equals: .favorite)
            .accessibilityIdentifier("player-favorite")
            Button("收藏列表") { activeSheet = .favorites }
                .focused($focusedControl, equals: .favoriteList)
                .accessibilityIdentifier("player-favorite-list")
            Button("房内设置") { activeSheet = .settings }
                .focused($focusedControl, equals: .settings)
                .accessibilityIdentifier("player-room-settings")
        }
    }

    private var playbackStatus: String {
        if let playbackIssue { return playbackIssue.title }
        switch engine.state {
        case .idle, .preparing: return "连接中"
        case .buffering: return "缓冲中"
        case .playing: return "正在播放"
        case .paused: return "已暂停"
        case .failed: return "播放失败"
        case .stopped: return "已停止"
        }
    }

    private func refreshPlayback() {
        qualityRecoveryMessage = nil
        playbackResources = []
        controlsActivity += 1
        retry += 1
    }

    private func togglePlayback() {
        guard playbackIssue == nil, !sleepExpired else { return }
        engine.togglePlayback()
        controlsActivity += 1
    }

    private func stopForSleepTimer() {
        guard !sleepExpired else { return }
        sleepExpired = true
        activeSheet = nil
        selectionMenu = nil
        focusedControl = .sleepExit
        engine.stop()
    }

    private func switchChannel(_ offset: Int) {
        if let next = queue.adjacent(to: room, offset: offset) { openChannel(next) }
    }

    private func showControls() {
        controlsActivity += 1
        withAnimation(.easeOut(duration: 0.2), completionCriteria: .removed) {
            controlsVisible = true
        } completion: {
            if controlsVisible { focusedControl = firstControl }
        }
    }

    private func menuIsPresented(_ menu: PlayerMenu) -> Binding<Bool> {
        Binding(get: { selectionMenu == menu }, set: { presented in
            if !presented, selectionMenu == menu { selectionMenu = nil }
        })
    }

    private func lineTitle(_ line: Int) -> String { "线路 \(line + 1)" }

    private func observeQualityRecovery(_ state: PlaybackState) {
        guard autoQuality, scenePhase == .active, !sleepExpired else { return }
        let now = ContinuousClock.now
        guard qualityRecovery.observe(state, now: now), let selectedQuality,
              let lower = AutoQualityRecovery.nextLower(from: selectedQuality, choices: qualities) else { return }
        qualityRecovery.markDowngraded(at: now)
        selectQuality(lower, automatically: true)
    }

    private func selectQuality(_ quality: LiveQuality, automatically: Bool = false) {
        guard selectedQuality != quality else { return }
        qualityRecoveryMessage = automatically ? "网络波动，已切换至\(quality.name)" : nil
        playbackResources = []
        preferredLine = nil
        selectedQuality = quality
    }

    private func startPlayback() async {
        playbackIssue = nil
        let requestedLine = preferredLine
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
            var resources = playbackResources
            if resources.isEmpty {
                resources = try await service.playback(roomId: room.roomId, quality: selectedQuality)
            }
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
                try await play(resources, preferredLine: requestedLine)
            } catch LiveProviderError.noPlayback {
                try Task.checkCancellation()
                let fresh = try await service.playback(roomId: room.roomId, quality: selectedQuality)
                try Task.checkCancellation()
                if fresh == resources { throw LiveProviderError.noPlayback }
                try await play(fresh, preferredLine: requestedLine)
            }
        } catch {
            guard !Task.isCancelled, !sleepExpired else { return }
            let issue = await PlaybackIssue.classify(error) {
                try await core.service(room.provider).resolveRoom(room.roomId).isLive
            }
            if !Task.isCancelled, !sleepExpired { playbackIssue = issue }
        }
    }

    private func play(_ resources: [PlaybackResource], preferredLine: Int?) async throws {
        try Task.checkCancellation()
        playbackResources = resources
        try await engine.run(resources: resources, preferredLine: preferredLine)
    }
}

private enum PlayerFocus: Hashable {
    case video, playPause, refresh, channels, quality, line, danmaku, favorite, favoriteList, settings, retry, sleepExit
}

private enum PlayerSheet: String, Identifiable {
    case channels, favorites, settings
    var id: Self { self }
}

private enum PlayerMenu {
    case quality, line
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
