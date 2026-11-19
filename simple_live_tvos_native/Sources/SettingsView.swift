import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var core: NativeCoreClient
    @State private var error: String?

    var body: some View {
        List {
            NavigationLink("弹幕设置") { DanmakuSettingsView() }
            NavigationLink("关注设置") { FavoriteSettingsView() }
            NavigationLink("频道轮播") { ChannelRotationSettingsView() }
            ForEach(core.loginProviders) { provider in
                Section(provider.title) {
                    if core.authenticated.contains(provider.id) {
                        Text("已登录")
                        Button("退出登录") {
                            Task {
                                do { try await core.signOut(provider: provider.id); error = nil }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                    } else {
                        NavigationLink("扫码登录") { ProviderLoginView(provider: provider) }
                    }
                }
            }
            if let error { Text(error) }
        }
        .listStyle(.plain)
    }
}
