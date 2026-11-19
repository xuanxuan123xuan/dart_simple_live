import XCTest
@testable import SimpleLiveTVOS

@MainActor
final class AccountImportTests: XCTestCase {
    func testImportPreparesThenCommitsSelectedAccountsTogether() async throws {
        let store = MemoryAccountStore()
        let requestCredentials = AccountRequestCredentials()
        let core = NativeCoreClient(accountStore: store, requestCredentials: requestCredentials)
        try await core.saveAccount(AccountCredential(cookie: "ttwid=original"), for: .douyin)
        try await core.saveAccount(AccountCredential(cookie: "passToken=primary; uid=1001"), for: .kuaishou)
        let expiry = Date().addingTimeInterval(3_600)
        let prepare: SyncImporter.PrepareAccounts = core.prepareSyncAccounts
        let commit = try await prepare([
            SyncAccount(slot: "kuaishou.secondary", cookie: "passToken=backup; uid=2002", kww: "signature", expiresAt: expiry),
            SyncAccount(slot: "xiaohongshu", cookie: "Cookie: web_session=new")
        ])
        XCTAssertNil(store.values[.kuaishouSecondary])
        XCTAssertNil(store.values[.xiaohongshu])
        XCTAssertEqual(core.accountStatus(.kuaishouSecondary), .signedOut)

        try commit()
        XCTAssertEqual(store.values[.douyin]?.cookie, "ttwid=original")
        XCTAssertEqual(store.values[.kuaishou]?.cookie, "passToken=primary; uid=1001")
        XCTAssertEqual(store.values[.kuaishouSecondary]?.expiresAt, expiry)
        XCTAssertEqual(store.values[.kuaishouSecondary]?.kww, "signature")
        XCTAssertEqual(store.values[.xiaohongshu]?.cookie, "web_session=new")
        XCTAssertEqual(requestCredentials.credential(for: .kuaishouSecondary), store.values[.kuaishouSecondary])
        XCTAssertEqual(core.accountStatus(.xiaohongshu), .configured)
    }

    func testInvalidSelectionAndFailedCommitLeavePreviousAccountsInPlace() async throws {
        let store = MemoryAccountStore()
        let requestCredentials = AccountRequestCredentials()
        let core = NativeCoreClient(accountStore: store, requestCredentials: requestCredentials)
        try await core.saveAccount(AccountCredential(cookie: "ttwid=stable"), for: .douyin)
        do {
            _ = try await core.prepareAccountImport([
                .douyin: AccountCredential(cookie: "ttwid=new"),
                .xiaohongshu: AccountCredential(cookie: "broken")
            ])
            XCTFail("An invalid credential passed preparation")
        } catch AccountCredentialError.invalidFormat {}
        let commit = try await core.prepareAccountImport([
            .douyin: AccountCredential(cookie: "ttwid=new"),
            .xiaohongshu: AccountCredential(cookie: "web_session=new")
        ])
        store.failWrites = true
        XCTAssertThrowsError(try commit())
        XCTAssertEqual(store.values[.douyin]?.cookie, "ttwid=stable")
        XCTAssertNil(store.values[.xiaohongshu])
        XCTAssertEqual(requestCredentials.credential(for: .douyin)?.cookie, "ttwid=stable")
        XCTAssertEqual(core.accountStatus(.xiaohongshu), .signedOut)
    }

    func testImportCannotRestoreAccountAfterNewerSignOut() async throws {
        let store = MemoryAccountStore()
        let core = NativeCoreClient(accountStore: store)
        let commit = try await core.prepareAccountImport([
            .douyin: AccountCredential(cookie: "ttwid=incoming"),
            .xiaohongshu: AccountCredential(cookie: "web_session=incoming")
        ])
        try core.signOut(.douyin)
        XCTAssertThrowsError(try commit()) {
            guard case AccountCredentialError.changedDuringImport = $0 else { return XCTFail("Expected import conflict") }
        }
        XCTAssertTrue(store.values.isEmpty)
    }

    func testImportCanSwapAccountsAndRejectsDuplicateTargetsAndIdentities() async throws {
        let core = NativeCoreClient(accountStore: MemoryAccountStore())
        let primary = AccountCredential(cookie: "passToken=primary; uid=1001")
        let secondary = AccountCredential(cookie: "passToken=secondary; uid=2002")
        try await core.saveAccount(primary, for: .kuaishou)
        try await core.saveAccount(secondary, for: .kuaishouSecondary)

        let swap = try await core.prepareAccountImport([.kuaishou: secondary, .kuaishouSecondary: primary])
        try swap()
        do {
            _ = try await core.prepareAccountImport([.kuaishouSecondary: secondary])
            XCTFail("The active primary identity was accepted in the backup slot")
        } catch AccountCredentialError.duplicateKuaishouAccount {}
        do {
            _ = try await core.prepareSyncAccounts([
                SyncAccount(slot: "kuaishou", cookie: primary.cookie),
                SyncAccount(slot: "kuaishou", cookie: secondary.cookie)
            ])
            XCTFail("Duplicate sync target was accepted")
        } catch AccountCredentialError.invalidFormat {}
    }
}
