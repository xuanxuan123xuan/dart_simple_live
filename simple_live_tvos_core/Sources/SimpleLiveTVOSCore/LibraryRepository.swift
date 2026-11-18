import Foundation

public protocol LibraryRepository {
    func favorites() -> [RoomKey]
    func recent() -> [RoomKey]
    func isFavorite(_ room: RoomKey) -> Bool
    mutating func toggleFavorite(_ room: RoomKey)
    mutating func recordVisit(_ room: RoomKey)
    mutating func clearRecent()
}

public struct InMemoryLibraryRepository: LibraryRepository, Sendable {
    public private(set) var favoriteRooms: [RoomKey] = []
    public private(set) var recentRooms: [RoomKey] = []
    public let favoriteLimit: Int
    public let recentLimit: Int

    public init(favoriteLimit: Int = 200, recentLimit: Int = 80) {
        self.favoriteLimit = favoriteLimit
        self.recentLimit = recentLimit
    }

    public func favorites() -> [RoomKey] { favoriteRooms }
    public func recent() -> [RoomKey] { recentRooms }
    public func isFavorite(_ room: RoomKey) -> Bool { favoriteRooms.contains(room) }

    public mutating func toggleFavorite(_ room: RoomKey) {
        if let index = favoriteRooms.firstIndex(of: room) {
            favoriteRooms.remove(at: index)
        } else {
            favoriteRooms.insert(room, at: 0)
            favoriteRooms = Array(favoriteRooms.prefix(favoriteLimit))
        }
    }

    public mutating func recordVisit(_ room: RoomKey) {
        recentRooms.removeAll { $0 == room }
        recentRooms.insert(room, at: 0)
        recentRooms = Array(recentRooms.prefix(recentLimit))
    }

    public mutating func clearRecent() { recentRooms.removeAll() }
}
