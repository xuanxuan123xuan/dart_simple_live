import Foundation
import Security

@MainActor
protocol AccountSessionStore {
    func read(_ slot: AccountSlot) throws -> AccountCredential?
    func save(_ credential: AccountCredential, for slot: AccountSlot) throws
    func clear(_ slot: AccountSlot) throws
}

@MainActor
final class KeychainSessionStore: AccountSessionStore {
    private let service: String

    init(service: String = "com.xuanxuan.simplelive.tvos.session") {
        self.service = service
    }

    func read(_ slot: AccountSlot) throws -> AccountCredential? {
        var query = baseQuery(provider: slot.rawValue)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status) }
        guard let data = result as? Data else { throw KeychainError(errSecDecode) }
        if data.first == UInt8(ascii: "{") {
            guard let credential = try? JSONDecoder().decode(AccountCredential.self, from: data) else {
                throw KeychainError(errSecDecode)
            }
            return credential
        }
        guard let cookie = String(data: data, encoding: .utf8) else { throw KeychainError(errSecDecode) }
        return AccountCredential(cookie: cookie)
    }

    func save(_ credential: AccountCredential, for slot: AccountSlot) throws {
        let data = try JSONEncoder().encode(credential)
        let query = baseQuery(provider: slot.rawValue)
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
    }

    func clear(_ slot: AccountSlot) throws {
        let status = SecItemDelete(baseQuery(provider: slot.rawValue) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status)
        }
    }

    private func baseQuery(provider: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
        ]
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    init(_ status: OSStatus) { self.status = status }
    var errorDescription: String? { "Keychain 操作失败（\(status)）" }
}
