import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @FocusState private var focusedSlot: AccountSlot?

    var body: some View {
        List {
            ForEach(core.accountSlots) { slot in
                NavigationLink {
                    AccountDetailsView(slot: slot)
                } label: {
                    HStack {
                        Text(slot.title)
                        Spacer()
                        Text(core.accountStatus(slot).title)
                            .foregroundStyle(.secondary)
                    }
                }
                .focused($focusedSlot, equals: slot)
                .accessibilityIdentifier("account.\(slot.rawValue)")
            }
        }
        .listStyle(.plain)
        .defaultFocus($focusedSlot, core.accountSlots.first)
        .navigationTitle("账号")
    }
}

private struct AccountDetailsView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @State private var error: String?
    @State private var retry = 0
    @State private var confirmSignOut = false
    let slot: AccountSlot

    private var status: AccountStatus { core.accountStatus(slot) }
    private var removeTitle: String { status == .verified ? "退出登录" : "清除 Cookie" }

    var body: some View {
        List {
            Section("账号状态") {
                Text(status.title)
                if status == .configured { Text("平台登录状态待确认").foregroundStyle(.secondary) }
            }
            if let provider = core.loginProviders.first(where: { $0.id == slot.rawValue }) {
                NavigationLink("扫码登录") { ProviderLoginView(provider: provider) }
            }
            if slot != .bilibili {
                NavigationLink(status == .signedOut ? "录入 Cookie" : "替换 Cookie") {
                    AccountCookieEditor(slot: slot)
                }
            }
            if status == .unavailable {
                Button("重新校验") { retry += 1 }
            }
            if status != .signedOut {
                Button(removeTitle, role: .destructive) { confirmSignOut = true }
                    .accessibilityIdentifier("account.remove")
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .listStyle(.plain)
        .navigationTitle(slot.title)
        .confirmationDialog("确定要\(removeTitle)？", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(removeTitle, role: .destructive) {
                do {
                    try core.signOut(slot)
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
            Button("取消", role: .cancel) {}
        }
        .task(id: retry) {
            if retry > 0 { await core.restoreAccount(slot) }
        }
    }
}

private struct AccountCookieEditor: View {
    @EnvironmentObject private var core: NativeCoreClient
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var kww = ""
    @State private var saving = false
    @State private var error: String?
    let slot: AccountSlot

    var body: some View {
        List {
            SecureField(slot == .douyin ? "Cookie 或 ttwid" : "Cookie", text: $input)
                .disabled(saving)
                .accessibilityIdentifier("account.cookie.input")
            if slot.isKuaishou {
                SecureField("Kww（可选）", text: $kww)
                    .disabled(saving)
            }
            Button(saving ? "正在校验" : "保存 Cookie") {
                error = nil
                saving = true
            }
            .disabled(saving || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("account.cookie.save")
            if let error { Text(error).foregroundStyle(.red) }
        }
        .listStyle(.plain)
        .navigationTitle("\(slot.title) Cookie")
        .task(id: saving) {
            guard saving else { return }
            defer { saving = false }
            do {
                let signature = kww.trimmingCharacters(in: .whitespaces)
                let credential = AccountCredential(cookie: input, kww: signature.isEmpty ? nil : signature)
                try await core.saveAccount(credential, for: slot)
                input = ""
                kww = ""
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private extension AccountSlot {
    var title: String {
        switch self {
        case .bilibili: "哔哩哔哩"
        case .douyu: "斗鱼"
        case .douyin: "抖音"
        case .kuaishou: "快手主账号"
        case .kuaishouSecondary: "快手备用账号"
        case .xiaohongshu: "小红书"
        }
    }
}

private extension AccountStatus {
    var title: String {
        switch self {
        case .signedOut: "未配置"
        case .checking: "正在校验"
        case .verified: "已登录"
        case .configured: "已配置"
        case .invalid: "凭据无效或已过期"
        case .unavailable: "暂时无法校验"
        }
    }
}
