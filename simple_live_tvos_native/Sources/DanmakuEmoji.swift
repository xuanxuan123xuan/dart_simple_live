import Foundation
import SimpleLiveTVOSCore

enum DanmakuEmoji {
    private static let shortToken = try! NSRegularExpression(pattern: #"\[[^\[\]]{1,16}\]"#)

    static func douyu(_ message: String) -> [DanmakuSpan] {
        spans(in: message, matching: shortToken) {
            DouyuDanmakuEmojiAssets.urls[$0] ?? CommonDanmakuEmojiAssets.urls[$0]
        }
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
    static func permits(_ url: URL) -> Bool {
        guard let host = secureHost(url) else { return false }
        if isBilibili(host) || host == "shark2.douyucdn.cn" { return true }
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
