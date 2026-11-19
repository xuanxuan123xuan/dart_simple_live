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
    @EnvironmentObject private var core: NativeCoreClient
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ChannelRotationPreferences.onLiveEnd) private var onLiveEnd = false
    @AppStorage(ChannelRotationPreferences.onFailure) private var onFailure = false
    @AppStorage(ChannelRotationPreferences.playlistOnly) private var playlistOnly = false
    @AppStorage(ChannelRotationPreferences.random) private var random = false
    @State private var room: RoomDescriptor
    @State private var queue: ChannelQueue
    @State private var handoff: RoomPlaybackHandoff?
    @State private var sleepDeadline: Date?
    @State private var rotation = ChannelRotation()
    @State private var pendingSwitch: UUID?

    let openMultiRoom: ([RoomDescriptor], RoomPlaybackHandoff) -> Void

    init(room: RoomDescriptor, rooms: [RoomDescriptor], restoring handoff: RoomPlaybackHandoff? = nil,
         openMultiRoom: @escaping ([RoomDescriptor], RoomPlaybackHandoff) -> Void) {
        _room = State(initialValue: room)
        _queue = State(initialValue: ChannelQueue(rooms: rooms, current: room))
        _handoff = State(initialValue: handoff)
        self.openMultiRoom = openMultiRoom
    }

    var body: some View {
        PlayerView(room: room, queue: queue, sleepDeadline: $sleepDeadline, restoring: handoff,
                   onPlaybackIssue: handlePlaybackIssue, onStablePlayback: { rotation.reset() },
                   openMultiRoom: { rooms, seed in
                       pendingSwitch = nil
                       openMultiRoom(rooms, seed)
                   }) { next in
            pendingSwitch = nil
            rotation.reset()
            tune(next)
        }
        .id(room.key)
        .task(id: pendingSwitch) {
            guard let request = pendingSwitch else { return }
            await rotate(request)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { pendingSwitch = nil }
        }
    }

    private func handlePlaybackIssue(_ issue: PlaybackIssue?, roomKey: String) {
        guard room.key == roomKey else { return }
        guard let issue, scenePhase == .active, issue == .offline ? onLiveEnd : onFailure else {
            pendingSwitch = nil
            return
        }
        pendingSwitch = UUID()
    }

    private func rotate(_ request: UUID) async {
        let source = playlistOnly ? library.rotationRooms : library.favorites
        let targets = rotation.candidates(after: room, in: source, random: playlistOnly && random)
        let original = room.key
        for target in targets {
            guard canRotate(request, from: original) else { return }
            do {
                let resolved = try await core.service(target.provider).resolveRoom(target.roomId)
                guard canRotate(request, from: original) else { return }
                let alreadyAttempted = rotation.hasAttempted(resolved)
                rotation.markAttempted(target)
                guard resolved.isLive == true, !alreadyAttempted else { continue }
                rotation.markAttempted(resolved)
                pendingSwitch = nil
                tune(resolved)
                return
            } catch {
                guard canRotate(request, from: original) else { return }
                rotation.markAttempted(target)
            }
        }
        if pendingSwitch == request { pendingSwitch = nil }
    }

    private func canRotate(_ request: UUID, from original: String) -> Bool {
        !Task.isCancelled && pendingSwitch == request && room.key == original && scenePhase == .active
            && (sleepDeadline.map { $0 > .now } ?? true)
    }

    private func tune(_ next: RoomDescriptor) {
        if !queue.rooms.contains(where: { $0.key == next.key }) {
            queue = ChannelQueue(rooms: queue.rooms + [next], current: next)
        }
        handoff = nil
        room = next
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
