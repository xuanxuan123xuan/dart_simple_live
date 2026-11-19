import Foundation
import Security

@MainActor
protocol AccountSessionStore {
    func read(_ slot: AccountSlot) throws -> AccountCredential?
    func saveBatch(_ credentials: [AccountSlot: AccountCredential]) throws
    func clear(_ slot: AccountSlot) throws
}

extension AccountSessionStore {
    func save(_ credential: AccountCredential, for slot: AccountSlot) throws {
        try saveBatch([slot: credential])
    }
}

@MainActor
final class KeychainSessionStore: AccountSessionStore {
    private let service: String
    private let accountIndex = "account-sessions.v2"

    init(service: String = "com.xuanxuan.simplelive.tvos.session") {
        self.service = service
    }

    func read(_ slot: AccountSlot) throws -> AccountCredential? {
        if let snapshot = try readSnapshot() { return snapshot[slot.rawValue] }
        return try readLegacy(slot)
    }

    func saveBatch(_ credentials: [AccountSlot: AccountCredential]) throws {
        guard !credentials.isEmpty else { return }
        var snapshot = try snapshotForUpdate(excluding: Set(credentials.keys))
        for (slot, credential) in credentials { snapshot[slot.rawValue] = credential }
        try writeSnapshot(snapshot)
    }

    func clear(_ slot: AccountSlot) throws {
        var snapshot = try snapshotForUpdate(excluding: [slot])
        snapshot[slot.rawValue] = nil
        try writeSnapshot(snapshot)
    }

    private func snapshotForUpdate(excluding slots: Set<AccountSlot>) throws -> [String: AccountCredential] {
        if let snapshot = try readSnapshot() { return snapshot }
        var legacy: [String: AccountCredential] = [:]
        for slot in AccountSlot.allCases where !slots.contains(slot) {
            legacy[slot.rawValue] = try readLegacy(slot)
        }
        return legacy
    }

    private func readSnapshot() throws -> [String: AccountCredential]? {
        guard let data = try readItem(accountIndex) else { return nil }
        guard let snapshot = try? JSONDecoder().decode([String: AccountCredential].self, from: data) else {
            throw KeychainError(errSecDecode)
        }
        return snapshot
    }

    private func readLegacy(_ slot: AccountSlot) throws -> AccountCredential? {
        guard let data = try readItem(slot.rawValue) else { return nil }
        if data.first == UInt8(ascii: "{") {
            guard let credential = try? JSONDecoder().decode(AccountCredential.self, from: data) else {
                throw KeychainError(errSecDecode)
            }
            return credential
        }
        guard let cookie = String(data: data, encoding: .utf8) else { throw KeychainError(errSecDecode) }
        return AccountCredential(cookie: cookie)
    }

    private func readItem(_ account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status) }
        guard let data = result as? Data else { throw KeychainError(errSecDecode) }
        return data
    }

    private func writeSnapshot(_ snapshot: [String: AccountCredential]) throws {
        let data = try JSONEncoder().encode(snapshot)
        let query = baseQuery(account: accountIndex)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw KeychainError(insertStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status)
        }

        // The snapshot is authoritative once saved. Retrying legacy cleanup on the
        // next write cannot bring back a signed-out account.
        for slot in AccountSlot.allCases {
            SecItemDelete(baseQuery(account: slot.rawValue) as CFDictionary)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    init(_ status: OSStatus) { self.status = status }
    var errorDescription: String? { "Keychain 操作失败（\(status)）" }
}
