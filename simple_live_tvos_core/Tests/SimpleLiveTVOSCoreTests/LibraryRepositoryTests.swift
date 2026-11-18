import XCTest
@testable import SimpleLiveTVOSCore

final class LibraryRepositoryTests: XCTestCase {
    func testFavoritesAndRecentUseProviderRoomIdentity() {
        let bili = RoomKey(provider: .bilibili, roomId: "100")
        let douyu = RoomKey(provider: .douyu, roomId: "100")
        var store = InMemoryLibraryRepository(favoriteLimit: 2, recentLimit: 2)

        store.toggleFavorite(bili)
        store.toggleFavorite(douyu)
        store.recordVisit(bili)
        store.recordVisit(douyu)

        XCTAssertEqual(store.favorites(), [douyu, bili])
        XCTAssertEqual(store.recent(), [douyu, bili])
        XCTAssertNotEqual(bili, douyu)
    }

    func testHistoryIsDeduplicatedAndBounded() {
        var store = InMemoryLibraryRepository(recentLimit: 2)
        let first = RoomKey(provider: .bilibili, roomId: "1")
        let second = RoomKey(provider: .bilibili, roomId: "2")
        let third = RoomKey(provider: .bilibili, roomId: "3")

        store.recordVisit(first)
        store.recordVisit(second)
        store.recordVisit(first)
        store.recordVisit(third)

        XCTAssertEqual(store.recent(), [third, first])
    }
}
