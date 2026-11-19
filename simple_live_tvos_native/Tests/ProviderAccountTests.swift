import Security
import XCTest
@testable import SimpleLiveTVOS

@MainActor
final class ProviderAccountTests: XCTestCase {
    func testCookieProvidersUseKeychainAcrossClientsAndKeepSlotsSeparate() async throws {
        let namespace = "SimpleLiveTVOS.TV16.tests." + UUID().uuidString
        let store = KeychainSessionStore(service: namespace)
        defer { for slot in AccountSlot.allCases { try? store.clear(slot) } }
        let core = NativeCoreClient(accountStore: store)
        try await core.saveAccount(AccountCredential(cookie: "guest-device"), for: .douyin)
        try await core.saveAccount(AccountCredential(cookie: "Cookie: web_session=xhs-test"), for: .xiaohongshu)
        try await core.saveAccount(AccountCredential(cookie: "acf_auth=legacy; acf_uid=123"), for: .douyu)
        try await core.saveAccount(AccountCredential(
            cookie: "Cookie: kuaishou.live.web_st=one; userId=1001; did=device\nKww: test-header"
        ), for: .kuaishou)
        try await core.saveAccount(AccountCredential(
            cookie: "kuaishou.live.web_st=two; userId=2002; kwfv1=encoded%2Bvalue"
        ), for: .kuaishouSecondary)
        XCTAssertEqual(try store.read(.kuaishou)?.cookie, "kuaishou.live.web_st=one; userId=1001")
        XCTAssertEqual(try store.read(.kuaishou)?.kww, "test-header")
        XCTAssertEqual(try store.read(.douyin)?.cookie, "ttwid=guest-device")

        let restored = AccountRequestCredentials()
        let restarted = NativeCoreClient(accountStore: KeychainSessionStore(service: namespace), requestCredentials: restored)
        await restarted.start()
        for slot in [AccountSlot.douyin, .douyu, .kuaishou, .kuaishouSecondary, .xiaohongshu] {
            XCTAssertEqual(restarted.accountStatus(slot), .configured)
            XCTAssertEqual(restored.credential(for: slot), try store.read(slot))
        }
        try restarted.signOut(.kuaishou)
        XCTAssertNil(try store.read(.kuaishou))
        XCTAssertEqual(restarted.accountStatus(.kuaishou), .signedOut)
        XCTAssertEqual(restarted.accountStatus(.kuaishouSecondary), .configured)
        XCTAssertNotNil(restored.credential(for: .kuaishouSecondary))
    }

    func testLegacyKeychainValueIsReadable() throws {
        let namespace = "SimpleLiveTVOS.TV16.legacy." + UUID().uuidString
        let store = KeychainSessionStore(service: namespace)
        defer { try? store.clear(.bilibili) }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: namespace,
            kSecAttrAccount as String: AccountSlot.bilibili.rawValue,
            kSecValueData as String: Data("SESSDATA=legacy".utf8)
        ]
        XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)
        XCTAssertEqual(try store.read(.bilibili), AccountCredential(cookie: "SESSDATA=legacy"))
    }

    func testProviderValidationRejectsExpiredAndIncompleteCredentials() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let douyin = try ProviderAccountValidation.douyin(AccountCredential(cookie: "ttwid=value"), now: now)
        XCTAssertEqual(douyin.status, .configured)
        XCTAssertThrowsError(try ProviderAccountValidation.douyin(AccountCredential(cookie: "sid_guard=token%7C1700000000%7C1"), now: now))
        XCTAssertThrowsError(try ProviderAccountValidation.douyin(AccountCredential(cookie: "unrelated=entry"), now: now))
        XCTAssertThrowsError(try ProviderAccountValidation.kuaishou(AccountCredential(cookie: "did=guest; userId=1234"), now: now))
        let payload = Data(#"{"exp":1700000000}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try ProviderAccountValidation.kuaishou(AccountCredential(cookie: "kuaishou.live.web_st=x.\(payload).y"), now: now))
        XCTAssertThrowsError(try ProviderAccountValidation.kuaishou(
            AccountCredential(cookie: "passToken=test", kww: "header\r\nInjected: field"), now: now
        ))
        XCTAssertThrowsError(try ProviderAccountValidation.xiaohongshu(AccountCredential(cookie: "Cookie: invalid")))
    }

    func testKuaishouRejectsSameIdentityAndDerivesRequestHeader() async throws {
        let store = MemoryAccountStore()
        let core = NativeCoreClient(accountStore: store)
        try await core.saveAccount(AccountCredential(cookie: "kuaishou.live.web_st=one; userId=1001"), for: .kuaishou)
        do {
            try await core.saveAccount(AccountCredential(cookie: "UID=1001; kuaishou.live.web_st=another"), for: .kuaishouSecondary)
            XCTFail("The same account was assigned to both slots")
        } catch AccountCredentialError.duplicateKuaishouAccount {}
        XCTAssertNil(store.values[.kuaishouSecondary])
        let credential = AccountCredential(cookie: "kwfv1=test%2Bvalue; kuaishou.live.web_st=two", kww: "fallback")
        XCTAssertEqual(ProviderAccountValidation.kuaishouKww(credential), "test+value###ssrc")
        XCTAssertEqual(ProviderAccountValidation.kuaishouKww(AccountCredential(cookie: "passToken=one", kww: "fallback")), "fallback")
    }

    func testKuaishouFallbackIsBoundedAndSkipsExpiredOrDeletedAccounts() async throws {
        let accounts = AccountRequestCredentials()
        let primary = AccountCredential(cookie: "passToken=primary")
        let secondary = AccountCredential(cookie: "passToken=secondary")
        accounts.set(primary, for: .kuaishou)
        accounts.set(secondary, for: .kuaishouSecondary)
        var attempts: [AccountCredential?] = []
        let result = try await accounts.withKuaishouAccount { credential in
            attempts.append(credential)
            if credential != nil { throw LiveProviderError.authenticationRequired }
            return "anonymous"
        }
        XCTAssertEqual(result, "anonymous")
        XCTAssertEqual(attempts, [primary, secondary, nil])

        attempts = []
        accounts.set(AccountCredential(cookie: "passToken=expired", expiresAt: .distantPast), for: .kuaishou)
        let fallback = try await accounts.withKuaishouAccount { value in
            attempts.append(value)
            return value
        }
        XCTAssertEqual(fallback, secondary)
        XCTAssertEqual(attempts, [secondary])
        accounts.set(nil, for: .kuaishouSecondary)
        let guest = try await accounts.withKuaishouAccount { $0 }
        XCTAssertNil(guest)
    }

    func testKuaishouDoesNotRetryRateLimitsWithAnotherAccount() async {
        let accounts = AccountRequestCredentials()
        accounts.set(AccountCredential(cookie: "passToken=primary"), for: .kuaishou)
        accounts.set(AccountCredential(cookie: "passToken=secondary"), for: .kuaishouSecondary)
        var attempts = 0
        do {
            let _: Void = try await accounts.withKuaishouAccount { _ in
                attempts += 1
                throw LiveProviderError.rateLimited
            }
            XCTFail("The rate limit was swallowed")
        } catch LiveProviderError.rateLimited {
            XCTAssertEqual(attempts, 1)
        } catch {
            XCTFail("Unexpected failure: \(error)")
        }
    }
}
