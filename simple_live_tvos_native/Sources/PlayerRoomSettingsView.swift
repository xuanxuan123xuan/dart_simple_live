import SwiftUI

struct PlayerRoomSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    let room: RoomDescriptor
    @ObservedObject var engine: PlaybackEngine
    @Binding var danmakuEnabled: Bool
    @Binding var sleepDeadline: Date?
    @AppStorage(PlaybackPreferences.autoQuality) private var autoQuality = true

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
            HStack(spacing: 40) {
                Toggle("显示弹幕", isOn: $danmakuEnabled)
                Toggle("网络波动时自动降低清晰度", isOn: $autoQuality)
            }
            Button(library.hasRotationRoom(room) ? "从轮播移除本房间" : "加入轮播列表",
                   systemImage: "list.bullet.rectangle") { library.toggleRotationRoom(room) }
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
