import XCTest
@testable import SimpleLiveTVOS

final class FavoriteStatusStoreTests: XCTestCase {
    @MainActor
    func testRefreshDistinguishesOfflineFromNetworkFailureAndPreservesOtherPlatforms() async {
        let live = room("101", provider: "bilibili", isLive: true)
        let offline = room("101", provider: "huya", isLive: false)
        let unavailable = room("101", provider: "douyu", isLive: true)
        let store = FavoriteStatusStore()
        await store.refresh([live, offline, unavailable]) { room in
            if room.provider == "douyu" { throw LiveProviderError.serviceUnavailable }
            return room
        }
        XCTAssertEqual(store.presence(for: live), .live)
        XCTAssertEqual(store.presence(for: offline), .offline)
        XCTAssertEqual(store.presence(for: unavailable), .unknown)
        await store.refresh([live]) { _ in throw LiveProviderError.rateLimited }
        XCTAssertEqual(store.presence(for: live), .unknown)
        XCTAssertEqual(store.presence(for: offline), .offline)
        XCTAssertFalse(store.isRefreshing)
    }

    @MainActor
    func testRemovingAnEntryDoesNotRestoreItsSnapshotAfterAnInflightRefresh() async {
        let live = room("101", provider: "bilibili", isLive: true)
        let store = FavoriteStatusStore()
        store.keepOnly([live])
        await store.refresh([live]) { room in
            await store.keepOnly([])
            return room
        }
        XCTAssertNil(store.snapshots[live.key])
    }

    private func room(_ id: String, provider: String, isLive: Bool) -> RoomDescriptor {
        RoomDescriptor(provider: provider, roomId: id, title: id, cover: "", userName: "", isLive: isLive)
    }
}
