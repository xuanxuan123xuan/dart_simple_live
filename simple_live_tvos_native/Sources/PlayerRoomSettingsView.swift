import SwiftUI

struct PlayerRoomSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var engine: PlaybackEngine
    @Binding var danmakuEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Text("房内设置").font(.title.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("关闭") { dismiss() }
            }
            HStack(spacing: 30) {
                Button("降低音量", systemImage: "speaker.minus") { engine.setVolume(engine.volume - 10) }
                    .disabled(engine.volume == 0)
                Text("\(engine.volume)%").monospacedDigit().accessibilityIdentifier("player-volume")
                Button("提高音量", systemImage: "speaker.plus") { engine.setVolume(engine.volume + 10) }
                    .disabled(engine.volume == 100)
                Toggle("静音", isOn: Binding(get: { engine.isMuted }, set: { engine.setMuted($0) }))
            }
            Toggle("显示弹幕", isOn: $danmakuEnabled)
            Spacer()
        }
        .padding(40)
    }
}
