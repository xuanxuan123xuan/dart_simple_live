import Foundation
import SimpleLiveTVOSCore

enum DanmakuEmoji {
    private static let shortToken = try! NSRegularExpression(pattern: #"\[[^\[\]]{1,16}\]"#)
    private static let kuaishouToken = try! NSRegularExpression(pattern: #"\[[^\[\]\r\n]{1,64}\]"#)

    static func douyu(_ message: String) -> [DanmakuSpan] {
        spans(in: message, matching: shortToken) {
            DouyuDanmakuEmojiAssets.urls[$0] ?? CommonDanmakuEmojiAssets.urls[$0]
        }
    }

    static func huya(_ message: String) -> [DanmakuSpan] {
        spans(in: message, matching: shortToken) {
            HuyaDanmakuEmojiAssets.urls[$0] ?? CommonDanmakuEmojiAssets.urls[$0]
        }
    }

    static func kuaishou(_ message: String) -> [DanmakuSpan] {
        spans(in: message, matching: kuaishouToken) { token in
            var candidates = [token]
            let lowercase = token.lowercased()
            if lowercase != token { candidates.append(lowercase) }
            var index = 0
            while index < candidates.count {
                if let alias = KuaishouDanmakuEmojiAssets.aliases[candidates[index]], !candidates.contains(alias) {
                    candidates.append(alias)
                }
                index += 1
            }
            for candidate in candidates {
                if let url = KuaishouDanmakuEmojiAssets.mobile[candidate] ?? KuaishouDanmakuEmojiAssets.web[candidate] {
                    return url
                }
            }
            return nil
        }
    }

    static func kuaishouText(_ message: String) -> String {
        let text = message as NSString
        let open = text.range(of: "[", options: .backwards)
        guard open.location != NSNotFound else { return message }
        let tail = NSRange(location: NSMaxRange(open), length: text.length - NSMaxRange(open))
        guard text.range(of: "]", options: .literal, range: tail).location == NSNotFound else { return message }
        var length = tail.length
        while length > 0, text.character(at: tail.location + length - 1) == 0xfffd {
            length -= 1
        }
        // Dart counts UTF-16 units and strips short partial tokens even when the name is unknown.
        return length <= 8 ? text.substring(to: open.location) : message
    }

    private static func spans(in message: String, matching pattern: NSRegularExpression,
                              lookup: (String) -> String?) -> [DanmakuSpan] {
        let text = message as NSString
        var cursor = 0
        var result: [DanmakuSpan] = []
        for match in pattern.matches(in: message, range: NSRange(location: 0, length: text.length)) {
            let token = text.substring(with: match.range)
            guard let value = lookup(token), let url = URL(string: value), DanmakuStickerURL.permits(url) else { continue }
            if cursor < match.range.location {
                result.append(.text(text.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            result.append(.image(url: url, fallbackText: token))
            cursor = NSMaxRange(match.range)
        }
        if cursor < text.length { result.append(.text(text.substring(from: cursor))) }
        return result
    }
}

enum DanmakuStickerURL {
    private static let kuaishouHosts: Set<String> = [
        "ali2.a.yximgs.com", "bd.a.yximgs.com", "p4-plat.wsbkwai.com", "p66-plat.ndcjl.com",
    ]

    static func permits(_ url: URL) -> Bool {
        guard let host = secureHost(url) else { return false }
        if isBilibili(host) || host == "shark2.douyucdn.cn"
            || host == "cdnfile2.msstatic.com" || host == "materials-g-ai.msstatic.com" { return true }
        if kuaishouHosts.contains(host) { return true }
        return host == "cdn.jsdelivr.net" && url.path.hasPrefix("/gh/twitter/twemoji@14.0.2/assets/72x72/")
    }

    static func bilibili(_ string: String) -> URL? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: value.hasPrefix("//") ? "https:" + value : value) else { return nil }
        if parts.scheme == "http" { parts.scheme = "https" }
        guard let url = parts.url, let host = secureHost(url), isBilibili(host) else { return nil }
        return url
    }

    private static func secureHost(_ url: URL) -> String? {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return nil }
        return url.host?.lowercased()
    }

    private static func isBilibili(_ host: String) -> Bool {
        host == "hdslb.com" || host.hasSuffix(".hdslb.com")
    }
}
