import Foundation
import os

final class KuaishouEmojiPanel: Sendable {
    static let shared = KuaishouEmojiPanel()
    private static let endpoint = URL(string: "https://live.kuaishou.com/live_api/emoji/panel")!

    private struct State: Sendable {
        var urls: [String: String] = [:]
        var nextAttempt: TimeInterval = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var urls: [String: String] { state.withLock { $0.urls } }

    func refreshIfNeeded() {
        let now = ProcessInfo.processInfo.systemUptime
        let start = state.withLock { state in
            guard now >= state.nextAttempt else { return false }
            state.nextAttempt = now + 300
            return true
        }
        guard start else { return }
        Task {
            guard let data = try? await DanmakuAssetRequest.data(from: Self.endpoint, limit: 128 * 1024,
                                                               mimeTypePrefix: "application/json"),
                  let urls = try? Self.decode(data), !urls.isEmpty else { return }
            state.withLock {
                $0.urls = urls
                $0.nextAttempt = .infinity
            }
        }
    }

    static func decode(_ response: Data) throws -> [String: String] {
        guard let document = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              let entries = document["data"] as? [String: Any] else { return [:] }
        return entries.reduce(into: [:]) { urls, entry in
            guard DanmakuEmoji.isKuaishouToken(entry.key), let value = entry.value as? String,
                  let url = DanmakuStickerURL.kuaishou(value) else { return }
            urls[entry.key] = url.absoluteString
        }
    }
}
