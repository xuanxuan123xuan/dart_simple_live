import SwiftUI

struct XiaohongshuPhoneView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var code = ""
    @State private var connecting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("在手机的 Simple Live 打开「局域网数据同步」→「小红书直播发现」，保持该页面打开。")
                .foregroundStyle(.secondary)
            TextField("手机地址", text: $address, prompt: Text("例如 192.168.1.20:23234"))
                .autocorrectionDisabled()
                .disabled(connecting)
                .accessibilityIdentifier("xiaohongshu-phone-address")
            SecureField("六位连接码", text: $code)
                .disabled(connecting)
                .accessibilityIdentifier("xiaohongshu-phone-code")
            HStack(spacing: 24) {
                Button(connecting ? "正在连接" : "连接", action: connect)
                    .disabled(connecting || address.isEmpty || code.isEmpty)
                if core.xiaohongshuPhone != nil {
                    Button("断开连接") {
                        core.disconnectXiaohongshuPhone()
                        dismiss()
                    }
                    .disabled(connecting)
                }
                if connecting { ProgressView() }
            }
            if let error { Text(error).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: 980)
        .navigationTitle("小红书手机连接")
        .onAppear {
            if address.isEmpty { address = core.xiaohongshuPhone?.address ?? "" }
        }
        .task(id: connecting) {
            guard connecting else { return }
            defer { if !Task.isCancelled { connecting = false } }
            do {
                try await core.connectXiaohongshuPhone(address: address, code: code)
                code = ""
                dismiss()
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    private func connect() {
        guard !connecting else { return }
        error = nil
        connecting = true
    }
}
