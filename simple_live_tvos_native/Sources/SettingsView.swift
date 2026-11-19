import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            NavigationLink("播放设置") { PlaybackSettingsView() }
                .accessibilityIdentifier("settings-playback")
            NavigationLink("弹幕设置") { DanmakuSettingsView() }
            NavigationLink("关注设置") { FavoriteSettingsView() }
            NavigationLink("多屏设置") { MultiRoomSettingsView() }
                .accessibilityIdentifier("settings-multi-room")
            NavigationLink("账号设置") { AccountSettingsView() }
            NavigationLink("关于") { AboutUpdateView() }
        }
        .listStyle(.plain)
    }
}
