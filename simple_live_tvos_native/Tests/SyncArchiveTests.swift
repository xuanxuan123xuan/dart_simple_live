import XCTest
@testable import SimpleLiveTVOS

final class SyncArchiveTests: XCTestCase {
    func testDartZIPUsesCanonicalProfileAndLegacyFallback() throws {
        let selection = SyncSelection(categories: Set(SyncCategory.allCases))
        let modern = try SyncArchive.decode(SyncProfileTests.fixture("dart-backup-v4.zip"), selection: selection)
            .prepare(selection)
        XCTAssertEqual(modern.favorites?.first?.id, "bilibili:42")
        XCTAssertEqual(modern.histories?.first?.id, "douyu:17")
        XCTAssertEqual(modern.accounts?.count, 3)
        XCTAssertEqual(modern.settings?["simple_live_tvos.danmaku"] as? Bool, false)
        XCTAssertEqual(modern.settings?.count, 1)

        let legacy = try SyncArchive.decode(SyncProfileTests.fixture("dart-backup-legacy.zip"), selection: selection)
            .prepare(selection)
        XCTAssertEqual(legacy.favorites, modern.favorites)
        XCTAssertEqual(legacy.histories, modern.histories)
        XCTAssertEqual(legacy.shields, ["关键词", "/广告.*/"])
        XCTAssertEqual(legacy.accounts?.map(\.slot), ["bilibili"])
        XCTAssertEqual(legacy.settings?["simple_live_tvos.follow.onlyLive"] as? Bool, true)
    }

    func testArchiveRoundTripAndSelection() throws {
        let settings = SyncSelection(categories: [.histories, .settings])
        let modern = try SyncArchive.decode(SyncProfileTests.fixture("dart-backup-v4.zip"), selection: settings)
            .prepare(settings)
        let exported = try SyncArchive.encode(modern)
        let decoded = try SyncArchive.decode(exported, selection: settings).prepare(settings)
        XCTAssertNil(decoded.favorites)
        XCTAssertNil(decoded.accounts)
        XCTAssertNil(decoded.shields)
        XCTAssertEqual(decoded.histories?.map(\.id), ["douyu:17"])
        let stamp = try XCTUnwrap(decoded.histories?.first?.watchedAt)
        XCTAssertEqual(stamp.timeIntervalSince1970, 1795050903.123456, accuracy: 0.000002)
        XCTAssertEqual(decoded.settings?["simple_live_tvos.danmaku"] as? Bool, false)
        XCTAssertThrowsError(try SyncArchive.decode(Data(exported.prefix(12)), selection: settings))
    }
}
