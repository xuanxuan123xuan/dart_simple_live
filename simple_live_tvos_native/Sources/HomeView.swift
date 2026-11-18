import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @StateObject private var library = LibraryStore()
    @State private var section: HomeSection = .live
    @State private var provider = "bilibili"
    @State private var searchQuery = ""
    @State private var category: CategoryDescriptor?
    @State private var path: [HomeRoute] = []
    @FocusState private var focusedSection: HomeSection?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 16) {
                HomePlatformBar(providers: core.providers, selection: provider) { id in
                    if provider != id {
                        category = nil
                        provider = id
                    }
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
                case .categories:
                    CategoryListView(categories: core.categories, selected: $category)
                case let .openRoom(provider):
                    OpenRoomView(provider: provider) { path = [.room($0)] }
                case let .room(room):
                    PlayerView(room: room)
                }
            }
        }
        .environmentObject(library)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .live:
            browse
        case .search:
            search
        case .favorites:
            libraryPage(.favorites, rooms: library.favorites)
        case .history:
            libraryPage(.history, rooms: library.recent)
        case .settings:
            VStack(alignment: .leading, spacing: 12) {
                pageTitle("设置")
                SettingsView()
            }
        }
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: 10) {
            browseTools
            HomeRoomResults(provider: provider, listing: category.map(RoomListing.category) ?? .recommended)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: provider) { await core.loadCategories(provider: provider) }
    }

    private var browseTools: some View {
        HStack(spacing: 12) {
            pageTitle(category == nil ? "推荐直播" : "分类直播")
            Spacer()

            if !core.categories.isEmpty {
                NavigationLink(value: HomeRoute.categories) {
                    HomePill(quiet: false) {
                        Label(category?.name ?? "分类", systemImage: "square.grid.2x2")
                            .lineLimit(1)
                    }
                }
                .buttonStyle(HomeButtonStyle())
                .focusEffectDisabled()
                .accessibilityIdentifier("live-categories")
            }

            openRoomLink
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
                    TextField("搜索直播间", text: $searchQuery,
                              prompt: Text("搜索\(platform)直播间").foregroundStyle(.white.opacity(0.68)))
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
                    HomeRoomResults(provider: provider, listing: .search(term))
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

    private func libraryPage(_ section: HomeSection, rooms: [RoomDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            pageTitle(section.title)
            RoomGrid(rooms: rooms)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func pageTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 42, weight: .bold))
            .accessibilityAddTraits(.isHeader)
    }
}

private enum HomeRoute: Hashable {
    case categories
    case openRoom(String)
    case room(RoomDescriptor)
}

private struct CategoryListView: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [CategoryDescriptor]
    @Binding var selected: CategoryDescriptor?

    var body: some View {
        List {
            Button("全部") { select(nil) }
            ForEach(categories) { category in
                Button(category.name) { select(category) }
            }
        }
        .navigationTitle("直播分类")
    }

    private func select(_ category: CategoryDescriptor?) {
        selected = category
        dismiss()
    }
}

private struct HomeRoomResults: View {
    @EnvironmentObject private var core: NativeCoreClient
    @State private var retry = 0
    let provider: String
    let listing: RoomListing

    var body: some View {
        results.task(id: Request(provider: provider, listing: listing, retry: retry)) {
            await core.loadRooms(provider: provider, listing: listing)
        }
    }

    @ViewBuilder
    private var results: some View {
        if !core.isCurrentRoomListing(provider: provider, listing: listing) {
            ProgressView()
        } else if core.rooms.isEmpty {
            if core.isLoading {
                ProgressView()
            } else if let message = core.errorMessage {
                ContentUnavailableView {
                    Label(message, systemImage: "tv")
                } actions: {
                    Button("重试") { retry += 1 }
                }
            } else {
                ContentUnavailableView(emptyTitle, systemImage: "tv")
            }
        } else {
            RoomGrid(rooms: core.rooms) {
                if let message = core.errorMessage {
                    Text(message).foregroundStyle(.secondary)
                }
                if core.hasMore {
                    Button(core.isLoading ? "加载中" : "加载更多") {
                        Task { await core.loadRooms(provider: provider, listing: listing, append: true) }
                    }
                    .disabled(core.isLoading)
                }
            }
        }
    }

    private var emptyTitle: LocalizedStringKey {
        if case .search = listing { return "未找到相关直播间" }
        return "暂无直播间"
    }

    private struct Request: Hashable {
        let provider: String
        let listing: RoomListing
        let retry: Int
    }
}

private struct OpenRoomView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @State private var input = ""
    @State private var error: String?
    @State private var submission: String?
    let provider: String
    let open: (RoomDescriptor) -> Void

    var body: some View {
        VStack(spacing: 24) {
            TextField("房间号或直播链接", text: $input)
                .autocorrectionDisabled()
                .onSubmit { submission = input }
            Button("进入直播间") { submission = input }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if submission != nil { ProgressView() }
            if let error { Text(error) }
        }
        .navigationTitle("进入直播间")
        .task(id: submission) {
            guard let submission else { return }
            error = nil
            defer { if !Task.isCancelled { self.submission = nil } }
            do {
                let room = try await core.service(provider).resolveRoom(submission)
                try Task.checkCancellation()
                open(room)
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

private struct RoomGrid<Footer: View>: View {
    @EnvironmentObject private var library: LibraryStore
    let rooms: [RoomDescriptor]
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        if rooms.isEmpty {
            ContentUnavailableView("暂无直播间", systemImage: "tray")
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 24)], spacing: 24) {
                    ForEach(rooms) { room in
                        NavigationLink(value: HomeRoute.room(room)) {
                            RoomTile(room: room)
                        }
                        .buttonStyle(HomeButtonStyle())
                        .focusEffectDisabled()
                        .contextMenu {
                            Button(library.isFavorite(room) ? "取消收藏" : "收藏") { library.toggleFavorite(room) }
                        }
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 12)
                footer()
                    .padding(.vertical, 12)
            }
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 22)
                }
            }
            .focusSection()
        }
    }
}

private struct RoomTile: View {
    @Environment(\.isFocused) private var isFocused
    let room: RoomDescriptor

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        VStack(alignment: .leading, spacing: 0) {
            Color.white.opacity(0.06)
                .aspectRatio(16.0 / 9, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        AsyncImage(url: URL(string: room.cover)) { phase in
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

            VStack(alignment: .leading, spacing: 4) {
                Text(room.title)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                Text(room.userName)
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
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
}

private extension RoomGrid where Footer == EmptyView {
    init(rooms: [RoomDescriptor]) {
        self.init(rooms: rooms) { EmptyView() }
    }
}
