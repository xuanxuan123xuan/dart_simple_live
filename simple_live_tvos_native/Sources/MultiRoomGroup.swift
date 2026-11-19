import Observation

@MainActor
@Observable
final class MultiRoomGroup {
    private(set) var sessions: [RoomPlaybackSession] = []
    private(set) var selectedKey: String?
    private(set) var primaryKey: String?
    private(set) var expandedKey: String?
    private(set) var audioKey: String?
    private(set) var audioMode: MultiRoomAudioMode
    private var initialDanmaku: Bool
    var layout: MultiRoomLayout

    init(rooms: [RoomDescriptor], preferences: MultiRoomPreferences = .init(), restoring handoff: RoomPlaybackHandoff? = nil) {
        layout = preferences.layout
        audioMode = preferences.audioMode
        initialDanmaku = preferences.danmakuEnabled
        replaceRooms(rooms, restoring: handoff)
    }

    var rooms: [RoomDescriptor] { sessions.map(\.room) }
    var selected: RoomPlaybackSession? { sessions.first { $0.room.key == selectedKey } }
    var allPaused: Bool { sessions.allSatisfy { $0.engine.pausedByUser } }
    var allDanmakuEnabled: Bool { sessions.allSatisfy { $0.danmakuOverride == true } }

    @discardableResult
    func replaceRooms(_ rooms: [RoomDescriptor]) -> Bool { replaceRooms(rooms, restoring: nil) }

    @discardableResult
    private func replaceRooms(_ rooms: [RoomDescriptor], restoring handoff: RoomPlaybackHandoff?) -> Bool {
        let selection = MultiRoomSelection(rooms)
        guard selection.canStart else { return false }
        let byRoom = Dictionary(uniqueKeysWithValues: sessions.map { ($0.room.key, $0) })
        let keys = Set(selection.rooms.map(\.key))
        let pauseNewRooms = !sessions.isEmpty && allPaused
        for session in sessions where !keys.contains(session.room.key) { session.retire() }
        sessions = selection.rooms.map { room in
            if let existing = byRoom[room.key] { return existing }
            let session = RoomPlaybackSession(room: room, danmakuEnabled: initialDanmaku, restoring: handoff)
            if pauseNewRooms { session.engine.setPaused(true) }
            return session
        }
        let first = sessions.first?.room.key
        if selectedKey.map(keys.contains) != true { selectedKey = first }
        if primaryKey.map(keys.contains) != true { primaryKey = first }
        if audioKey.map(keys.contains) != true { audioKey = first }
        if expandedKey.map(keys.contains) != true { expandedKey = nil }
        applyAudioRouting()
        return true
    }

    func select(_ key: String) {
        guard contains(key) else { return }
        selectedKey = key
    }

    func makePrimary(_ key: String) {
        guard contains(key) else { return }
        primaryKey = key
        layout = .primary
    }

    func toggleExpanded(_ key: String) {
        guard contains(key) else { return }
        select(key)
        expandedKey = expandedKey == key ? nil : key
    }

    func setAudioFocus(_ key: String) {
        guard contains(key) else { return }
        audioKey = key
        applyAudioRouting()
    }

    func setAudioMode(_ mode: MultiRoomAudioMode) {
        audioMode = mode
        applyAudioRouting()
    }

    private func applyAudioRouting() {
        // Mute the old output before opening the new one.
        if audioMode == .single {
            for session in sessions where session.room.key != audioKey { session.engine.setAudioSuppressed(true) }
            sessions.first { $0.room.key == audioKey }?.engine.setAudioSuppressed(false)
        } else {
            for session in sessions { session.engine.setAudioSuppressed(false) }
        }
    }

    func setPaused(_ paused: Bool) {
        for session in sessions { session.engine.setPaused(paused) }
    }

    func refresh() {
        for session in sessions { session.refresh() }
    }

    func setDanmaku(_ enabled: Bool) {
        initialDanmaku = enabled
        for session in sessions { session.danmakuOverride = enabled }
    }

    func remove(_ key: String) {
        replaceRooms(rooms.filter { $0.key != key })
    }

    func stop() {
        for session in sessions { session.stop() }
    }

    func retire() {
        for session in sessions { session.retire() }
    }

    private func contains(_ key: String) -> Bool {
        sessions.contains { $0.room.key == key }
    }
}
