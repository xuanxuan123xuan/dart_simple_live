import Foundation

struct ValidatedAccount {
    let credential: AccountCredential
    let status: AccountStatus
}

enum ProviderAccountValidation {
    static func douyin(_ credential: AccountCredential, now: Date = Date()) throws -> ValidatedAccount {
        let input = credential.cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        let isBareToken = input.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || "-_.%".utf8.contains($0)
        }
        let cookie = try AccountCookie(isBareToken ? "ttwid=" + input : input)
        let login = ["sessionid", "sid_guard", "sid_tt", "uid_tt"].contains { cookie[$0] != nil } || cookie["login_status"] == "1"
        guard login || cookie["ttwid"] != nil else { throw AccountCredentialError.invalidFormat }
        if let sidGuard = cookie["sid_guard"]?.removingPercentEncoding {
            let parts = sidGuard.split(separator: "|", omittingEmptySubsequences: false)
            if parts.count >= 3, let loggedIn = Double(parts[1]), let maxAge = Double(parts[2]),
               loggedIn.isFinite, maxAge.isFinite, loggedIn > 0, maxAge >= 0 {
                let start = loggedIn > 1_000_000_000_000 ? loggedIn / 1000 : loggedIn
                if start + maxAge <= now.timeIntervalSince1970 { throw LiveProviderError.authenticationRequired }
            }
        }
        return ValidatedAccount(credential: AccountCredential(cookie: cookie.header), status: .configured)
    }

    static func douyuWithoutRefresh(_ cookie: AccountCookie, now: Date = Date()) -> ValidatedAccount? {
        if cookie["LTP0"] != nil, cookie["dy_did"] != nil || cookie["acf_did"] != nil { return nil }
        let jwtValid = tokenExpiry(cookie["acf_jwt_token"]).map { $0 > now } ?? false
        let hasLegacySession = cookie["acf_auth"] != nil && (Int(cookie["acf_uid"] ?? "") ?? 0) > 0
        guard jwtValid || hasLegacySession else { return nil }
        return ValidatedAccount(credential: AccountCredential(cookie: cookie.header), status: .configured)
    }

    static func kuaishou(_ credential: AccountCredential, now: Date = Date()) throws -> ValidatedAccount {
        var cookie = try AccountCookie(credential.cookie)
        let tokenNames = ["kuaishou.live.web_st", "kuaishou.server.web_st", "kuaishou.live.web_at", "kuaishou.server.web_at", "passToken"]
        guard tokenNames.contains(where: { cookie[$0] != nil }) else { throw AccountCredentialError.invalidFormat }
        for name in ["did", "didv", "clientid", "client_key", "kpn", "kuaishou.live.bfb1s"] {
            cookie.remove(name)
        }
        let kww = credential.kww ?? AccountCookie.requestHeader("kww", in: credential.cookie)
            ?? AccountCookie.requestHeader("kwfv1", in: credential.cookie)
        guard kww.map(safeHeaderValue) != false else { throw AccountCredentialError.invalidFormat }
        let embedded = tokenNames.lazy.compactMap { tokenExpiry(cookie[$0]) }.first
        let expiration = [credential.expiresAt, embedded].compactMap { $0 }.min()
        if let expiration, expiration <= now { throw LiveProviderError.authenticationRequired }
        return ValidatedAccount(
            credential: AccountCredential(cookie: cookie.header, kww: kww?.isEmpty == false ? kww : nil, expiresAt: expiration),
            status: .configured
        )
    }

    static func sameKuaishouAccount(_ lhs: AccountCredential, _ rhs: AccountCredential) -> Bool {
        let left = cookiePairs(lhs.cookie)
        let right = cookiePairs(rhs.cookie)
        if left == right { return true }
        if let uid = kuaishouUID(left), uid == kuaishouUID(right) { return true }
        return false
    }

    static func kuaishouKww(_ credential: AccountCredential) -> String? {
        if let cookieValue = try? AccountCookie(credential.cookie)["kwfv1"] {
            let decoded = cookieValue.removingPercentEncoding ?? cookieValue
            return (safeHeaderValue(decoded) ? decoded : cookieValue) + "###ssrc"
        }
        return credential.kww
    }

    static func xiaohongshu(_ credential: AccountCredential) throws -> ValidatedAccount {
        let cookie = try AccountCookie(credential.cookie)
        return ValidatedAccount(credential: AccountCredential(cookie: cookie.header), status: .configured)
    }

    private static func kuaishouUID(_ fields: [String: String]) -> String? {
        ["userid", "user_id", "uid", "kuaishou.user.id"].lazy.compactMap { fields[$0] }.first {
            $0.range(of: #"^[A-Za-z0-9_-]{4,64}$"#, options: .regularExpression) != nil
        }
    }

    private static func safeHeaderValue(_ input: String) -> Bool {
        input.utf8.count <= 8192 && input.utf8.allSatisfy { (32...126).contains($0) }
    }

    private static func tokenExpiry(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let parts = (raw.removingPercentEncoding ?? raw).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let json = try? JSONObject.decode(data) else { return nil }
        for field in ["exp", "expiresAt", "expireAt", "expiration"] {
            guard let value = Double(json.text(field)), value.isFinite, value > 0 else { continue }
            let seconds = value < 100_000_000_000 ? value : value / 1000
            if (1_577_836_800...7_258_118_400).contains(seconds) { return Date(timeIntervalSince1970: seconds) }
        }
        return nil
    }
}
