import XCTest
@testable import SimpleLiveTVOS

final class SyncProfileTests: XCTestCase {
    static func fixture(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: SyncProfileTests.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @MainActor
    func testDartProfileMergeAndSelectedOverwrite() async throws {
        let suite = "SyncProfileTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = LibraryStore(defaults: defaults)
        let local = RoomDescriptor(provider: "huya", roomId: "7", title: "本机", cover: "", userName: "")
        library.toggleFavorite(local)
        library.visit(local, at: .distantPast)
        library.importBlockedWords(["本机规则"])
        let profile = try SyncProfile(data: Self.fixture("dart-profile-v4.json"))
        let importer = SyncImporter(library: library)
        let all = try profile.prepare(SyncSelection())
        try await importer.apply(all, overwrite: false, confirmed: false)
        XCTAssertEqual(library.favoriteEntries.map(\.id), [local.key, "bilibili:42"])
        XCTAssertTrue(library.favoriteEntries[1].isPriority)
        XCTAssertEqual(library.historyEntries.map(\.id), ["douyu:17", local.key])
        let timestamp = try XCTUnwrap(library.historyEntries.first?.watchedAt)
        XCTAssertEqual(timestamp.timeIntervalSince1970, 1795050903.123456, accuracy: 0.000002)
        XCTAssertEqual(library.blockedWords, ["本机规则", "关键词", "/广告.*/"])

        let history = try profile.prepare(SyncSelection(categories: [.histories]))
        do {
            try await importer.apply(history, overwrite: true, confirmed: false)
            XCTFail("Overwrite requires consent")
        } catch SyncError.confirmationRequired {}
        XCTAssertEqual(library.historyEntries.count, 2)
        try await importer.apply(history, overwrite: true, confirmed: true)
        let reopened = LibraryStore(defaults: defaults)
        XCTAssertEqual(reopened.historyEntries.map(\.id), ["douyu:17"])
        XCTAssertEqual(reopened.favoriteEntries, library.favoriteEntries)
        XCTAssertEqual(reopened.blockedWords, library.blockedWords)
    }

    @MainActor
    func testInvalidCategoryAndFailedAccountCommitPreserveExistingData() async throws {
        let suite = "SyncProfileTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = LibraryStore(defaults: defaults)
        library.importBlockedWords(["本机"])
        var malformed = SyncProfile()
        malformed.values = [.shields: ["更新"], .histories: [["siteId": "douyu"]]]
        XCTAssertThrowsError(try malformed.prepare(SyncSelection()))
        XCTAssertEqual(try malformed.prepare(SyncSelection(categories: [.shields])).shields, ["更新"])
        let profile = try SyncProfile(data: Self.fixture("dart-profile-v4.json"))
        let plan = try profile.prepare(SyncSelection(categories: [.shields, .accounts]))
        let importer = SyncImporter(library: library) { accounts in
            XCTAssertEqual(accounts.map(\.slot), ["bilibili", "kuaishou", "kuaishou.secondary"])
            return { throw SyncError.accountsUnavailable }
        }
        do {
            try await importer.apply(plan, overwrite: true, confirmed: true)
            XCTFail("Expected TV-16 commit failure")
        } catch SyncError.accountsUnavailable {}
        XCTAssertEqual(LibraryStore(defaults: defaults).blockedWords, ["本机"])
    }

    func testDartKuaishouExpirySentinelAndNumericString() throws {
        let profile = try SyncProfile(payload: [
            "schema": "simple_live_profile", "schemaVersion": 4,
            "accounts": ["items": [["siteId": "kuaishou", "slots": [
                "primary": ["cookie": "passToken=primary", "cookieExpiresAt": 0],
                "secondary": ["cookie": "passToken=secondary", "cookieExpiresAt": "1795050903000"],
            ]]]],
        ])
        let accounts = try XCTUnwrap(profile.prepare(SyncSelection(categories: [.accounts])).accounts)
        XCTAssertNil(accounts[0].expiresAt)
        XCTAssertEqual(accounts[1].expiresAt?.timeIntervalSince1970, 1795050903)
    }

    func testDartLegacyFormatsAndUnknownProviderProtection() throws {
        let history = try SyncProfile(data: Self.fixture("dart-legacy-history.json"))
        XCTAssertEqual(try history.prepare(SyncSelection()).histories?.first?.id, "douyu:17")
        let legacy = try SyncProfile(data: Self.fixture("dart-legacy-profile.json"))
        let plan = try legacy.prepare(SyncSelection(categories: [.accounts, .shields]))
        XCTAssertEqual(plan.accounts?.first?.slot, "douyu")
        XCTAssertEqual(plan.shields, ["旧规则"])

        var future = SyncProfile()
        future.values[.follows] = [["siteId": "future-site", "roomId": "1"]]
        let fallback = try future.prepare(SyncSelection())
        XCTAssertEqual(fallback.skipped, 1)
        XCTAssertTrue(fallback.mergeOnly.contains(.follows))
        XCTAssertThrowsError(try SyncProfile(payload: ["schema": "simple_live_profile", "schemaVersion": 5]))
    }

    func testSyncedSettingsOutsidePresetsHaveMatchingChoices() throws {
        let values = try SyncPreferences.nativeValues([
            "DanmuArea": 0.8, "FollowPageSize": 60,
            "AutoUpdateFollowEnable": true, "AutoUpdateFollowDuration": 7,
        ])
        let area = try XCTUnwrap(values["simple_live_tvos.danmaku.area"] as? Double)
        let pageSize = try XCTUnwrap(values[FavoritePreferences.pageSize] as? Int)
        let refresh = try XCTUnwrap(values[FavoritePreferences.refreshMinutes] as? Int)
        XCTAssertEqual([0.25, 0.5, 0.75, 1].includingSelection(area), [0.25, 0.5, 0.75, 0.8, 1])
        XCTAssertEqual([12, 24, 48, 100, 200, 400].includingSelection(pageSize), [12, 24, 48, 60, 100, 200, 400])
        XCTAssertEqual([0, 5, 10, 15, 30, 60].includingSelection(refresh), [0, 5, 7, 10, 15, 30, 60])
    }
}
