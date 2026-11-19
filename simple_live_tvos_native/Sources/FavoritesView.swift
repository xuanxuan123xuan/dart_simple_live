import SwiftUI

struct FavoritePreferences {
    static let pageSize = "simple_live_tvos.follow.pageSize"
    static let layout = "simple_live_tvos.follow.layout"
    static let onlyLive = "simple_live_tvos.follow.onlyLive"
    static let refreshOnEnter = "simple_live_tvos.follow.refreshOnEnter"
    static let refreshMinutes = "simple_live_tvos.follow.refreshMinutes"
    static let showLiveCover = "simple_live_tvos.follow.showLiveCover"
}

enum FavoriteLayout: String, CaseIterable, Identifiable {
    case standard, compact, card

    var id: Self { self }
    var title: String {
        switch self {
        case .standard: "默认"
        case .compact: "紧凑"
        case .card: "大卡片"
        }
    }
    var minimumWidth: CGFloat {
        switch self {
        case .standard: 280
        case .compact: 220
        case .card: 365
        }
    }
}

struct FavoritesView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var status: FavoriteStatusStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(FavoritePreferences.pageSize) private var pageSize = 200
    @AppStorage(FavoritePreferences.layout) private var layout = FavoriteLayout.standard
    @AppStorage(FavoritePreferences.onlyLive) private var onlyLive = false
    @AppStorage(FavoritePreferences.refreshOnEnter) private var refreshOnEnter = false
    @AppStorage(FavoritePreferences.refreshMinutes) private var refreshMinutes = 0
    @AppStorage(FavoritePreferences.showLiveCover) private var showLiveCover = false
    @State private var provider: String?
    @State private var priorityOnly = false
    @State private var page = 0
    @State private var manage = false
    @State private var refreshRequest: RefreshRequest?
    @FocusState private var focusedRoom: String?
    @State private var lastFocusedRoom: String?
    var preview = false
    var showAll: (() -> Void)?

    var body: some View {
        let entries = filteredEntries
        let pageCount = max(1, (entries.count + limit - 1) / limit)
        let currentPage = min(page, pageCount - 1)
        let visible = Array(entries.dropFirst(currentPage * limit).prefix(limit))
        VStack(alignment: .leading, spacing: 14) {
            tools(visible: visible)
            if !preview {
                filters
            }
            if visible.isEmpty {
                ContentUnavailableView(library.favoriteEntries.isEmpty ? "还没有关注" : "没有符合条件的关注",
                                       systemImage: "star")
            } else {
                grid(visible, queue: entries.map(\.room))
                if !preview && pageCount > 1 { pager(currentPage, of: pageCount) }
            }
        }
        .onChange(of: provider) { _, _ in page = 0 }
        .onChange(of: priorityOnly) { _, _ in page = 0 }
        .onChange(of: onlyLive) { _, _ in page = 0 }
        .onChange(of: pageSize) { _, _ in page = 0 }
        .task(id: refreshRequest) {
            guard let request = refreshRequest else { return }
            await refresh(request.rooms)
            if request == refreshRequest { refreshRequest = nil }
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active, preview || refreshOnEnter else { return }
            await refresh(library.favorites)
        }
        .task(id: scenePhase == .active ? refreshMinutes : 0) {
            guard scenePhase == .active, refreshMinutes > 0 else { return }
            let interval = Duration.seconds(min(refreshMinutes, 120) * 60)
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { break }
                await refresh(library.favorites)
            }
        }
    }

    private var limit: Int { preview ? 6 : min(max(2, pageSize), 400) }

    private var filteredEntries: [FavoriteEntry] {
        let entries = library.favoriteEntries.filter { entry in
            (provider == nil || entry.room.provider == provider) && (!priorityOnly || entry.isPriority)
                && (preview || !onlyLive || status.presence(for: entry.room) == .live)
        }
        // Keep one's library order stable within each priority level.
        return entries.filter(\.isPriority) + entries.filter { !$0.isPriority }
    }

    private func tools(visible: [FavoriteEntry]) -> some View {
        HStack(spacing: 18) {
            Text("我的关注").font(.system(size: preview ? 34 : 42, weight: .bold)).accessibilityAddTraits(.isHeader)
            Text("\(library.favoriteEntries.count) 个").foregroundStyle(.secondary)
            Spacer()
            if let showAll { Button("查看全部", action: showAll).accessibilityIdentifier("favorites-open-all") }
            Button(manage ? "完成管理" : "管理") { manage.toggle() }.disabled(library.favoriteEntries.isEmpty)
            if !preview {
                NavigationLink("多屏观看", value: HomeRoute.selectMultiRoom)
                    .accessibilityIdentifier("favorites-multi-room")
                Button("刷新本页") { refreshRequest = RefreshRequest(rooms: visible.map(\.room)) }
                    .disabled(visible.isEmpty || status.isRefreshing)
            }
            Button(status.isRefreshing ? "正在刷新" : "刷新全部") {
                refreshRequest = RefreshRequest(rooms: library.favorites)
            }
            .disabled(library.favoriteEntries.isEmpty || status.isRefreshing)
        }
        .focusSection()
    }

    private var filters: some View {
        HStack(spacing: 13) {
            chip("全平台", selected: provider == nil) { provider = nil }
            ForEach(core.providers) { option in
                chip(option.title, selected: provider == option.id) { provider = option.id }
            }
            chip("特别关注", selected: priorityOnly) { priorityOnly.toggle() }
            chip("只看开播", selected: onlyLive) { onlyLive.toggle() }
        }
        .focusSection()
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HomePill(selected: selected, quiet: false) { Text(title).lineLimit(1) }
        }
        .buttonStyle(HomeButtonStyle())
        .focusEffectDisabled()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func grid(_ entries: [FavoriteEntry], queue: [RoomDescriptor]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: preview ? 238 : layout.minimumWidth), spacing: 24)], spacing: 24) {
                ForEach(entries) { entry in
                    Group {
                        if manage {
                            Menu { actions(entry) } label: { card(entry) }
                        } else {
                            NavigationLink(value: HomeRoute.room(entry.room, queue: queue)) { card(entry) }
                                .contextMenu { actions(entry) }
                        }
                    }
                    .buttonStyle(HomeButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedRoom, equals: entry.id)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .defaultFocus($focusedRoom, entries.contains(where: { $0.id == lastFocusedRoom }) ? lastFocusedRoom : entries.first?.id)
        .onChange(of: focusedRoom) { _, value in
            if let value { lastFocusedRoom = value }
        }
        .focusSection()
    }

    private func card(_ entry: FavoriteEntry) -> some View {
        let presence = status.presence(for: entry.room)
        let name = entry.room.userName.isEmpty ? entry.room.title : entry.room.userName
        let platform = core.providers.first(where: { $0.id == entry.room.provider })?.title ?? entry.room.provider
        let title = entry.isPriority ? "★ \(name)" : name
        return RoomTile(room: entry.room, heading: title, caption: "\(platform) · \(presence.title)",
                        showCover: layout != .compact && (preview || (showLiveCover && presence == .live)),
                        coverOverride: presence == .live ? status.snapshots[entry.id]?.cover : nil)
    }

    @ViewBuilder
    private func actions(_ entry: FavoriteEntry) -> some View {
        Button(entry.isPriority ? "取消特别关注" : "设为特别关注") {
            library.setPriority(!entry.isPriority, room: entry.room)
        }
        Button("取消关注", role: .destructive) { library.toggleFavorite(entry.room) }
    }

    private func pager(_ index: Int, of count: Int) -> some View {
        HStack {
            Spacer()
            Button("上一页") { page = index - 1 }.disabled(index == 0)
            Text("\(index + 1) / \(count)").foregroundStyle(.secondary)
            Button("下一页") { page = index + 1 }.disabled(index + 1 == count)
            Spacer()
        }
        .focusSection()
    }

    private func refresh(_ rooms: [RoomDescriptor]) async {
        await status.refresh(rooms) { room in
            try await core.service(room.provider).resolveRoom(room.roomId)
        }
    }

    private struct RefreshRequest: Equatable {
        let rooms: [RoomDescriptor]
        let id = UUID()
    }
}

struct FavoriteSettingsView: View {
    @AppStorage(FavoritePreferences.pageSize) private var pageSize = 200
    @AppStorage(FavoritePreferences.layout) private var layout = FavoriteLayout.standard
    @AppStorage(FavoritePreferences.onlyLive) private var onlyLive = false
    @AppStorage(FavoritePreferences.refreshOnEnter) private var refreshOnEnter = false
    @AppStorage(FavoritePreferences.refreshMinutes) private var refreshMinutes = 0
    @AppStorage(FavoritePreferences.showLiveCover) private var showLiveCover = false

    var body: some View {
        List {
            Section("关注列表") {
                Picker("布局", selection: $layout) {
                    ForEach(FavoriteLayout.allCases) { Text($0.title).tag($0) }
                }
                Picker("每页数量", selection: $pageSize) {
                    ForEach([12, 24, 48, 100, 200, 400], id: \.self) { Text("\($0) 个").tag($0) }
                }
                Toggle("只显示开播关注", isOn: $onlyLive)
                Toggle("显示直播封面", isOn: $showLiveCover)
            }
            Section("状态刷新") {
                Toggle("进入关注页时刷新", isOn: $refreshOnEnter)
                Picker("定时刷新", selection: $refreshMinutes) {
                    Text("关闭").tag(0)
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text("每 \($0) 分钟").tag($0) }
                }
            }
        }
        .navigationTitle("关注设置")
    }
}
