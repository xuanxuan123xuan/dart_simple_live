import SwiftUI
import WebKit

struct HomeView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @StateObject private var library = LibraryStore()
    @State private var selectedProvider = "bilibili"
    @State private var searchText = ""
    @State private var section = HomeSection.recommend
    @State private var selectedCategory: CategoryDescriptor?

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("浏览") {
                    Label("推荐", systemImage: "sparkles")
                        .tag(HomeSection.recommend)
                    Label("搜索", systemImage: "magnifyingglass")
                        .tag(HomeSection.search)
                }
                Section("资料库") {
                    Label("收藏", systemImage: "star")
                        .tag(HomeSection.favorites)
                    Label("历史", systemImage: "clock")
                        .tag(HomeSection.recent)
                }
                Section("平台") {
                    ForEach(core.providers) { provider in
                        Text(provider.title)
                            .tag(HomeSection.provider(provider.id))
                    }
                }
                Section {
                    Label("设置", systemImage: "gearshape")
                        .tag(HomeSection.settings)
                }
            }
            .navigationTitle("Simple Live")
        } detail: {
            detailView
        }
        .environmentObject(library)
        .searchable(text: $searchText, prompt: "搜索直播间")
        .onChange(of: section) { _, value in
            if case let .provider(provider) = value {
                selectedProvider = provider
                selectedCategory = nil
            }
        }
        .task(id: selectedProvider) {
            selectedCategory = nil
            await core.loadCategories(provider: selectedProvider)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch section {
        case .recommend, .provider:
            ProviderRoomsView(
                provider: selectedProvider,
                searchText: searchText,
                selectedCategory: $selectedCategory
            )
        case .search:
            ProviderRoomsView(
                provider: selectedProvider,
                searchText: searchText,
                selectedCategory: $selectedCategory
            )
        case .favorites:
            LibraryGridView(title: "收藏", rooms: library.favorites)
        case .recent:
            LibraryGridView(title: "历史", rooms: library.recent)
        case .settings:
            SettingsView()
        }
    }
}

private enum HomeSection: Hashable {
    case recommend
    case search
    case favorites
    case recent
    case provider(String)
    case settings
}

private struct ProviderRoomsView: View {
    @EnvironmentObject private var core: NativeCoreClient
    let provider: String
    let searchText: String
    @Binding var selectedCategory: CategoryDescriptor?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !core.categories.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        Button("全部") { selectedCategory = nil }
                            .buttonStyle(.borderedProminent)
                        ForEach(core.categories) { category in
                            Button(category.name) { selectedCategory = category }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            RoomGridView(
                provider: provider,
                searchText: searchText,
                category: selectedCategory
            )
        }
    }
}

private struct RoomGridView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @EnvironmentObject private var library: LibraryStore
    let provider: String
    let searchText: String
    let category: CategoryDescriptor?

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 24)]

    var body: some View {
        Group {
            if core.isLoading {
                ProgressView()
            } else if core.rooms.isEmpty {
                ContentUnavailableView("暂无直播间", systemImage: "tv")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(core.rooms) { room in
                            NavigationLink {
                                PlayerView(provider: provider, room: room)
                                    .environmentObject(core)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    AsyncImage(url: URL(string: room.cover)) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.gray.opacity(0.25)
                                    }
                                    .frame(height: 160)
                                    .clipped()
                                    Text(room.title).lineLimit(1)
                                    Text(room.userName)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.card)
                            .contextMenu {
                                Button(library.isFavorite(room) ? "取消收藏" : "收藏") {
                                    library.toggleFavorite(room)
                                }
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                library.visit(room)
                            })
                        }
                    }
                }
            }
        }
        .navigationTitle(searchText.isEmpty ? "推荐" : "搜索")
        .task(id: "\(provider)|\(category?.id ?? "recommend")|\(searchText)") {
            if !searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(350))
                await core.search(provider: provider, keyword: searchText)
            } else if let category {
                await core.loadCategory(
                    provider: provider,
                    categoryId: category.id,
                    categoryName: category.name,
                    parentId: category.parentId
                )
            } else {
                await core.loadRecommend(provider: provider)
            }
        }
    }
}

private struct LibraryGridView: View {
    @EnvironmentObject private var core: NativeCoreClient
    let title: String
    let rooms: [RoomDescriptor]

    var body: some View {
        ScrollView {
            if rooms.isEmpty {
                ContentUnavailableView(title == "历史" ? "暂无历史" : "暂无收藏", systemImage: "tray")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 24)], spacing: 24) {
                    ForEach(rooms) { room in
                        NavigationLink {
                            PlayerView(provider: room.provider, room: room)
                                .environmentObject(core)
                        } label: {
                            Text(room.title)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                                .padding(20)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.card)
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @State private var danmakuEnabled = true
    @State private var showingLogin = false
    @State private var loginMessage: String?

    var body: some View {
        Form {
            Toggle("显示直播弹幕", isOn: $danmakuEnabled)
            Text("弹幕仅用于观看，当前版本不提供发送功能。")
                .foregroundStyle(.secondary)
            Text("账号会话通过 tvOS Keychain 保存。")
                .foregroundStyle(.secondary)
            Button("小红书网页登录") {
                core.prepareXiaohongshuLogin()
                showingLogin = true
            }
            if let loginMessage {
                Text(loginMessage)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .sheet(isPresented: $showingLogin, onDismiss: core.closeWebLogin) {
            if let webView = core.loginWebView {
                WebLoginContainer(webView: webView)
                    .task {
                        do {
                            try await core.loginXiaohongshu()
                            loginMessage = "小红书会话已保存"
                            showingLogin = false
                        } catch {
                            loginMessage = error.localizedDescription
                        }
                    }
            } else {
                ProgressView()
            }
        }
    }
}

private struct WebLoginContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}
