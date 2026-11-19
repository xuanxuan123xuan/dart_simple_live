import CoreImage.CIFilterBuiltins
import SwiftUI

struct SyncView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @EnvironmentObject private var library: LibraryStore
    let category: SyncCategory?

    var body: some View {
        List {
            NavigationLink {
                RemoteSyncView(category: category, importer: importer)
            } label: {
                Label("远程同步", systemImage: "network")
            }
            NavigationLink {
                LANSyncView(category: category, importer: importer)
            } label: {
                Label("局域网同步", systemImage: "wifi")
            }
            NavigationLink {
                WebDAVSyncView(category: category, library: library, core: core, importer: importer)
            } label: {
                Label("WebDAV 备份与恢复", systemImage: "externaldrive")
            }
        }
        .navigationTitle(category == .histories ? "导入观看历史" : "数据同步")
    }

    private var importer: SyncImporter {
        SyncImporter(library: library, prepareAccounts: core.prepareSyncAccounts)
    }
}

struct SyncCategoryControls: View {
    let fixed: SyncCategory?
    let allowSettings: Bool
    @Binding var selection: SyncSelection

    static func initial(_ fixed: SyncCategory?, settings: Bool) -> SyncSelection {
        var categories = fixed.map { Set([$0]) } ?? SyncCategory.library
        if fixed == nil, settings { categories.insert(.settings) }
        return SyncSelection(categories: categories, accountSites: SyncProfile.accountSites)
    }

    var body: some View {
        Section("数据类别") {
            if let fixed {
                Label(fixed.title, systemImage: "checkmark")
            } else {
                ForEach(SyncCategory.allCases.filter { allowSettings || $0 != .settings }) { category in
                    Toggle(category.title, isOn: categoryToggle(category))
                }
                if selection.categories.contains(.accounts) {
                    ForEach(Self.sites, id: \.id) { site in
                        Toggle(site.title, isOn: siteToggle(site.id))
                    }
                }
            }
        }
    }

    private func categoryToggle(_ category: SyncCategory) -> Binding<Bool> {
        Binding { selection.categories.contains(category) } set: { enabled in
            if enabled { selection.categories.insert(category) }
            else { selection.categories.remove(category) }
        }
    }

    private func siteToggle(_ site: String) -> Binding<Bool> {
        Binding { selection.accountSites?.contains(site) == true } set: { enabled in
            if enabled { selection.accountSites?.insert(site) }
            else { selection.accountSites?.remove(site) }
        }
    }

    private static let sites = [(id: "bilibili", title: "哔哩哔哩"), (id: "douyu", title: "斗鱼"),
                                (id: "douyin", title: "抖音"), (id: "kuaishou", title: "快手主备账号"),
                                (id: "xiaohongshu", title: "小红书")]
}

struct SyncReviewModifier: ViewModifier {
    @ObservedObject var receiver: SyncReceiver
    @FocusState private var focused: Action?

    private enum Action: Hashable { case cancel, confirm }

    func body(content: Content) -> some View {
        content
            .disabled(receiver.review != nil)
            .accessibilityHidden(receiver.review != nil)
            .overlay {
                if let review = receiver.review {
                    ZStack {
                        Color.black.opacity(0.7).ignoresSafeArea()
                        VStack(spacing: 24) {
                            Text(review.overwrite ? "确认覆盖所选数据？" : "确认导入账号？")
                                .font(.title2.bold())
                                .accessibilityAddTraits(.isHeader)
                            Text(review.summary).foregroundStyle(.secondary)
                            HStack(spacing: 24) {
                                Button("取消") { receiver.answer(false, id: review.id) }
                                    .focused($focused, equals: .cancel)
                                Button(review.overwrite ? "覆盖导入" : "导入",
                                       role: review.overwrite ? .destructive : nil) {
                                    receiver.answer(true, id: review.id)
                                }
                                .focused($focused, equals: .confirm)
                                .accessibilityIdentifier("sync-review-confirm")
                            }
                        }
                        .padding(44)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
                        .focusSection()
                    }
                    .defaultFocus($focused, .cancel)
                    .task(id: review.id) { focused = .cancel }
                    .onExitCommand { receiver.answer(false, id: review.id) }
                }
            }
    }
}

struct SyncQRCode: View {
    let value: String
    let label: String

    var body: some View {
        if let code = makeImage() {
            Image(decorative: code, scale: 1)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 205, height: 205)
                .padding(16)
                .background(.white)
                .accessibilityLabel(label)
        }
    }

    private func makeImage() -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        guard let image = filter.outputImage else { return nil }
        return Self.context.createCGImage(image, from: image.extent)
    }

    private static let context = CIContext()
}

private struct RemoteSyncView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("simple_live_tvos.sync.remote.server") private var server = RemoteSyncSettings.domestic
    @AppStorage("simple_live_tvos.sync.remote.proxy") private var proxy = ""
    @StateObject private var client = RemoteSync()
    @StateObject private var receiver: SyncReceiver
    @State private var selection: SyncSelection
    @State private var run: UUID?
    @State private var validationError: String?
    let category: SyncCategory?

    init(category: SyncCategory?, importer: SyncImporter) {
        self.category = category
        _receiver = StateObject(wrappedValue: SyncReceiver(importer: importer))
        _selection = State(initialValue: SyncCategoryControls.initial(category, settings: false))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            List {
                Section("同步站点") {
                    Button("国内站点") { server = RemoteSyncSettings.domestic }
                    Button("Cloudflare 站点") { server = RemoteSyncSettings.cloudflare }
                    TextField("WebSocket 地址", text: $server).autocorrectionDisabled()
                    TextField("HTTP 代理地址", text: $proxy, prompt: Text("系统代理 / direct / 主机:端口"))
                        .autocorrectionDisabled()
                    Button(run == nil ? "创建同步房间" : "断开连接") {
                        validationError = nil
                        run = run == nil ? UUID() : nil
                    }
                    .accessibilityIdentifier("remote-sync-connect")
                }
                SyncCategoryControls(fixed: category, allowSettings: false, selection: $selection)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 16) {
                Text(validationError ?? (run == nil && client.room == nil && client.status == "准备连接"
                                          ? "连接后显示房间码" : client.status))
                if let code = client.room, let expiresAt = client.expiresAt {
                    Text(code).font(.system(size: 54, weight: .bold, design: .monospaced))
                        .accessibilityIdentifier("remote-sync-room")
                    SyncQRCode(value: code, label: "同步房间二维码")
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = max(0, Int(ceil(expiresAt.timeIntervalSince(context.date))))
                        Text("剩余 \(seconds / 60):\(seconds % 60, specifier: "%02d") · 已连 \(client.peerCount) 台设备")
                            .monospacedDigit()
                    }
                }
                if let result = receiver.result { Text(result).foregroundStyle(.secondary) }
            }
            .frame(width: 440, alignment: .leading)
            .padding(.top, 54)
        }
        .navigationTitle("远程同步")
        .modifier(SyncReviewModifier(receiver: receiver))
        .task(id: run) {
            guard let id = run else { return }
            do {
                let settings = try RemoteSyncSettings(server: server, proxy: proxy)
                await client.run(settings: settings, selection: { selection }, receiver: receiver)
            } catch {
                validationError = error.localizedDescription
            }
            if run == id { run = nil }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { run = nil } }
    }
}

private struct LANSyncView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var client = LANSync()
    @StateObject private var receiver: SyncReceiver
    @State private var selection: SyncSelection
    let category: SyncCategory?

    init(category: SyncCategory?, importer: SyncImporter) {
        self.category = category
        _receiver = StateObject(wrappedValue: SyncReceiver(importer: importer))
        _selection = State(initialValue: SyncCategoryControls.initial(category, settings: true))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            List {
                Button("重新启动接收") { start() }
                SyncCategoryControls(fixed: category, allowSettings: true, selection: $selection)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                Text(client.status)
                if client.ready, !client.addresses.isEmpty {
                    let addresses = client.addresses.map { "\($0):\(LANSync.httpPort)" }
                    SyncQRCode(value: addresses.joined(separator: ";"), label: "局域网同步地址二维码")
                    ForEach(addresses, id: \.self) { Text($0).monospacedDigit() }
                }
                if let progress = client.progress { Text(progress).foregroundStyle(.secondary) }
            }
            .frame(width: 480, alignment: .leading)
            .padding(.top, 54)
        }
        .navigationTitle("局域网同步")
        .modifier(SyncReviewModifier(receiver: receiver))
        .task {
            if scenePhase != .background { start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { client.stop() }
            if phase == .active && !client.ready { start() }
        }
        .onDisappear { client.stop() }
    }

    private func start() {
        client.start(selection: { selection }, receiver: receiver)
    }
}
