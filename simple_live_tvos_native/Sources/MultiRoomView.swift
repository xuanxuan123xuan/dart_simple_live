import SwiftUI

struct MultiRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var group: MultiRoomGroup
    @State private var controlsVisible = true
    @State private var activity = 0
    @State private var sheet: ControlSheet?
    @State private var pendingExit: ExitAction?
    @FocusState private var focus: Focus?

    let openSingle: (RoomPlaybackHandoff, [RoomDescriptor]) -> Void

    init(rooms: [RoomDescriptor], restoring handoff: RoomPlaybackHandoff? = nil,
         openSingle: @escaping (RoomPlaybackHandoff, [RoomDescriptor]) -> Void) {
        _group = State(initialValue: MultiRoomGroup(rooms: rooms, restoring: handoff))
        self.openSingle = openSingle
    }

    var body: some View {
        GeometryReader { geometry in
            let primary = group.sessions.firstIndex { $0.room.key == group.primaryKey } ?? 0
            let frames = MultiRoomGeometry.frames(count: group.sessions.count, size: geometry.size,
                                                  layout: group.layout, primaryIndex: primary,
                                                  gap: CGFloat(group.spacing.rawValue))
            let expandedFrame = MultiRoomGeometry.fitted(in: CGRect(origin: .zero, size: geometry.size))
            ZStack(alignment: .topLeading) {
                Color.black
                ForEach(Array(zip(group.sessions, frames)), id: \.0.room.key) { session, regularFrame in
                    let key = session.room.key
                    let visible = group.expandedKey == nil || group.expandedKey == key
                    let frame = group.expandedKey == key ? expandedFrame : regularFrame
                    roomTile(session, visible: visible)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .opacity(visible ? 1 : 0)
                        .allowsHitTesting(visible)
                        .accessibilityHidden(!visible)
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if controlsVisible, let session = group.selected { controls(for: session) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.colorScheme, .dark)
        .defaultFocus($focus, group.selectedKey.map(Focus.tile))
        .onChange(of: focus) { _, value in
            activity += 1
            if case let .tile(key) = value, key != group.selectedKey {
                group.select(key)
                controlsVisible = true
            }
        }
        .onExitCommand(perform: controlsVisible || group.expandedKey != nil ? handleBack : nil)
        .onPlayPauseCommand {
            if let session = group.selected, session.playbackIssue == nil {
                session.engine.togglePlayback()
                showControls()
            }
        }
        .sheet(item: $sheet, onDismiss: finishSheet) { item in
            switch item {
            case .room:
                if let session = group.selected {
                    MultiRoomPaneControls(group: group, session: session) {
                        pendingExit = .single(session.handoff(danmakuEnabled: session.danmakuOverride == true))
                        sheet = nil
                    } remove: {
                        group.remove(session.room.key)
                        sheet = nil
                        focusSelected()
                    }
                }
            case .group:
                groupControls
            case .rooms:
                MultiRoomPickerView(rooms: group.rooms, confirmTitle: "应用房间") { rooms in
                    if group.replaceRooms(rooms) {
                        sheet = nil
                        focusSelected()
                    }
                }
            }
        }
        .task(id: hideAfterActivity) {
            guard let expected = hideAfterActivity else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled, hideAfterActivity == expected else { return }
            hideControls()
        }
        .onDisappear { group.stop() }
    }

    private var hideAfterActivity: Int? {
        controlsVisible && sheet == nil && scenePhase == .active ? activity : nil
    }

    private func roomTile(_ session: RoomPlaybackSession, visible: Bool) -> some View {
        let key = session.room.key
        let showsDanmaku = visible && session.danmakuOverride == true
        return ZStack(alignment: .topLeading) {
            RoomVideoView(engine: session.engine)
            if showsDanmaku, scenePhase == .active, session.playbackIssue == nil {
                DanmakuOverlay(events: session.danmakuEvents, showControls: controlsVisible && group.selectedKey == key)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if let issue = session.playbackIssue {
                VStack(spacing: 12) {
                    Image(systemName: "play.slash")
                    Text(issue.title).lineLimit(1)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !session.engine.pausedByUser, session.engine.state != .playing {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if controlsVisible {
                Text(session.room.title)
                    .font(.caption.weight(.semibold)).lineLimit(1)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.72))
                    .accessibilityHidden(true)
            }
            if visible {
                Button {
                    group.select(key)
                    showControls()
                    if group.expandedKey == key { focus = .expand }
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(PlaybackSurfaceButtonStyle())
                .focusEffectDisabled()
                .focused($focus, equals: .tile(key))
                .onMoveCommand(perform: group.expandedKey == key ? { direction in
                    if direction == .down {
                        showControls()
                        focus = .expand
                    }
                } : nil)
                .accessibilityLabel(session.room.title)
                .accessibilityValue(session.playbackStatus)
                .accessibilityIdentifier("multi-room-tile-\(key)")
            }
        }
        .clipped()
        .overlay {
            if controlsVisible, group.selectedKey == key {
                Rectangle().strokeBorder(focus == .tile(key) ? .white : .white.opacity(0.45), lineWidth: 4)
                    .allowsHitTesting(false)
            }
        }
        .modifier(RoomPlaybackActivity(session: session, showsDanmaku: showsDanmaku))
    }

    private func controls(for session: RoomPlaybackSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.room.title).font(.headline).lineLimit(1)
                Text(session.playbackStatus).font(.caption).lineLimit(1)
                if !session.engine.isEffectivelyMuted, session.engine.volume > 0 {
                    Image(systemName: "speaker.wave.2.fill").accessibilityLabel("有声")
                }
                Spacer()
                Text("\(group.sessions.count) 路").font(.caption).monospacedDigit()
            }
            HStack(spacing: 22) {
                Button(session.engine.pausedByUser ? "继续" : "暂停") {
                    session.engine.togglePlayback()
                    showControls()
                }
                .disabled(session.playbackIssue != nil)
                .focused($focus, equals: .playPause)
                .accessibilityIdentifier("multi-room-play-pause")
                Button(group.expandedKey == nil ? "放大此路" : "恢复多屏") {
                    group.toggleExpanded(session.room.key)
                    showControls()
                    focus = .expand
                }
                .focused($focus, equals: .expand)
                .accessibilityIdentifier("multi-room-expand")
                Button("本路控制") { sheet = .room }
                    .focused($focus, equals: .roomControls)
                    .accessibilityIdentifier("multi-room-pane-controls")
                Button("整组控制") { sheet = .group }
                    .focused($focus, equals: .groupControls)
                    .accessibilityIdentifier("multi-room-group-controls")
                Button("管理房间") { sheet = .rooms }
                    .focused($focus, equals: .manageRooms)
                    .accessibilityIdentifier("multi-room-edit")
            }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 18)
        .focusSection()
    }

    private var groupControls: some View {
        MultiRoomControlPanel(title: "整组控制") {
            Picker("布局", selection: $group.layout) {
                ForEach(MultiRoomLayout.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("声音", selection: Binding(get: { group.audioMode }, set: group.setAudioMode)) {
                ForEach(MultiRoomAudioMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Button(group.allPaused ? "全部继续" : "全部暂停") { group.setPaused(!group.allPaused) }
            Button("全部刷新") { group.refresh() }
            Button(group.allDanmakuEnabled ? "全部关闭弹幕" : "全部开启弹幕") {
                group.setDanmaku(!group.allDanmakuEnabled)
            }
            Button("退出多屏", role: .destructive) {
                pendingExit = .back
                sheet = nil
            }
        }
    }

    private func finishSheet() {
        activity += 1
        guard let exit = pendingExit else { return }
        pendingExit = nil
        group.retire()
        switch exit {
        case .back: dismiss()
        case let .single(handoff): openSingle(handoff, group.rooms)
        }
    }

    private func showControls() {
        activity += 1
        controlsVisible = true
    }

    private func hideControls() {
        controlsVisible = false
        focusSelected()
    }

    private func focusSelected() {
        focus = group.selectedKey.map(Focus.tile)
    }

    private func handleBack() {
        if sheet != nil {
            sheet = nil
        } else if controlsVisible {
            hideControls()
        } else if let expanded = group.expandedKey {
            group.toggleExpanded(expanded)
            showControls()
            focusSelected()
        }
    }

    private enum ExitAction {
        case back
        case single(RoomPlaybackHandoff)
    }

    private enum ControlSheet: String, Identifiable {
        case room, group, rooms
        var id: Self { self }
    }

    private enum Focus: Hashable {
        case tile(String), playPause, expand, roomControls, groupControls, manageRooms
    }
}

private struct MultiRoomPaneControls: View {
    let group: MultiRoomGroup
    let session: RoomPlaybackSession
    let openSingle: () -> Void
    let remove: () -> Void

    private var engine: PlaybackEngine { session.engine }

    var body: some View {
        MultiRoomControlPanel(title: session.room.title) {
            Section("播放") {
                if let issue = session.playbackIssue, case let .failed(message) = issue {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Button(engine.pausedByUser ? "继续播放" : "暂停播放") { engine.togglePlayback() }
                    .disabled(session.playbackIssue != nil)
                Button("刷新本路") { session.refresh() }
                if let selected = session.selectedQuality {
                    Picker("清晰度", selection: Binding(get: { selected }, set: { session.selectQuality($0) })) {
                        ForEach(session.qualities) { Text($0.name).tag($0) }
                    }
                }
                if !session.availableLines.isEmpty {
                    Picker("线路", selection: Binding(get: { engine.currentLine ?? session.availableLines.first ?? 0 },
                                                     set: session.selectLine)) {
                        ForEach(session.availableLines, id: \.self) { Text("线路 \($0 + 1)").tag($0) }
                    }
                }
                if let message = session.qualityRecoveryMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("声音和弹幕") {
                if group.audioMode == .single {
                    Button(group.audioKey == session.room.key ? "本路为声音来源" : "将声音切换到本路") {
                        group.setAudioFocus(session.room.key)
                    }
                    .disabled(group.audioKey == session.room.key)
                }
                Toggle("静音", isOn: Binding(get: { engine.isMuted }, set: engine.setMuted))
                HStack {
                    Text("音量 \(engine.volume)%").monospacedDigit()
                    Spacer()
                    Button("降低") { engine.setVolume(engine.volume - 10) }.disabled(engine.volume == 0)
                    Button("提高") { engine.setVolume(engine.volume + 10) }.disabled(engine.volume == 100)
                }
                .buttonStyle(.bordered)
                Toggle("本路弹幕", isOn: Binding(get: { session.danmakuOverride == true },
                                               set: { session.danmakuOverride = $0 }))
                if let message = session.danmakuError {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("房间") {
                Button("设为主画面") { group.makePrimary(session.room.key) }
                Button("转为单路播放", action: openSingle)
                    .accessibilityIdentifier("multi-room-open-single")
                Button("移除此路", role: .destructive, action: remove).disabled(group.sessions.count <= 2)
            }
        }
    }
}

private struct MultiRoomControlPanel<Controls: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder let controls: Controls

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                Button("关闭") { dismiss() }
                Text(title).font(.title.bold()).lineLimit(1).accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .focusSection()
            List { controls }
                .pickerStyle(.menu)
                .focusSection()
        }
        .padding(32)
        .frame(width: 1060, height: 800)
    }
}
