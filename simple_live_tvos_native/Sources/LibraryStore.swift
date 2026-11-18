import Foundation
import Combine

struct FavoriteEntry: Codable, Equatable, Identifiable {
    let room: RoomDescriptor
    var isPriority = false
    var id: String { room.key }
}

struct HistoryEntry: Codable, Equatable, Identifiable {
    let room: RoomDescriptor
    // v1 kept order but recorded no time; leave that timestamp unknown.
    let watchedAt: Date?
    var id: String { room.key }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favoriteEntries: [FavoriteEntry]
    @Published private(set) var historyEntries: [HistoryEntry]
    @Published private(set) var rotationRooms: [RoomDescriptor]
    @Published private(set) var blockedWords: [String]

    var favorites: [RoomDescriptor] { favoriteEntries.map(\.room) }
    var recent: [RoomDescriptor] { historyEntries.map(\.room) }

    private let defaults: UserDefaults
    private static let blockedWordsKey = "simple_live_tvos.danmaku.blockedWords.v1"
    private static let rotationKey = "simple_live_tvos.rotation.rooms.v1"
    private static let favoritesKey = "simple_live_tvos.favorites.v2"
    private static let recentKey = "simple_live_tvos.recent.v2"
    private static let legacyFavoritesKey = "simple_live_tvos.favorites.v1"
    private static let legacyRecentKey = "simple_live_tvos.recent.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        blockedWords = Self.cleanedWords(defaults.stringArray(forKey: Self.blockedWordsKey) ?? [])
        rotationRooms = Self.unique(Self.load(Self.rotationKey, from: defaults) ?? [])
        let savedFavorites: [FavoriteEntry]? = Self.load(Self.favoritesKey, from: defaults)
        let savedHistory: [HistoryEntry]? = Self.load(Self.recentKey, from: defaults)
        let legacyFavorites: [RoomDescriptor] = savedFavorites == nil ? Self.load(Self.legacyFavoritesKey, from: defaults) ?? [] : []
        let legacyHistory: [RoomDescriptor] = savedHistory == nil ? Self.load(Self.legacyRecentKey, from: defaults) ?? [] : []
        favoriteEntries = Self.unique(savedFavorites ?? legacyFavorites.map { FavoriteEntry(room: $0) })
        historyEntries = Self.unique(savedHistory ?? legacyHistory.map { HistoryEntry(room: $0, watchedAt: nil) })
        if savedFavorites == nil && !legacyFavorites.isEmpty { saveFavorites() }
        if savedHistory == nil && !legacyHistory.isEmpty { saveHistory() }
    }

    func isFavorite(_ room: RoomDescriptor) -> Bool {
        favoriteEntries.contains { $0.id == room.key }
    }

    func toggleFavorite(_ room: RoomDescriptor) {
        if let index = favoriteEntries.firstIndex(where: { $0.id == room.key }) {
            favoriteEntries.remove(at: index)
        } else {
            favoriteEntries.insert(FavoriteEntry(room: room), at: 0)
        }
        saveFavorites()
    }

    func setPriority(_ value: Bool, room: RoomDescriptor) {
        guard let index = favoriteEntries.firstIndex(where: { $0.id == room.key }),
              favoriteEntries[index].isPriority != value else { return }
        favoriteEntries[index].isPriority = value
        saveFavorites()
    }

    func importBlockedWords(_ words: [String], replacing: Bool = false) {
        blockedWords = Self.cleanedWords(replacing ? words : blockedWords + words)
        defaults.set(blockedWords, forKey: Self.blockedWordsKey)
    }

    func removeBlockedWord(_ word: String) {
        blockedWords.removeAll { $0 == word }
        defaults.set(blockedWords, forKey: Self.blockedWordsKey)
    }

    private static func cleanedWords(_ words: [String]) -> [String] {
        var seen = Set<String>()
        return words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func hasRotationRoom(_ room: RoomDescriptor) -> Bool {
        rotationRooms.contains { $0.key == room.key }
    }

    func toggleRotationRoom(_ room: RoomDescriptor) {
        if let index = rotationRooms.firstIndex(where: { $0.key == room.key }) {
            rotationRooms.remove(at: index)
        } else {
            rotationRooms.append(room)
        }
        save(rotationRooms, key: Self.rotationKey)
    }

    func moveRotationRoom(_ room: RoomDescriptor, by delta: Int) {
        guard let index = rotationRooms.firstIndex(where: { $0.key == room.key }) else { return }
        let (next, overflow) = index.addingReportingOverflow(delta)
        guard !overflow, next != index, rotationRooms.indices.contains(next) else { return }
        let moved = rotationRooms.remove(at: index)
        rotationRooms.insert(moved, at: next)
        save(rotationRooms, key: Self.rotationKey)
    }

    func visit(_ room: RoomDescriptor, at date: Date = Date()) {
        historyEntries.removeAll { $0.id == room.key }
        historyEntries.insert(HistoryEntry(room: room, watchedAt: date), at: 0)
        saveHistory()
    }

    func removeVisit(_ room: RoomDescriptor) {
        historyEntries.removeAll { $0.id == room.key }
        saveHistory()
    }

    func clearRecent() {
        historyEntries.removeAll()
        saveHistory()
    }

    /// Keep the most recent snapshot for each platform/room identity when merging an import.
    func importHistory(_ entries: [HistoryEntry], replacing: Bool = false) {
        let combined = replacing ? entries : historyEntries + entries
        let sorted = combined.enumerated().sorted { lhs, rhs in
            switch (lhs.element.watchedAt, rhs.element.watchedAt) {
            case let (a?, b?) where a != b: return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
        historyEntries = Self.unique(sorted)
        saveHistory()
    }

    private static func load<T: Decodable>(_ key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func unique<T: Identifiable>(_ values: [T]) -> [T] {
        var seen = Set<T.ID>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private func saveFavorites() { save(favoriteEntries, key: Self.favoritesKey) }
    private func saveHistory() { save(historyEntries, key: Self.recentKey) }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
