struct MultiRoomSelection {
    static let minimum = 2
    static let maximum = 4
    private(set) var rooms: [RoomDescriptor]

    init(_ rooms: [RoomDescriptor] = []) {
        self.rooms = []
        for room in rooms {
            if self.rooms.count == Self.maximum { break }
            add(room)
        }
    }

    var canStart: Bool { rooms.count >= Self.minimum }

    func contains(_ room: RoomDescriptor) -> Bool { rooms.contains { $0.key == room.key } }

    @discardableResult
    mutating func toggle(_ room: RoomDescriptor) -> Bool {
        if let index = rooms.firstIndex(where: { $0.key == room.key }) {
            rooms.remove(at: index)
            return true
        }
        return add(room)
    }

    @discardableResult
    mutating func add(_ room: RoomDescriptor) -> Bool {
        guard !contains(room), rooms.count < Self.maximum else { return false }
        rooms.append(room)
        return true
    }
}
