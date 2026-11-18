import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [RoomDescriptor] = []
    @Published private(set) var recent: [RoomDescriptor] = []

    private let defaults = UserDefaults.standard
    private let favoritesKey = "simple_live_tvos.favorites.v1"
    private let recentKey = "simple_live_tvos.recent.v1"

    init() {
        favorites = load(favoritesKey)
        recent = load(recentKey)
    }

    func isFavorite(_ room: RoomDescriptor) -> Bool {
        favorites.contains { $0.key == room.key }
    }

    func toggleFavorite(_ room: RoomDescriptor) {
        if isFavorite(room) {
            favorites.removeAll { $0.key == room.key }
        } else {
            favorites.insert(room, at: 0)
            favorites = Array(favorites.prefix(200))
        }
        save(favorites, key: favoritesKey)
    }

    func visit(_ room: RoomDescriptor) {
        recent.removeAll { $0.key == room.key }
        recent.insert(room, at: 0)
        recent = Array(recent.prefix(80))
        save(recent, key: recentKey)
    }

    func clearRecent() {
        recent.removeAll()
        save(recent, key: recentKey)
    }

    private func load(_ key: String) -> [RoomDescriptor] {
        guard let data = defaults.data(forKey: key),
              let values = try? JSONDecoder().decode([RoomDescriptor].self, from: data) else {
            return []
        }
        return values
    }

    private func save(_ values: [RoomDescriptor], key: String) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: key)
    }
}
