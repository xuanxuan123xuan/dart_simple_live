import SwiftUI

struct WebDAVSyncView: View {
    private enum Action: Equatable { case connect, upload, download }
    private struct Job: Equatable {
        let id = UUID()
        let action: Action
    }

    let category: SyncCategory?
    let library: LibraryStore
    let core: NativeCoreClient
    private let credentialStore = WebDAVCredentialStore()
    @StateObject private var receiver: SyncReceiver
    @State private var credentials = WebDAVCredentials()
    @State private var saved: WebDAVCredentials?
    @State private var loaded = false
    @State private var selection: SyncSelection
    @State private var job: Job?
    @State private var progress: String?
    @State private var result: String?
    @State private var confirmUpload = false
    @AppStorage("simple_live_tvos.sync.webdav.lastUpload") private var lastUpload = 0.0
    @AppStorage("simple_live_tvos.sync.webdav.lastRestore") private var lastRestore = 0.0

    init(category: SyncCategory?, library: LibraryStore, core: NativeCoreClient, importer: SyncImporter) {
        self.category = category
        self.library = library
        self.core = core
        _receiver = StateObject(wrappedValue: SyncReceiver(importer: importer))
        _selection = State(initialValue: SyncCategoryControls.initial(category, settings: true))
    }

    var body: some View {
        List {
            Section("连接") {
                TextField("WebDAV 地址", text: $credentials.address).autocorrectionDisabled()
                TextField("用户名", text: $credentials.user).autocorrectionDisabled()
                SecureField("密码", text: $credentials.password)
                Button("验证并保存连接") { job = Job(action: .connect) }
                if saved != nil { Button("移除保存的连接", role: .destructive, action: clear) }
            }
            .disabled(job != nil)
            SyncCategoryControls(fixed: category, allowSettings: true, selection: $selection)
                .disabled(job != nil)
            Section {
                if category == nil {
                    Button("上传备份") { confirmUpload = true }
                }
                Button("下载并恢复") { job = Job(action: .download) }
                    .accessibilityIdentifier("webdav-sync-restore")
            }
            .disabled(job != nil || saved == nil || credentials != saved || selection.categories.isEmpty)
            if let progress {
                ProgressView(progress)
            }
            if let result { Text(result).accessibilityIdentifier("webdav-sync-result") }
            if lastUpload > 0 { timestamp("上次上传", seconds: lastUpload) }
            if lastRestore > 0 { timestamp("上次恢复", seconds: lastRestore) }
        }
        .navigationTitle("WebDAV 备份与恢复")
        .modifier(SyncReviewModifier(receiver: receiver))
        .confirmationDialog("上传并替换云端备份？", isPresented: $confirmUpload, titleVisibility: .visible) {
            Button("上传备份", role: .destructive) { job = Job(action: .upload) }
            Button("取消", role: .cancel) {}
        }
        .task {
            guard !loaded else { return }
            loaded = true
            do {
                saved = try credentialStore.read()
                if let saved { credentials = saved }
            } catch { result = error.localizedDescription }
        }
        .task(id: job) {
            guard let job else { return }
            await perform(job)
        }
    }

    private func timestamp(_ title: String, seconds: Double) -> some View {
        LabeledContent(title, value: Date(timeIntervalSince1970: seconds).formatted(date: .abbreviated, time: .shortened))
    }

    private func clear() {
        do {
            try credentialStore.clear()
            credentials = WebDAVCredentials()
            saved = nil
            lastUpload = 0
            lastRestore = 0
            result = "已移除 WebDAV 连接"
        } catch { result = error.localizedDescription }
    }

    private func perform(_ operation: Job) async {
        result = nil
        defer {
            if job == operation {
                progress = nil
                job = nil
            }
        }
        do {
            let client = try WebDAVSync(credentials: credentials)
            switch operation.action {
            case .connect:
                progress = "验证连接"
                try await client.verify()
                try Task.checkCancellation()
                try credentialStore.save(credentials)
                if credentials != saved {
                    lastUpload = 0
                    lastRestore = 0
                }
                saved = credentials
                result = "连接已验证并保存"
            case .upload:
                progress = "打包备份"
                var plan = library.syncBackup(selection: selection)
                if selection.categories.contains(.accounts) {
                    let sites = selection.accountSites ?? SyncProfile.accountSites
                    plan.accounts = try core.exportSyncAccounts().filter {
                        sites.contains($0.slot == "kuaishou.secondary" ? "kuaishou" : $0.slot)
                    }
                }
                guard plan.hasData else { throw SyncError.noSelection }
                let archive = try SyncArchive.encode(plan)
                try Task.checkCancellation()
                progress = "上传备份"
                try await client.upload(archive)
                lastUpload = Date().timeIntervalSince1970
                result = "上传成功"
            case .download:
                progress = "下载备份"
                let archive = try await client.download()
                try Task.checkCancellation()
                progress = "校验备份"
                let profile = try SyncArchive.decode(archive, selection: selection)
                progress = "处理导入"
                let summary = try await receiver.receive(profile, selection: selection, overwrite: true)
                lastRestore = Date().timeIntervalSince1970
                result = "恢复完成 · \(summary)"
            }
        } catch {
            if !Task.isCancelled { result = error.localizedDescription }
        }
    }
}
