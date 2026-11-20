import Combine
import Foundation

enum FavoritePresence: String, CaseIterable, Sendable {
    case live, offline, unknown

    init(_ status: Bool?) {
        switch status {
        case true?: self = .live
        case false?: self = .offline
        case nil: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .live: "直播中"
        case .offline: "未开播"
        case .unknown: "状态未知"
        }
    }
}

@MainActor
final class FavoriteStatusStore: ObservableObject {
    struct Snapshot: Sendable {
        let presence: FavoritePresence
        let cover: String?
    }

    @Published private(set) var snapshots: [String: Snapshot] = [:]
    @Published private(set) var isRefreshing = false
    private var validKeys: Set<String>?
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

    func presence(for room: RoomDescriptor) -> FavoritePresence {
        snapshots[room.key]?.presence ?? .unknown
    }

    func sortedEntries(_ entries: [FavoriteEntry]) -> [FavoriteEntry] {
        entries.map { entry in
            let name = entry.displayName
            return (entry: entry, isLive: presence(for: entry.room) == .live,
                    name: name.applyingTransform(.mandarinToLatin, reverse: false) ?? name)
        }.sorted { lhs, rhs in
            if lhs.isLive != rhs.isLive { return lhs.isLive }
            return lhs.name.compare(rhs.name, options: [.caseInsensitive, .diacriticInsensitive, .numeric]) == .orderedAscending
        }.map(\.entry)
    }

    func refresh(_ rooms: [RoomDescriptor], fetch: @escaping @Sendable (RoomDescriptor) async throws -> RoomDescriptor) async {
        guard !rooms.isEmpty else { return }
        // A new view can request a refresh while the previous view's cancelled task is still finishing.
        while isRefreshing && !Task.isCancelled {
            await withCheckedContinuation { refreshWaiters.append($0) }
        }
        guard !Task.isCancelled else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        var seen = Set<String>()
        let unique = rooms.filter { seen.insert($0.key).inserted }
        let groups = Dictionary(grouping: unique, by: \.provider)
        await withTaskGroup(of: Void.self) { group in
            for platformRooms in groups.values {
                group.addTask { [weak self] in
                    for (index, room) in platformRooms.enumerated() {
                        if Task.isCancelled { break }
                        if index > 0 {
                            do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
                        }
                        do {
                            let result = try await fetch(room)
                            try Task.checkCancellation()
                            await self?.record(Snapshot(presence: FavoritePresence(result.isLive), cover: result.cover), for: room.key)
                        } catch {
                            if Task.isCancelled { break }
                            await self?.record(Snapshot(presence: .unknown, cover: nil), for: room.key)
                            // After explicit throttling, leave remaining entries untouched until the next refresh.
                            if case LiveProviderError.rateLimited = error { break }
                        }
                    }
                }
            }
            await group.waitForAll()
        }
    }

    func keepOnly(_ rooms: [RoomDescriptor]) {
        let ids = Set(rooms.map(\.key))
        validKeys = ids
        snapshots = snapshots.filter { ids.contains($0.key) }
    }

    private func record(_ snapshot: Snapshot, for key: String) {
        guard !Task.isCancelled, validKeys?.contains(key) != false else { return }
        snapshots[key] = snapshot
    }
}
