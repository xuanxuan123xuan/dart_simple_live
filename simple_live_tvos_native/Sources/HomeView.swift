import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @StateObject private var library = LibraryStore()
    @StateObject private var favoriteStatus = FavoriteStatusStore()
    @State private var section: HomeSection = .home
    @State private var provider = "bilibili"
    @State private var searchQuery = ""
    @State private var searchMode: SearchMode = .rooms
    @State private var path: [HomeRoute] = []
    @FocusState private var focusedSection: HomeSection?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 16) {
                HomePlatformBar(providers: section == .live || section == .search ? core.providers : [], selection: provider) { id in
                    provider = id
                    if section != .search { section = .live }
                }

                sectionContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HomeBottomBar(selection: section, focus: $focusedSection) { section = $0 }
            }
            .padding(.horizontal, 12)
            .background { HomeBackdrop() }
            .environment(\.colorScheme, .dark)
            .toolbar(.hidden, for: .navigationBar)
            .onExitCommand(perform: focusedSection == nil ? { focusedSection = section } : nil)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case let .categories(provider):
                    CategoryListView(provider: provider, category: nil)
                case let .categoryChildren(provider, category):
                    CategoryListView(provider: provider, category: category)
                case let .categoryRooms(provider, category):
                    HomeRoomResults(provider: provider, listing: category.map(RoomListing.category) ?? .recommended)
                        .navigationTitle(category?.name ?? "全部直播")
                case let .openRoom(provider):
                    OpenRoomView(provider: provider) { path = [.room($0)] }
                case let .room(room, rooms):
                    ChannelPlayerView(room: room, rooms: rooms, openMultiRoom: openMultiRoom)
                case let .sync(category):
                    SyncView(category: category)
                case .selectMultiRoom:
                    MultiRoomPickerView { rooms in
                        guard path.last == .selectMultiRoom else { return }
                        path[path.count - 1] = .multiRoom(rooms, seed: nil)
                    }
                case let .multiRoom(rooms, seed):
                    MultiRoomView(rooms: rooms, restoring: seed, openSingle: openSingleRoom)
                case let .singleFromMulti(handoff, queue):
                    ChannelPlayerView(room: handoff.room, rooms: queue, restoring: handoff, openMultiRoom: openMultiRoom)
                }
            }
        }
        .environmentObject(library)
        .environmentObject(favoriteStatus)
        .onChange(of: library.favorites, initial: true) { _, rooms in favoriteStatus.keepOnly(rooms) }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .home:
            dashboard
        case .live:
            browse
        case .search:
            search
        case .favorites:
            FavoritesView()
                .frame(maxHeight: .infinity, alignment: .topLeading)
        case .history:
            HistoryView()
        case .settings:
            VStack(alignment: .leading, spacing: 12) {
                pageTitle("设置")
                SettingsView()
            }
        }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                dashboardShortcut("热门直播", icon: "flame") { section = .live }
                NavigationLink(value: HomeRoute.categories(provider == "xiaohongshu" ? "bilibili" : provider)) {
                    HomePill(quiet: false) { Label("直播类目", systemImage: "square.grid.2x2") }
                }
                .buttonStyle(HomeButtonStyle())
                .focusEffectDisabled()
                .accessibilityIdentifier("live-categories")
                dashboardShortcut("搜索直播", icon: "magnifyingglass") { section = .search }
                dashboardShortcut("观看历史", icon: "clock") { section = .history }
                NavigationLink(value: HomeRoute.sync(nil)) {
                    HomePill(quiet: false) { Label("数据同步", systemImage: "arrow.triangle.2.circlepath") }
                }
                .buttonStyle(HomeButtonStyle())
                .focusEffectDisabled()
                .accessibilityIdentifier("home-data-sync")
                NavigationLink(value: HomeRoute.selectMultiRoom) {
                    HomePill(quiet: false) { Label("多屏观看", systemImage: "rectangle.split.2x2") }
                }
                .buttonStyle(HomeButtonStyle())
                .focusEffectDisabled()
                .accessibilityIdentifier("home-multi-room")
                Spacer()
                openRoomLink
            }
            .focusSection()
            FavoritesView(preview: true) { section = .favorites }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func dashboardShortcut(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HomePill(quiet: false) { Label(title, systemImage: icon) } }
            .buttonStyle(HomeButtonStyle())
            .focusEffectDisabled()
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: 10) {
            browseTools
            Group {
                if provider == "xiaohongshu" {
                    ContentUnavailableView {
                        Label("小红书直播发现暂不可用", systemImage: "link")
                    } description: {
                        Text("仍可通过直播链接或房间号进入。")
                    } actions: {
                        openRoomLink
                    }
                } else {
                    HomeRoomResults(provider: provider, listing: .recommended)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var browseTools: some View {
        HStack(spacing: 12) {
            pageTitle("推荐直播")
            Spacer()

            if provider != "xiaohongshu" {
                NavigationLink(value: HomeRoute.categories(provider)) {
                    HomePill(quiet: false) {
                        Label("直播类目", systemImage: "square.grid.2x2")
                            .lineLimit(1)
                    }
                }
                .buttonStyle(HomeButtonStyle())
                .focusEffectDisabled()
                .accessibilityIdentifier("live-categories")

                openRoomLink
            }
        }
        .focusSection()
    }

    private var search: some View {
        let term = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let platform = core.providers.first(where: { $0.id == provider })?.title ?? ""

        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 24) {
                pageTitle("搜索")
                Spacer()
                if provider == "xiaohongshu" {
                    openRoomLink
                } else {
                    ForEach(SearchMode.allCases, id: \.self) { mode in
                        Button { searchMode = mode } label: {
                            HomePill(selected: searchMode == mode, quiet: false) { Text(mode.title) }
                        }
                        .buttonStyle(HomeButtonStyle())
                        .focusEffectDisabled()
                        .accessibilityAddTraits(searchMode == mode ? .isSelected : [])
                    }
                    TextField("搜索\(searchMode.title)", text: $searchQuery,
                              prompt: Text("搜索\(platform)\(searchMode.title)").foregroundStyle(.white.opacity(0.68)))
                        .autocorrectionDisabled()
                        .frame(width: 620)
                        .accessibilityIdentifier("search-query")
                }
            }
            .focusSection()

            Group {
                if provider == "xiaohongshu" {
                    ContentUnavailableView("小红书支持用直播链接进房", systemImage: "link")
                } else if term.isEmpty {
                    ContentUnavailableView("输入主播名或关键词", systemImage: "magnifyingglass")
                } else {
                    HomeRoomResults(provider: provider, listing: .search(term, searchMode))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var openRoomLink: some View {
        NavigationLink(value: HomeRoute.openRoom(provider)) {
            HomePill(quiet: false) {
                Label("房间号 / 链接", systemImage: "link")
            }
        }
        .buttonStyle(HomeButtonStyle())
        .focusEffectDisabled()
        .accessibilityIdentifier("live-open-room")
    }

    private func openMultiRoom(_ rooms: [RoomDescriptor], _ seed: RoomPlaybackHandoff) {
        path.append(.multiRoom(rooms, seed: seed))
    }

    private func openSingleRoom(_ handoff: RoomPlaybackHandoff, _ queue: [RoomDescriptor]) {
        guard case .multiRoom = path.last else { return }
        path.removeLast()
        switch path.last {
        case .room, .singleFromMulti: path.removeLast()
        default: break
        }
        path.append(.singleFromMulti(handoff, queue: queue))
    }

    private func pageTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 42, weight: .bold))
            .accessibilityAddTraits(.isHeader)
    }
}

enum HomeRoute: Hashable {
    case categories(String)
    case categoryChildren(String, CategoryDescriptor)
    case categoryRooms(String, CategoryDescriptor?)
    case openRoom(String)
    case room(RoomDescriptor, queue: [RoomDescriptor] = [])
    case sync(SyncCategory?)
    case selectMultiRoom
    case multiRoom([RoomDescriptor], seed: RoomPlaybackHandoff?)
    case singleFromMulti(RoomPlaybackHandoff, queue: [RoomDescriptor])
}

private struct CategoryListView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @FocusState private var focused: String?
    @State private var lastFocused: String?
    @State private var catalog: [CategoryDescriptor]?
    @State private var error: String?
    @State private var retry = 0
    let provider: String
    let category: CategoryDescriptor?

    var body: some View {
        Group {
            if let categories = category?.children ?? catalog {
                categoryGrid(categories)
            } else if let error {
                ContentUnavailableView {
                    Label("无法加载直播类目", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { retry += 1 }
                }
            } else {
                ProgressView("正在加载直播类目")
            }
        }
        .navigationTitle(category?.name ?? "直播类目")
        .task(id: retry) {
            guard category == nil, catalog == nil else { return }
            error = nil
            do {
                var seen = Set<String>()
                let result = try await core.service(provider).categories()
                try Task.checkCancellation()
                catalog = result.filter { seen.insert($0.id).inserted }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    private var includesAll: Bool { category?.canBrowseRooms ?? true }

    @ViewBuilder
    private func categoryGrid(_ categories: [CategoryDescriptor]) -> some View {
        if categories.isEmpty && !includesAll {
            ContentUnavailableView("暂无子类目", systemImage: "square.grid.2x2")
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 26)], spacing: 26) {
                    if includesAll {
                        categoryLink("全部", id: "all", icon: "square.grid.2x2", route: .categoryRooms(provider, category))
                    }
                    ForEach(categories) { item in
                        let branch = !item.children.isEmpty || !item.canBrowseRooms
                        categoryLink(item.name, id: item.id, icon: branch ? "folder" : "tv",
                                     route: branch ? .categoryChildren(provider, item) : .categoryRooms(provider, item))
                    }
                }
                .padding(28)
            }
            .defaultFocus($focused, lastFocused ?? (includesAll ? "all" : categories.first?.id))
            .onChange(of: focused) { _, value in
                if let value { lastFocused = value }
            }
        }
    }

    private func categoryLink(_ title: String, id: String, icon: String, route: HomeRoute) -> some View {
        NavigationLink(value: route) {
            HomePill(quiet: false) {
                Label(title, systemImage: icon).lineLimit(1).frame(maxWidth: .infinity, minHeight: 64)
            }
        }
        .buttonStyle(HomeButtonStyle())
        .focusEffectDisabled()
        .focused($focused, equals: id)
    }
}

private struct HomeRoomResults: View {
    @EnvironmentObject private var core: NativeCoreClient
    @StateObject private var results = RoomResultsStore()
    @State private var retry = 0
    @State private var pagination: Pagination?
    let provider: String
    let listing: RoomListing

    var body: some View {
        let query = RoomResultsStore.Query(provider: provider, listing: listing, retry: retry)
        let request = pagination.flatMap { $0.query == query ? $0 : nil }
        content(query)
            .task(id: query) { await load(query, next: false) }
            .task(id: request) {
                guard let request else { return }
                await load(request.query, next: true)
                if pagination == request { pagination = nil }
            }
    }

    @ViewBuilder
    private func content(_ query: RoomResultsStore.Query) -> some View {
        if results.query != query || results.status == .idle {
            ProgressView()
        } else if results.rooms.isEmpty && !results.hasMore {
            switch results.status {
            case .idle, .loading:
                ProgressView()
            case let .failed(message):
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") { retry += 1 }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()
            case .loaded:
                ContentUnavailableView(emptyTitle, systemImage: "tv")
            }
        } else if results.rooms.isEmpty {
            VStack(spacing: 18) {
                ContentUnavailableView(emptyTitle, systemImage: "tv")
                pageFooter(query)
            }
            .frame(maxWidth: .infinity)
            .focusSection()
        } else {
            RoomGrid(rooms: results.rooms) { pageFooter(query) }
        }
    }

    @ViewBuilder
    private func pageFooter(_ query: RoomResultsStore.Query) -> some View {
        switch results.status {
        case let .failed(message):
            Text(message).foregroundStyle(.secondary)
            Button("重试加载更多") { pagination = Pagination(query: query) }
        case .loading:
            ProgressView("正在加载更多")
        case .idle, .loaded:
            if results.hasMore {
                Button("加载更多") { pagination = Pagination(query: query) }
            } else {
                Text("已到底").foregroundStyle(.secondary)
            }
        }
    }

    private func load(_ query: RoomResultsStore.Query, next: Bool) async {
        await results.load(query, next: next) { page in
            if case .search = query.listing, !next { try await Task.sleep(for: .milliseconds(350)) }
            return try await core.service(query.provider).rooms(in: query.listing, page: page)
        }
    }

    private var emptyTitle: LocalizedStringKey {
        if case let .search(_, mode) = listing { return mode == .anchors ? "未找到相关主播" : "未找到相关直播间" }
        return "暂无直播间"
    }

    private struct Pagination: Equatable {
        let query: RoomResultsStore.Query
        let id = UUID()
    }
}

private struct OpenRoomView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @State private var input = ""
    @State private var error: String?
    @State private var submission: String?
    @State private var selectedProvider: String?
    let provider: String
    let open: (RoomDescriptor) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("分享链接会自动识别平台。输入房间号时，请先选择所属平台。")
                .foregroundStyle(.secondary)
            HStack(spacing: 18) {
                ForEach(core.providers) { platform in
                    Button { selectedProvider = platform.id } label: {
                        HomePill(selected: activeProvider == platform.id, quiet: false) { Text(platform.title) }
                    }
                    .buttonStyle(HomeButtonStyle())
                    .focusEffectDisabled()
                    .accessibilityAddTraits(activeProvider == platform.id ? .isSelected : [])
                }
            }
            .focusSection()
            .disabled(submission != nil)
            TextField("房间号或直播链接", text: $input)
                .autocorrectionDisabled()
                .onSubmit { submit() }
                .frame(maxWidth: 850)
                .accessibilityIdentifier("open-room-input")
            Button("进入直播间", action: submit)
                .disabled(submission != nil || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if submission != nil { ProgressView() }
            if let error { Text(error) }
        }
        .navigationTitle("进入直播间")
        .task(id: submission) {
            guard let submission else { return }
            error = nil
            defer { if !Task.isCancelled { self.submission = nil } }
            do {
                let room = try await core.resolveRoomInput(submission, provider: activeProvider)
                try Task.checkCancellation()
                open(room)
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    private var activeProvider: String { selectedProvider ?? provider }

    private func submit() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if submission == nil, !value.isEmpty { submission = value }
    }
}

private struct RoomGrid<Footer: View>: View {
    @EnvironmentObject private var library: LibraryStore
    @FocusState private var focusedRoom: String?
    @State private var lastFocusedRoom: String?
    let rooms: [RoomDescriptor]
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        if rooms.isEmpty {
            ContentUnavailableView("暂无直播间", systemImage: "tray")
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 24)], spacing: 24) {
                    ForEach(rooms) { room in
                        NavigationLink(value: HomeRoute.room(room, queue: rooms)) {
                            RoomTile(room: room)
                        }
                        .buttonStyle(HomeButtonStyle())
                        .focusEffectDisabled()
                        .focused($focusedRoom, equals: room.key)
                        .contextMenu {
                            Button(library.isFavorite(room) ? "取消收藏" : "收藏") { library.toggleFavorite(room) }
                        }
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .focusSection()
                VStack(spacing: 12) { footer() }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .focusSection()
            }
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 22)
                }
            }
            .defaultFocus($focusedRoom, rooms.contains(where: { $0.key == lastFocusedRoom }) ? lastFocusedRoom : rooms.first?.key)
            .onChange(of: focusedRoom) { _, value in
                if let value { lastFocusedRoom = value }
            }
            .focusSection()
        }
    }
}

struct RoomTile: View {
    @Environment(\.isFocused) private var isFocused
    let room: RoomDescriptor
    var heading: String? = nil
    var caption: String? = nil
    var showCover = true
    var coverOverride: String? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        VStack(alignment: .leading, spacing: 0) {
            if showCover { cover }
            VStack(alignment: .leading, spacing: 4) {
                Text(heading ?? room.title)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                if let caption {
                    Text(caption).font(.system(size: 20)).foregroundStyle(.secondary).lineLimit(1)
                } else if let isLive = room.isLive {
                    Label(isLive ? "直播中" : "未开播", systemImage: isLive ? "dot.radiowaves.left.and.right" : "moon")
                        .font(.system(size: 20))
                        .foregroundStyle(isLive ? Color.green : Color.white.opacity(0.64))
                } else {
                    Text(room.userName.isEmpty || room.userName == room.title ? room.roomId : room.userName)
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .background(Color(red: 0.11, green: 0.09, blue: 0.16), in: shape)
        .clipShape(shape)
        .overlay { shape.strokeBorder(isFocused ? Color(red: 0.83, green: 0.73, blue: 1) : .white.opacity(0.10), lineWidth: isFocused ? 3 : 1) }
        .scaleEffect(isFocused ? 1.035 : 1)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .accessibilityElement(children: .combine)
    }

    private var cover: some View {
        Color.white.opacity(0.06)
                .aspectRatio(16.0 / 9, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        AsyncImage(url: URL(string: coverOverride.flatMap { $0.isEmpty ? nil : $0 } ?? room.cover)) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Image(systemName: "play.tv")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.white.opacity(0.24))
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    }
                }
                .accessibilityHidden(true)
    }
}
