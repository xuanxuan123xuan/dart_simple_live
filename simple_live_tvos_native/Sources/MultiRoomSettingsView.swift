import SwiftUI

struct MultiRoomSettingsView: View {
    @AppStorage(MultiRoomPreferences.layoutKey) private var layout = MultiRoomLayout.grid
    @AppStorage(MultiRoomPreferences.spacingKey) private var spacing = MultiRoomSpacing.normal
    @AppStorage(MultiRoomPreferences.audioKey) private var audio = MultiRoomAudioMode.single
    @AppStorage(MultiRoomPreferences.danmakuKey) private var danmaku = MultiRoomDanmaku.inherited

    var body: some View {
        List {
            Section {
                SettingsPicker("默认布局", selection: $layout, options: MultiRoomLayout.allCases) {
                    Text($0.title)
                }
                SettingsPicker("画面间距", selection: $spacing, options: MultiRoomSpacing.allCases) {
                    Text($0.title)
                }
                SettingsPicker("默认声音", selection: $audio, options: MultiRoomAudioMode.allCases) {
                    Text($0.title)
                }
                SettingsPicker("默认弹幕", selection: $danmaku, options: MultiRoomDanmaku.allCases) {
                    Text($0.title)
                }
            } header: {
                Text("新建多屏")
            } footer: {
                Text("这些选项在新开多屏时生效。「单路有声」默认使用第一个房间的声音。从单屏转入时，原房间保留当前的弹幕和音量。")
            }
        }
        .navigationTitle("多屏设置")
    }
}
