import SwiftUI

struct MultiRoomSettingsView: View {
    @AppStorage(MultiRoomPreferences.layoutKey) private var layout = MultiRoomLayout.grid
    @AppStorage(MultiRoomPreferences.spacingKey) private var spacing = MultiRoomSpacing.normal
    @AppStorage(MultiRoomPreferences.audioKey) private var audio = MultiRoomAudioMode.single
    @AppStorage(MultiRoomPreferences.danmakuKey) private var danmaku = MultiRoomDanmaku.inherited

    var body: some View {
        List {
            Section {
                Picker("默认布局", selection: $layout) {
                    ForEach(MultiRoomLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("画面间距", selection: $spacing) {
                    ForEach(MultiRoomSpacing.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("默认声音", selection: $audio) {
                    ForEach(MultiRoomAudioMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("默认弹幕", selection: $danmaku) {
                    ForEach(MultiRoomDanmaku.allCases, id: \.self) { Text($0.title).tag($0) }
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
