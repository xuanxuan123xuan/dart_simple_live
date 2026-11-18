import SwiftUI

enum ChannelRotationPreferences {
    static let onLiveEnd = "simple_live_tvos.rotation.onLiveEnd"
    static let onFailure = "simple_live_tvos.rotation.onFailure"
    static let playlistOnly = "simple_live_tvos.rotation.playlistOnly"
    static let random = "simple_live_tvos.rotation.random"
}

struct ChannelRotation {
    private var attempted: Set<String> = []

    mutating func candidates(after room: RoomDescriptor, in source: [RoomDescriptor], random: Bool) -> [RoomDescriptor] {
        markAttempted(room)
        let offset = source.firstIndex { $0.key == room.key }.map { $0 + 1 } ?? 0
        let ordered = Array(source.dropFirst(offset)) + source.prefix(offset)
        var seen = attempted
        let eligible = ordered.filter { seen.insert($0.key).inserted }
        return random ? eligible.shuffled() : eligible
    }

    func hasAttempted(_ room: RoomDescriptor) -> Bool { attempted.contains(room.key) }
    mutating func markAttempted(_ room: RoomDescriptor) { attempted.insert(room.key) }
    mutating func reset() { attempted.removeAll() }
}

struct ChannelRotationSettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @AppStorage(ChannelRotationPreferences.onLiveEnd) private var onLiveEnd = false
    @AppStorage(ChannelRotationPreferences.onFailure) private var onFailure = false
    @AppStorage(ChannelRotationPreferences.playlistOnly) private var playlistOnly = false
    @AppStorage(ChannelRotationPreferences.random) private var random = false

    var body: some View {
        List {
            Section("自动换台") {
                Toggle("直播结束时换台", isOn: $onLiveEnd)
                Toggle("播放失败时换台", isOn: $onFailure)
                Toggle("使用轮播列表", isOn: $playlistOnly)
                Toggle("轮播随机换台", isOn: $random).disabled(!playlistOnly)
            }
            Section("轮播列表") {
                if library.rotationRooms.isEmpty { Text("可从下方关注或房内设置添加主播").foregroundStyle(.secondary) }
                ForEach(Array(library.rotationRooms.enumerated()), id: \.element.key) { index, room in
                    HStack(spacing: 20) {
                        Text("\(index + 1). \(room.title)").lineLimit(1)
                        Spacer()
                        Button("上移", systemImage: "arrow.up") { library.moveRotationRoom(room, by: -1) }
                            .disabled(index == 0)
                        Button("下移", systemImage: "arrow.down") { library.moveRotationRoom(room, by: 1) }
                            .disabled(index + 1 == library.rotationRooms.count)
                        Button("移除", systemImage: "minus.circle") { library.toggleRotationRoom(room) }
                    }
                    .buttonStyle(.bordered)
                    .focusSection()
                }
            }
            Section("从关注加入") {
                let available = library.favorites.filter { !library.hasRotationRoom($0) }
                if available.isEmpty { Text("暂无可加入的关注").foregroundStyle(.secondary) }
                ForEach(available) { room in
                    Button(room.title, systemImage: "plus") { library.toggleRotationRoom(room) }
                }
            }
        }
        .navigationTitle("频道轮播")
    }
}
