import Foundation

enum AccountSlot: String, CaseIterable, Identifiable, Sendable {
    case bilibili, douyu, douyin, kuaishou, xiaohongshu
    case kuaishouSecondary = "kuaishou.secondary"

    var id: String { rawValue }

    var otherKuaishouSlot: Self? {
        switch self {
        case .kuaishou: .kuaishouSecondary
        case .kuaishouSecondary: .kuaishou
        default: nil
        }
    }
}

enum AccountStatus: Equatable, Sendable {
    case signedOut, checking, verified, configured, invalid, unavailable
}

struct AccountCredential: Codable, Equatable, Sendable {
    let cookie: String
    let kww: String?
    let expiresAt: Date?

    init(cookie: String, kww: String? = nil, expiresAt: Date? = nil) {
        self.cookie = cookie
        self.kww = kww
        self.expiresAt = expiresAt
    }

    func replacingCookie(_ cookie: String) -> Self {
        Self(cookie: cookie, kww: kww, expiresAt: expiresAt)
    }
}

enum AccountCredentialError: LocalizedError {
    case invalidFormat, duplicateKuaishouAccount

    var errorDescription: String? {
        switch self {
        case .invalidFormat: "请输入有效的 Cookie"
        case .duplicateKuaishouAccount: "快手主账号和备用账号不能使用同一个账号"
        }
    }
}

struct AccountCookie {
    private var fields: [String: (name: String, value: String)] = [:]

    init(_ input: String) throws {
        let raw = Self.requestHeader("cookie", in: input) ?? input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.utf8.count <= 32_768, raw.utf8.allSatisfy({ (32...126).contains($0) }) else {
            throw AccountCredentialError.invalidFormat
        }
        let token = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        for part in raw.split(separator: ";") {
            let field = part.trimmingCharacters(in: .whitespaces)
            if field.isEmpty { continue }
            guard let split = field.firstIndex(of: "=") else { throw AccountCredentialError.invalidFormat }
            let name = field[..<split].trimmingCharacters(in: .whitespaces)
            let value = field[field.index(after: split)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.unicodeScalars.allSatisfy(token.contains) else {
                throw AccountCredentialError.invalidFormat
            }
            set(name, value: value)
        }
        guard fields.values.contains(where: { !$0.value.isEmpty }) else {
            throw AccountCredentialError.invalidFormat
        }
    }

    var header: String {
        fields.keys.sorted().compactMap { fields[$0] }.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    subscript(_ name: String) -> String? {
        guard let value = fields[name.lowercased()]?.value, !value.isEmpty else { return nil }
        return value
    }

    mutating func set(_ name: String, value: String) {
        fields[name.lowercased()] = (name, value)
    }

    mutating func remove(_ name: String) {
        fields.removeValue(forKey: name.lowercased())
    }

    static func requestHeader(_ name: String, in input: String) -> String? {
        let lines = input.split(whereSeparator: \.isNewline)
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.caseInsensitiveCompare(name) == .orderedSame, index + 1 < lines.count {
                return lines[index + 1].trimmingCharacters(in: .whitespaces)
            }
            if let colon = line.firstIndex(of: ":"),
               line[..<colon].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame {
                return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

/// Publishing a credential never suspends between Keychain, request credentials and UI state.
final class AccountRequestCredentials: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [AccountSlot: AccountCredential] = [:]

    func credential(for slot: AccountSlot) -> AccountCredential? {
        lock.withLock { values[slot] }
    }

    func withKuaishouAccount<T>(_ request: (AccountCredential?) async throws -> T) async throws -> T {
        for slot in [AccountSlot.kuaishou, .kuaishouSecondary] {
            try Task.checkCancellation()
            guard let value = credential(for: slot), (value.expiresAt ?? .distantFuture) > Date() else { continue }
            do {
                return try await request(value)
            } catch LiveProviderError.authenticationRequired {
                continue
            }
        }
        try Task.checkCancellation()
        return try await request(nil)
    }

    func set(_ credential: AccountCredential?, for slot: AccountSlot) {
        lock.withLock { values[slot] = credential }
    }
}
