import SwiftUI

struct PlayerRoomSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var engine: PlaybackEngine
    @Binding var danmakuEnabled: Bool
    @Binding var sleepDeadline: Date?

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
            Text("定时关闭").font(.headline)
            HStack(spacing: 22) {
                ForEach([15, 30, 60, 90, 120], id: \.self) { minutes in
                    Button("\(minutes) 分钟") { sleepDeadline = .now.addingTimeInterval(Double(minutes) * 60) }
                }
                Button("取消定时") { sleepDeadline = nil }
                    .disabled(sleepDeadline == nil)
            }
            if let sleepDeadline {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("剩余 \(SleepTimerDisplay.remaining(until: sleepDeadline, now: context.date))")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(40)
    }
}
