import SwiftUI

struct ChannelQueue {
    let rooms: [RoomDescriptor]

    init(rooms: [RoomDescriptor], current: RoomDescriptor) {
        var seen = Set<String>()
        let unique = rooms.filter { seen.insert($0.key).inserted }
        self.rooms = seen.contains(current.key) ? unique : [current] + unique
    }

    func adjacent(to current: RoomDescriptor, offset: Int) -> RoomDescriptor? {
        guard rooms.count > 1, let index = rooms.firstIndex(where: { $0.key == current.key }) else { return nil }
        let next = (index + offset % rooms.count + rooms.count) % rooms.count
        return next == index ? nil : rooms[next]
    }
}

/// Recreate playback and danmaku state when changing the active room; the navigation stack stays put.
struct ChannelPlayerView: View {
    @State private var room: RoomDescriptor
    let queue: ChannelQueue

    init(room: RoomDescriptor, rooms: [RoomDescriptor]) {
        _room = State(initialValue: room)
        queue = ChannelQueue(rooms: rooms, current: room)
    }

    var body: some View {
        PlayerView(room: room, queue: queue) { next in room = next }
            .id(room.key)
    }
}

struct PlayerChannelList: View {
    @Environment(\.dismiss) private var dismiss
    let current: RoomDescriptor
    let queue: ChannelQueue
    let select: (RoomDescriptor) -> Void

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Text("切换频道").font(.title.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("关闭") { dismiss() }
            }
            HStack(spacing: 32) {
                Button("上一台") { choose(queue.adjacent(to: current, offset: -1)) }
                    .disabled(queue.rooms.count < 2)
                Button("下一台") { choose(queue.adjacent(to: current, offset: 1)) }
                    .disabled(queue.rooms.count < 2)
            }
            List(queue.rooms) { room in
                Button { choose(room) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(room.title).lineLimit(1)
                        Text(room.key == current.key ? "正在观看" : room.userName)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityAddTraits(room.key == current.key ? .isSelected : [])
            }
        }
        .padding(32)
    }

    private func choose(_ room: RoomDescriptor?) {
        guard let room else { return }
        dismiss()
        if room.key != current.key { select(room) }
    }
}
