import SwiftUI

struct MultiRoomPickerView: View {
    enum Source: String, CaseIterable {
        case favorites = "关注", history = "历史", search = "搜索", link = "房间号／链接"
    }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var core: NativeCoreClient
    @EnvironmentObject private var favoriteStatus: FavoriteStatusStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var results = RoomResultsStore()
    @State private var selection: MultiRoomSelection
    @State private var source: Source
    @State private var searchProvider = "bilibili"
    @State private var linkProvider = "bilibili"
    @State private var search = ""
    @State private var link = ""
    @State private var linkAttempt: LinkAttempt?
    @State private var retry = 0
    @State private var pagination: PageRequest?
    @FocusState private var focusedSource: Source?
    @State private var message: String?
    let confirmTitle: String
    let onConfirm: ([RoomDescriptor]) -> Void

    init(rooms: [RoomDescriptor] = [], source: Source = .favorites, confirmTitle: String = "开始多屏",
         onConfirm: @escaping ([RoomDescriptor]) -> Void) {
        _selection = State(initialValue: MultiRoomSelection(rooms))
        _source = State(initialValue: source)
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
    }

    var body: some View {
        let page = pagination.flatMap { $0.query == query ? $0 : nil }
        let resolution = source == .link ? linkAttempt : nil
        VStack(spacing: 20) {
            HStack(spacing: 22) {
                Text("多屏选房").font(.title.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(selection.rooms.count) / \(MultiRoomSelection.maximum) 路").monospacedDigit()
                    .accessibilityIdentifier("multi-room-selection-count")
            }
            HStack(spacing: 18) {
                ForEach(Source.allCases, id: \.self) { item in
                    Button {
                        guard source != item else { return }
                        source = item
                        message = nil
                        pagination = nil
                        linkAttempt = nil
                    } label: {
                        HomePill(selected: source == item, quiet: false) { Text(item.rawValue) }
                    }
                    .buttonStyle(HomeButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedSource, equals: item)
                    .accessibilityAddTraits(source == item ? .isSelected : [])
                }
                Spacer()
                Button("取消") { dismiss() }
                Button(confirmTitle) { onConfirm(selection.rooms) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!selection.canStart)
                    .accessibilityIdentifier("multi-room-start")
            }
            .focusSection()
            HStack(alignment: .top, spacing: 28) {
                sourceContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                List {
                    Section("已选房间") {
                        if selection.rooms.isEmpty {
                            Text("请选择 2–4 个直播间").foregroundStyle(.secondary)
                        }
                        ForEach(selection.rooms) { room in
                            Button { selection.toggle(room) } label: {
                                Label(room.title, systemImage: "minus.circle").lineLimit(1)
                            }
                            .accessibilityIdentifier("multi-room-chosen-\(room.key)")
                        }
                    }
                }
                .frame(width: 500)
                .focusSection()
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(30)
        .frame(minWidth: 1180, minHeight: 720)
        .defaultFocus($focusedSource, source)
        .task(id: query) {
            guard let query else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await load(query)
        }
        .task(id: page) {
            guard let page else { return }
            await load(page.query, next: true)
            if pagination == page { pagination = nil }
        }
        .task(id: resolution) {
            guard let request = resolution else { return }
            do {
                let room = try await core.resolveRoomInput(request.input, provider: request.provider)
                try Task.checkCancellation()
                guard source == .link, request == linkAttempt else { return }
                if selection.contains(room) { message = "此房间已选" }
                else if selection.add(room) { link = ""; message = "已加入：\(room.title)" }
                else { message = "最多可选 4 路" }
            } catch {
                if !Task.isCancelled, request == linkAttempt { message = error.localizedDescription }
            }
            if request == linkAttempt { linkAttempt = nil }
        }
    }

    @ViewBuilder
    private var sourceContent: some View {
        switch source {
        case .favorites: roomList(library.favorites, empty: "没有关注的直播间", sortByPresence: true)
        case .history: roomList(library.recent, empty: "没有观看历史")
        case .search:
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    platformPicker(selection: $searchProvider, supportsSearch: true)
                    TextField("搜索直播", text: $search).autocorrectionDisabled()
                        .accessibilityIdentifier("multi-room-search")
                }
                if let query {
                    if results.query != query || results.status == .idle || (results.rooms.isEmpty && results.status == .loading && !results.hasMore) {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if case let .failed(detail) = results.status, results.rooms.isEmpty, !results.hasMore {
                        ContentUnavailableView {
                            Label("搜索失败", systemImage: "exclamationmark.circle")
                        } description: { Text(detail) } actions: { Button("重试") { retry += 1 } }
                    } else {
                        roomList(results.rooms, empty: "没有搜索结果")
                        if results.hasMore {
                            switch results.status {
                            case let .failed(detail):
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                                Button("重试加载更多") { pagination = PageRequest(query: query) }
                            case .loading:
                                ProgressView("正在加载更多")
                            case .idle, .loaded:
                                Button("加载更多") { pagination = PageRequest(query: query) }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("输入关键词搜索直播", systemImage: "magnifyingglass")
                }
            }
        case .link:
            VStack(alignment: .leading, spacing: 20) {
                Text("分享链接会自动识别平台。输入房间号时，请先选择所属平台。")
                    .foregroundStyle(.secondary)
                platformPicker(selection: $linkProvider)
                    .disabled(linkAttempt != nil)
                TextField("粘贴分享文本或输入房间号", text: $link).autocorrectionDisabled()
                    .disabled(linkAttempt != nil)
                    .onSubmit(submitLink)
                    .accessibilityIdentifier("multi-room-link")
                Button(linkAttempt == nil ? "解析并加入" : "正在解析", action: submitLink)
                    .disabled(linkAttempt != nil || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
        }
    }

    private var query: RoomResultsStore.Query? {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source == .search, !term.isEmpty else { return nil }
        return .init(provider: searchProvider, listing: .search(term), retry: retry)
    }

    private func load(_ query: RoomResultsStore.Query, next: Bool = false) async {
        await results.load(query, next: next) { page in
            try await core.service(query.provider).rooms(in: query.listing, page: page)
        }
    }

    private func submitLink() {
        let input = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, linkAttempt == nil else { return }
        message = nil
        linkAttempt = LinkAttempt(input: input, provider: linkProvider)
    }

    private func platformPicker(selection: Binding<String>, supportsSearch: Bool = false) -> some View {
        Picker("平台", selection: selection) {
            ForEach(core.providers.filter { !supportsSearch || $0.id != "xiaohongshu" }) {
                Text($0.title).tag($0.id)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func roomList(_ rooms: [RoomDescriptor], empty: String, sortByPresence: Bool = false) -> some View {
        let ordered = sortByPresence
            ? rooms.filter { presence($0) == .live } + rooms.filter { presence($0) != .live }
            : rooms
        if rooms.isEmpty {
            ContentUnavailableView(empty, systemImage: "rectangle.slash")
        } else {
            List(ordered) { room in
                let included = selection.contains(room)
                Button {
                    message = selection.toggle(room) ? nil : "最多可选 4 路"
                } label: {
                    HStack {
                        Image(systemName: included ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(room.title).lineLimit(1)
                            if !room.userName.isEmpty { Text(room.userName).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        let platform = core.providers.first(where: { $0.id == room.provider })?.title ?? room.provider
                        Text("\(platform) · \(presence(room).title)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityAddTraits(included ? .isSelected : [])
                .accessibilityIdentifier("multi-room-source-\(room.key)")
            }
            .focusSection()
        }
    }

    private func presence(_ room: RoomDescriptor) -> FavoritePresence {
        favoriteStatus.snapshots[room.key]?.presence ?? FavoritePresence(room.isLive)
    }

    private struct PageRequest: Equatable {
        let query: RoomResultsStore.Query
        let id = UUID()
    }

    private struct LinkAttempt: Equatable {
        let id = UUID()
        let input: String
        let provider: String
    }
}
