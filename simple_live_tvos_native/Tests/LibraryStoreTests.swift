import Foundation
import XCTest
@testable import SimpleLiveTVOS

final class LibraryStoreTests: XCTestCase {
    @MainActor
    func testLegacyMigrationKeepsEveryRoomAndPersistsPriorityAndClears() throws {
        try withDefaults { defaults in
            let rooms = (1...205).map { room(String($0)) }
            defaults.set(try JSONEncoder().encode(rooms + [rooms[0]]), forKey: "simple_live_tvos.favorites.v1")
            defaults.set(try JSONEncoder().encode(Array(rooms.prefix(85))), forKey: "simple_live_tvos.recent.v1")
            let store = LibraryStore(defaults: defaults)
            XCTAssertEqual(store.favorites, rooms)
            XCTAssertEqual(store.recent.count, 85)
            XCTAssertTrue(store.historyEntries.allSatisfy { $0.watchedAt == nil })

            store.setPriority(true, room: rooms[0])
            store.toggleFavorite(room("300"))
            store.clearRecent()
            let reloaded = LibraryStore(defaults: defaults)
            XCTAssertEqual(reloaded.favorites.count, 206)
            XCTAssertEqual(reloaded.favoriteEntries.first(where: { $0.room == rooms[0] })?.isPriority, true)
            XCTAssertTrue(reloaded.historyEntries.isEmpty, "Do not resurrect old history after a clear")
        }
    }

    @MainActor
    func testImportAndVisitsDeduplicateByPlatformKeepingNewestTimestamp() throws {
        try withDefaults { defaults in
            let store = LibraryStore(defaults: defaults)
            let first = Date(timeIntervalSince1970: 100)
            let second = Date(timeIntervalSince1970: 200)
            let third = Date(timeIntervalSince1970: 300)
            let bili = room("1")
            let douyu = room("1", provider: "douyu")
            store.visit(bili, at: first)
            store.importHistory([HistoryEntry(room: douyu, watchedAt: second), HistoryEntry(room: bili, watchedAt: third)])
            XCTAssertEqual(store.historyEntries.map(\.watchedAt), [third, second])
            XCTAssertEqual(store.recent, [bili, douyu])
            store.removeVisit(bili)
            XCTAssertEqual(LibraryStore(defaults: defaults).recent, [douyu])
        }
    }

    @MainActor
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "simple_live_tvos.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func room(_ id: String, provider: String = "bilibili") -> RoomDescriptor {
        RoomDescriptor(provider: provider, roomId: id, title: id, cover: "", userName: "")
    }
}
