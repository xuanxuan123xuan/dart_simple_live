@testable import SimpleLiveTVOS
import XCTest

final class ChannelRotationTests: XCTestCase {
    private func room(_ id: String, provider: String = "huya") -> RoomDescriptor {
        RoomDescriptor(provider: provider, roomId: id, title: id, cover: "", userName: "")
    }

    func testSequentialRotationWrapsAndExhaustsWithoutRevisiting() {
        let a = room("one"), b = room("two"), c = room("one", provider: "douyu")
        let source = [a, b, c, a]
        var rotation = ChannelRotation()
        XCTAssertEqual(rotation.candidates(after: b, in: source, random: false), [c, a])
        rotation.markAttempted(c)
        XCTAssertEqual(rotation.candidates(after: c, in: source, random: false), [a])
        rotation.markAttempted(a)
        XCTAssertTrue(rotation.candidates(after: a, in: source, random: false).isEmpty)
        rotation.reset()
        XCTAssertEqual(Set(rotation.candidates(after: a, in: source, random: true).map(\.key)), Set([b.key, c.key]))
    }

    @MainActor
    func testPlaylistOrderPersistsIndependentOfFavorites() throws {
        let suite = "rotation-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = room("one"), b = room("two")
        let store = LibraryStore(defaults: defaults)
        store.toggleFavorite(a)
        store.toggleRotationRoom(a)
        store.toggleRotationRoom(b)
        store.moveRotationRoom(a, by: 1)
        store.toggleFavorite(a)
        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertEqual(LibraryStore(defaults: defaults).rotationRooms, [b, a])
        store.toggleRotationRoom(b)
        XCTAssertEqual(LibraryStore(defaults: defaults).rotationRooms, [a])
    }
}
