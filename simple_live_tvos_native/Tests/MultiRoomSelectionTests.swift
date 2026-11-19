@testable import SimpleLiveTVOS
import XCTest

final class MultiRoomSelectionTests: XCTestCase {
    func testSeedDeduplicatesByProviderAndRoomAndKeepsFirstFour() {
        let first = room("bilibili", "1")
        let otherPlatform = room("huya", "1")
        let extra = (2...4).map { room("bilibili", String($0)) }
        let selection = MultiRoomSelection([first, room("bilibili", "1", title: "新标题"), otherPlatform] + extra)

        XCTAssertEqual(selection.rooms, [first, otherPlatform, extra[0], extra[1]])
        XCTAssertTrue(selection.canStart)
    }

    func testStartsAtTwoAndCanRemoveAndReplaceAtCapacity() {
        let rooms = (1...5).map { room("bilibili", String($0)) }
        var selection = MultiRoomSelection([rooms[0]])
        XCTAssertFalse(selection.canStart)
        XCTAssertFalse(selection.add(room("bilibili", "1", title: "新标题")))
        XCTAssertTrue(selection.toggle(rooms[1]))
        XCTAssertTrue(selection.canStart)
        XCTAssertTrue(selection.add(rooms[2]))
        XCTAssertTrue(selection.add(rooms[3]))
        XCTAssertFalse(selection.add(rooms[4]))
        XCTAssertTrue(selection.toggle(room("bilibili", "1", title: "新标题")))
        XCTAssertTrue(selection.add(rooms[4]))
        XCTAssertEqual(selection.rooms, Array(rooms.dropFirst()))
    }

    private func room(_ provider: String, _ id: String, title: String = "直播") -> RoomDescriptor {
        RoomDescriptor(provider: provider, roomId: id, title: title, cover: "", userName: "")
    }
}
