import XCTest
@testable import SimpleLiveTVOS

@MainActor
final class AccountSessionTests: XCTestCase {
    func testVerifiedCredentialSurvivesRestartAndSignOutClearsIt() async throws {
        let store = MemoryAccountStore()
        let credentials = AccountRequestCredentials()
        let core = NativeCoreClient(accountStore: store, requestCredentials: credentials) { _, credential in
            credential.replacingCookie(credential.cookie + "; refreshed=yes")
        }
        try await core.finishLogin(cookie: "User-Agent: Browser\r\nCookie: LTP0=test; dy_did=device", provider: "douyu")
        let saved = try XCTUnwrap(store.values[.douyu])
        XCTAssertEqual(saved.cookie, "dy_did=device; LTP0=test; refreshed=yes")
        XCTAssertEqual(core.accountStatus(.douyu), .verified)
        XCTAssertEqual(credentials.credential(for: .douyu), saved)

        let restoredCredentials = AccountRequestCredentials()
        let restarted = NativeCoreClient(accountStore: store, requestCredentials: restoredCredentials) { _, credential in credential }
        await restarted.start()
        XCTAssertEqual(restarted.accountStatus(.douyu), .verified)
        XCTAssertEqual(restoredCredentials.credential(for: .douyu), saved)
        try restarted.signOut(.douyu)
        XCTAssertEqual(restarted.accountStatus(.douyu), .signedOut)
        XCTAssertNil(store.values[.douyu])
        XCTAssertNil(restoredCredentials.credential(for: .douyu))
    }

    func testRejectedReplacementAndStorageFailureKeepPreviousSession() async throws {
        let store = MemoryAccountStore()
        let credentials = AccountRequestCredentials()
        let core = NativeCoreClient(accountStore: store, requestCredentials: credentials) { _, credential in
            guard credential.cookie != "SESSDATA=expired" else { throw LiveProviderError.authenticationRequired }
            return credential
        }
        try await core.finishLogin(cookie: "SESSDATA=valid", provider: "bilibili")
        let original = store.values[.bilibili]
        do {
            try await core.finishLogin(cookie: "SESSDATA=expired", provider: "bilibili")
            XCTFail("Expired Cookie was accepted")
        } catch LiveProviderError.authenticationRequired {}
        store.failWrites = true
        do {
            try await core.finishLogin(cookie: "SESSDATA=replacement", provider: "bilibili")
            XCTFail("Failed save was reported as successful")
        } catch MemoryAccountStore.Failure.write {}
        XCTAssertThrowsError(try core.signOut(.bilibili))
        XCTAssertEqual(store.values[.bilibili], original)
        XCTAssertEqual(credentials.credential(for: .bilibili), original)
        XCTAssertEqual(core.accountStatus(.bilibili), .verified)
    }

    func testUnavailableRestoreRetainsCredentialAndCanBeRetried() async {
        let store = MemoryAccountStore()
        store.values[.bilibili] = AccountCredential(cookie: "SESSDATA=old")
        store.values[.douyu] = AccountCredential(cookie: "LTP0=expired; dy_did=device")
        var online = false
        let core = NativeCoreClient(accountStore: store) { slot, credential in
            if slot == .douyu { throw LiveProviderError.authenticationRequired }
            if !online { throw LiveProviderError.serviceUnavailable }
            return credential
        }
        await core.start()
        XCTAssertEqual(core.accountStatus(.bilibili), .unavailable)
        XCTAssertEqual(core.accountStatus(.douyu), .invalid)
        XCTAssertEqual(store.values.count, 2)
        online = true
        await core.restoreAccount(.bilibili)
        XCTAssertEqual(core.accountStatus(.bilibili), .verified)
    }

    func testSignOutSupersedesAnInFlightRestore() async throws {
        let store = MemoryAccountStore()
        let credentials = AccountRequestCredentials()
        let old = AccountCredential(cookie: "SESSDATA=previous")
        store.values[.bilibili] = old
        let entered = expectation(description: "validation started")
        var validation: CheckedContinuation<AccountCredential, Never>?
        let core = NativeCoreClient(accountStore: store, requestCredentials: credentials) { _, _ in
            await withCheckedContinuation {
                validation = $0
                entered.fulfill()
            }
        }
        let restore = Task { await core.start() }
        await fulfillment(of: [entered], timeout: 2)
        try core.signOut(.bilibili)
        validation?.resume(returning: old)
        await restore.value
        XCTAssertEqual(core.accountStatus(.bilibili), .signedOut)
        XCTAssertNil(store.values[.bilibili])
        XCTAssertNil(credentials.credential(for: .bilibili))
    }

    func testCookieParsingRejectsMalformedValuesAndPreservesEquals() throws {
        XCTAssertEqual(try AccountCookie("cookie\nSESSION=data==\naccept\n*/*").header, "SESSION=data==")
        XCTAssertThrowsError(try AccountCookie("SESSION=test\r\nOther: data"))
        XCTAssertThrowsError(try AccountCookie("SESSION=\u{0}"))
        XCTAssertThrowsError(try AccountCookie("SESSION="))
    }
}

@MainActor
final class MemoryAccountStore: AccountSessionStore {
    enum Failure: Error { case write }

    var values: [AccountSlot: AccountCredential] = [:]
    var failWrites = false

    func read(_ slot: AccountSlot) throws -> AccountCredential? { values[slot] }

    func saveBatch(_ credentials: [AccountSlot: AccountCredential]) throws {
        if failWrites { throw Failure.write }
        values.merge(credentials) { _, new in new }
    }

    func clear(_ slot: AccountSlot) throws {
        if failWrites { throw Failure.write }
        values[slot] = nil
    }
}
