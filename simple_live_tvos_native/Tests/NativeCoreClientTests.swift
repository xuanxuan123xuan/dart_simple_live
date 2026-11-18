import XCTest
import SimpleLiveTVOSCore
@testable import SimpleLiveTVOS

final class NativeCoreClientTests: XCTestCase {
    func testProviderDescriptorIsIdentifiable() {
        let value = ProviderDescriptor(id: "bilibili", title: "哔哩哔哩", supportLabel: "HLS")
        XCTAssertEqual(value.id, "bilibili")
        XCTAssertEqual(value.title, "哔哩哔哩")
    }

    func testRoomIdentityIncludesProviderAndRoomId() {
        let bili = RoomDescriptor(
            provider: "bilibili",
            roomId: "100",
            title: "直播",
            cover: "",
            userName: "主播"
        )
        let douyu = RoomDescriptor(
            provider: "douyu",
            roomId: "100",
            title: "直播",
            cover: "",
            userName: "主播"
        )
        XCTAssertNotEqual(bili.key, douyu.key)
    }

    func testStreamProtocolNamesAreStable() {
        XCTAssertEqual(StreamProtocol.hls.rawValue, "hls")
        XCTAssertEqual(StreamProtocol.flv.rawValue, "flv")
        XCTAssertEqual(StreamProtocol.rtmp.rawValue, "rtmp")
    }

    @MainActor
    func testPaginationRetriesSamePageAndKeepsExistingRooms() async {
        let store = RoomResultsStore()
        let query = RoomResultsStore.Query(provider: "bilibili", listing: .recommended, retry: 0)
        let first = room("1")
        let second = room("2")
        await store.load(query) { page in
            XCTAssertEqual(page, 1)
            return RoomPage(rooms: [first], hasMore: true)
        }
        await store.load(query, next: true) { page in
            XCTAssertEqual(page, 2)
            throw LiveProviderError.serviceUnavailable
        }
        XCTAssertEqual(store.rooms, [first])
        XCTAssertEqual(store.status, .failed(LiveProviderError.serviceUnavailable.localizedDescription))
        await store.load(query, next: true) { page in
            XCTAssertEqual(page, 2)
            return RoomPage(rooms: [first, second, second], hasMore: false)
        }
        XCTAssertEqual(store.rooms, [first, second])
        XCTAssertEqual(store.status, .loaded)
        XCTAssertFalse(store.hasMore)
        await store.load(query, next: true) { _ in
            XCTFail("Do not fetch beyond the last page")
            return RoomPage(rooms: [], hasMore: false)
        }
    }

    @MainActor
    func testOverlappingRequestDoesNotReplaceNewPlatformResults() async {
        let store = RoomResultsStore()
        let old = RoomResultsStore.Query(provider: "bilibili", listing: .recommended, retry: 0)
        let current = RoomResultsStore.Query(provider: "douyu", listing: .recommended, retry: 0)
        let fresh = room("7", provider: "douyu")
        let stale = room("1")
        await store.load(old) { _ in
            await store.load(current) { _ in RoomPage(rooms: [fresh], hasMore: true) }
            return RoomPage(rooms: [stale], hasMore: false)
        }
        XCTAssertEqual(store.query, current)
        XCTAssertEqual(store.rooms, [fresh])
        XCTAssertTrue(store.hasMore)
    }

    private func room(_ id: String, provider: String = "bilibili") -> RoomDescriptor {
        RoomDescriptor(provider: provider, roomId: id, title: id, cover: "", userName: "")
    }
}
