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

extension Array where Element: Comparable {
    // Synced preferences can fall between the presets offered on tvOS.
    func includingSelection(_ selection: Element) -> Self {
        contains(selection) ? self : (self + [selection]).sorted()
    }
}
