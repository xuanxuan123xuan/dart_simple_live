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
    @State private var queue: ChannelQueue
    @State private var sleepDeadline: Date?

    init(room: RoomDescriptor, rooms: [RoomDescriptor]) {
        _room = State(initialValue: room)
        _queue = State(initialValue: ChannelQueue(rooms: rooms, current: room))
    }

    var body: some View {
        PlayerView(room: room, queue: queue, sleepDeadline: $sleepDeadline) { next in
            if !queue.rooms.contains(where: { $0.key == next.key }) {
                queue = ChannelQueue(rooms: queue.rooms + [next], current: next)
            }
            room = next
        }
        .id(room.key)
    }
}

struct PlayerChannelList: View {
    @Environment(\.dismiss) private var dismiss
    let current: RoomDescriptor
    let rooms: [RoomDescriptor]
    let title: String
    let queue: ChannelQueue?
    let select: (RoomDescriptor) -> Void

    init(current: RoomDescriptor, queue: ChannelQueue, select: @escaping (RoomDescriptor) -> Void) {
        self.current = current
        self.queue = queue
        rooms = queue.rooms
        title = "切换频道"
        self.select = select
    }

    init(current: RoomDescriptor, rooms: [RoomDescriptor], title: String, select: @escaping (RoomDescriptor) -> Void) {
        self.current = current
        self.rooms = rooms
        self.title = title
        queue = nil
        self.select = select
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Text(title).font(.title.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("关闭") { dismiss() }
            }
            if let queue {
                HStack(spacing: 32) {
                    Button("上一台") { choose(queue.adjacent(to: current, offset: -1)) }
                        .disabled(queue.rooms.count < 2)
                    Button("下一台") { choose(queue.adjacent(to: current, offset: 1)) }
                        .disabled(queue.rooms.count < 2)
                }
            }
            if rooms.isEmpty {
                ContentUnavailableView("暂无收藏", systemImage: "star")
            }
            List(rooms) { room in
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
