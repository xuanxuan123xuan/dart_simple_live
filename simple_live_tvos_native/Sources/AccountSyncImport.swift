import Foundation

extension NativeCoreClient {
    func prepareSyncAccounts(_ accounts: [SyncAccount]) async throws -> (@MainActor () throws -> Void) {
        var entries: [AccountSlot: AccountCredential] = [:]
        for account in accounts {
            guard let slot = AccountSlot(rawValue: account.slot), entries[slot] == nil else {
                throw AccountCredentialError.invalidFormat
            }
            entries[slot] = AccountCredential(cookie: account.cookie, kww: account.kww, expiresAt: account.expiresAt)
        }
        return try await prepareAccountImport(entries)
    }
}
