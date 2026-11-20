import XCTest
@testable import SimpleLiveTVOS

final class FavoriteStatusStoreTests: XCTestCase {
    @MainActor
    func testSortsLiveFirstAndInterleavesOfflineAndUnknownByName() async {
        let liveLatin = room("1", provider: "douyu", isLive: true, name: "DANK1NG")
        let liveChinese = room("2", provider: "douyin", isLive: true, name: "豆本熊")
        let offline = room("3", provider: "bilibili", isLive: false, name: "b主播")
        let unknown = room("4", provider: "huya", isLive: nil, name: "Alpha")
        let titleOnly = RoomDescriptor(provider: "kuaishou", roomId: "5", title: "Charlie", cover: "", userName: "")
        let store = FavoriteStatusStore()
        await store.refresh([liveChinese, offline, liveLatin]) { $0 }

        let entries = [FavoriteEntry(room: offline, isPriority: true), FavoriteEntry(room: liveChinese, isPriority: true),
                       FavoriteEntry(room: titleOnly), FavoriteEntry(room: unknown), FavoriteEntry(room: liveLatin)]
        XCTAssertEqual(store.sortedEntries(entries).map(\.id), [liveLatin.key, liveChinese.key, unknown.key, offline.key, titleOnly.key])
    }

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

    @MainActor
    func testRefreshFromNextViewSurvivesCancellationOfPreviousRefresh() async {
        let live = room("101", provider: "bilibili", isLive: true)
        let store = FavoriteStatusStore()
        let started = expectation(description: "Previous refresh starts")
        let previous = Task {
            await store.refresh([live]) { room in
                started.fulfill()
                try await Task.sleep(for: .seconds(10))
                return room
            }
        }
        await fulfillment(of: [started], timeout: 2)

        let cancel = Task { previous.cancel() }
        await store.refresh([live]) { $0 }
        await cancel.value
        await previous.value

        XCTAssertEqual(store.presence(for: live), .live)
        XCTAssertFalse(store.isRefreshing)
    }

    private func room(_ id: String, provider: String, isLive: Bool?, name: String = "") -> RoomDescriptor {
        RoomDescriptor(provider: provider, roomId: id, title: id, cover: "", userName: name, isLive: isLive)
    }
}
