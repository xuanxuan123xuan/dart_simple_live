import SimpleLiveTVOSCore
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MultiRoomPreferences.globalDanmakuKey) private var danmakuEnabled = true

    let room: RoomDescriptor
    let queue: ChannelQueue
    @Binding var sleepDeadline: Date?
    let onPlaybackIssue: (PlaybackIssue?, String) -> Void
    let onStablePlayback: () -> Void
    let openMultiRoom: ([RoomDescriptor], RoomPlaybackHandoff) -> Void
    let openChannel: (RoomDescriptor) -> Void

    @State private var session: RoomPlaybackSession
    @State private var sleepExpired = false
    @State private var controlsVisible = true
    @State private var controlsActivity = 0
    @State private var selectionMenu: PlayerMenu?
    @State private var activeSheet: PlayerSheet?
    @State private var pendingMultiRoom: [RoomDescriptor]?
    @FocusState private var focusedControl: PlayerFocus?

    init(room: RoomDescriptor, queue: ChannelQueue, sleepDeadline: Binding<Date?>,
         restoring handoff: RoomPlaybackHandoff? = nil, onPlaybackIssue: @escaping (PlaybackIssue?, String) -> Void,
         onStablePlayback: @escaping () -> Void,
         openMultiRoom: @escaping ([RoomDescriptor], RoomPlaybackHandoff) -> Void,
         openChannel: @escaping (RoomDescriptor) -> Void) {
        self.room = room
        self.queue = queue
        _sleepDeadline = sleepDeadline
        _session = State(initialValue: RoomPlaybackSession(room: room, restoring: handoff))
        self.onPlaybackIssue = onPlaybackIssue
        self.onStablePlayback = onStablePlayback
        self.openMultiRoom = openMultiRoom
        self.openChannel = openChannel
    }

    private var engine: PlaybackEngine { session.engine }
    private var playbackIssue: PlaybackIssue? { session.playbackIssue }
    private var danmaku: Binding<Bool> {
        Binding(get: { session.danmakuOverride ?? danmakuEnabled }, set: {
            if session.danmakuOverride == nil { danmakuEnabled = $0 }
            else { session.danmakuOverride = $0 }
        })
    }

    var body: some View {
        ZStack {
            RoomVideoView(engine: engine).ignoresSafeArea()
            if !controlsVisible && playbackIssue == nil && !sleepExpired {
                Button(action: showControls) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlaybackSurfaceButtonStyle())
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
            if danmaku.wrappedValue, scenePhase == .active, playbackIssue == nil, !sleepExpired {
                DanmakuOverlay(events: session.danmakuEvents, showControls: controlsVisible)
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
        .onPlayPauseCommand {
            guard activeSheet == nil, selectionMenu == nil, !sleepExpired else { return }
            togglePlayback()
            if !controlsVisible { showControls() }
        }
        .sheet(item: $activeSheet, onDismiss: finishSheet) { sheet in
            switch sheet {
            case .channels:
                PlayerChannelList(current: room, queue: queue, select: openChannel)
            case .favorites:
                PlayerChannelList(current: room, rooms: library.favorites, title: "收藏列表", select: openChannel)
            case .settings:
                PlayerRoomSettingsView(room: room, engine: engine, danmakuEnabled: danmaku,
                                       sleepDeadline: $sleepDeadline)
            case .multiRoom:
                MultiRoomPickerView(rooms: [room]) { rooms in
                    pendingMultiRoom = rooms
                    activeSheet = nil
                }
            }
        }
        .onChange(of: focusedControl) { _, _ in controlsActivity += 1 }
        .onChange(of: playbackIssue) { _, issue in
            onPlaybackIssue(engine.pausedByUser ? nil : issue, room.key)
            guard !sleepExpired else { return }
            if issue != nil { focusedControl = .retry }
            else if focusedControl == .retry { focusedControl = preferredFocus }
        }
        .task(id: engine.state == .playing) {
            guard engine.state == .playing else { return }
            do {
                try await Task.sleep(for: .seconds(20))
                try Task.checkCancellation()
                if engine.state == .playing { onStablePlayback() }
            } catch { return }
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
        .modifier(RoomPlaybackActivity(session: session,
                                       isEnabled: !sleepExpired && (sleepDeadline.map { $0 > .now } ?? true),
                                       showsDanmaku: danmaku.wrappedValue))
    }

    private var autoHideActivity: Int? {
        controlsVisible && !sleepExpired && selectionMenu == nil && activeSheet == nil && scenePhase == .active ? controlsActivity : nil
    }

    private var firstControl: PlayerFocus { .playPause }

    private var preferredFocus: PlayerFocus {
        if sleepExpired { return .sleepExit }
        if playbackIssue != nil { return .retry }
        return controlsVisible ? firstControl : .video
    }

    private var playerControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(room.title).font(.headline).lineLimit(1)
                Text(session.playbackStatus).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("player-status")
                if let sleepDeadline {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("定时关闭 \(SleepTimerDisplay.remaining(until: sleepDeadline, now: context.date))")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if let qualityRecoveryMessage = session.qualityRecoveryMessage { Text(qualityRecoveryMessage).font(.caption).foregroundStyle(.secondary) }
                if let danmakuError = session.danmakuError { Text(danmakuError).font(.caption).foregroundStyle(.secondary) }
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
            if !session.qualities.isEmpty {
                Button(session.selectedQuality?.name ?? "清晰度") { selectionMenu = .quality }
                    .focused($focusedControl, equals: .quality)
                    .accessibilityLabel("清晰度")
                    .accessibilityValue(session.selectedQuality?.name ?? "")
                    .accessibilityIdentifier("player-quality")
                    .confirmationDialog("清晰度", isPresented: menuIsPresented(.quality), titleVisibility: .visible) {
                        ForEach(session.qualities) { quality in
                            Button(quality.name) { session.selectQuality(quality) }
                        }
                    }
            }
            Button(engine.currentLine.map(lineTitle) ?? "线路") { selectionMenu = .line }
                .disabled(session.availableLines.isEmpty)
                .focused($focusedControl, equals: .line)
                .accessibilityLabel("线路")
                .accessibilityValue(engine.currentLine.map(lineTitle) ?? "")
                .accessibilityIdentifier("player-line")
                .confirmationDialog("选择线路", isPresented: menuIsPresented(.line), titleVisibility: .visible) {
                    ForEach(session.availableLines, id: \.self) { line in
                        Button(line == engine.currentLine ? "\(lineTitle(line))（当前）" : lineTitle(line)) {
                            session.selectLine(line)
                        }
                    }
                }
        }
    }

    private var roomActions: some View {
        HStack(spacing: 16) {
            Button {
                danmaku.wrappedValue.toggle()
                controlsActivity += 1
            } label: {
                Label(danmaku.wrappedValue ? "弹幕开" : "弹幕关", systemImage: danmaku.wrappedValue ? "text.bubble.fill" : "text.bubble")
            }
            .focused($focusedControl, equals: .danmaku)
            .accessibilityLabel("弹幕")
            .accessibilityValue(danmaku.wrappedValue ? "开" : "关")
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
            Button("多屏观看") { activeSheet = .multiRoom }
                .focused($focusedControl, equals: .multiRoom)
                .accessibilityIdentifier("player-multi-room")
            Button("房内设置") { activeSheet = .settings }
                .focused($focusedControl, equals: .settings)
                .accessibilityIdentifier("player-room-settings")
        }
    }

    private func finishSheet() {
        controlsActivity += 1
        if sleepExpired {
            focusedControl = .sleepExit
            return
        }
        guard let rooms = pendingMultiRoom else { return }
        pendingMultiRoom = nil
        let handoff = session.handoff(danmakuEnabled: danmaku.wrappedValue)
        session.stop()
        openMultiRoom(rooms, handoff)
    }

    private func refreshPlayback() {
        onPlaybackIssue(nil, room.key)
        controlsActivity += 1
        session.refresh()
    }

    private func togglePlayback() {
        guard playbackIssue == nil, !sleepExpired else { return }
        engine.togglePlayback()
        controlsActivity += 1
    }

    private func stopForSleepTimer() {
        guard !sleepExpired else { return }
        sleepExpired = true
        focusedControl = activeSheet == nil ? .sleepExit : nil
        pendingMultiRoom = nil
        activeSheet = nil
        selectionMenu = nil
        session.stop()
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
}

private enum PlayerFocus: Hashable {
    case video, playPause, refresh, channels, quality, line, danmaku, favorite, favoriteList, multiRoom, settings, retry, sleepExit
}

private enum PlayerSheet: String, Identifiable {
    case channels, favorites, settings, multiRoom
    var id: Self { self }
}

private enum PlayerMenu {
    case quality, line
}
