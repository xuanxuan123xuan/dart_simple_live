import Foundation
import SimpleLiveTVOSCore
import SwiftUI

enum DanmakuDedupeMode: String, CaseIterable {
    case off, sameSender, allSenders

    var title: String {
        switch self {
        case .off: "关闭"
        case .sameSender: "同一用户"
        case .allSenders: "所有用户"
        }
    }
}

struct DanmakuFilterConfiguration: Equatable {
    var mode: DanmakuDedupeMode = .off
    var window: Int = 20
    var step: Int = 2
    var blockedWords: [String] = []
}

private enum DanmakuBlockRule {
    case literal(String)
    case regex(NSRegularExpression)

    init?(_ word: String) {
        let scalars = word.unicodeScalars
        if scalars.first == "/", scalars.last == "/", scalars.count > 2 {
            let pattern = String(scalars.dropFirst().dropLast())
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
            self = .regex(expression)
        } else {
            self = .literal(word)
        }
    }

    func matches(raw: String, normalized: String) -> Bool {
        switch self {
        case let .literal(word):
            return normalized.contains(word)
        case let .regex(expression):
            // Stop expensive patterns so the overlay can keep processing incoming messages.
            let deadline = DispatchTime.now() + .milliseconds(5)
            var matched = false
            expression.enumerateMatches(in: raw, options: .reportProgress,
                                        range: NSRange(location: 0, length: raw.utf16.count)) { result, _, stop in
                if result != nil { matched = true }
                if matched || DispatchTime.now() >= deadline { stop.pointee = true }
            }
            return matched
        }
    }
}

struct DanmakuFilter {
    private struct Fingerprint: Hashable {
        var sender: String?
        var message: String
    }

    private let configuration: DanmakuFilterConfiguration
    private let blockedRules: [DanmakuBlockRule]
    private var recent: [Fingerprint] = []
    private var acceptedSincePrune = 0

    init(_ configuration: DanmakuFilterConfiguration = DanmakuFilterConfiguration()) {
        self.configuration = configuration
        blockedRules = configuration.blockedWords.compactMap(DanmakuBlockRule.init)
    }

    mutating func allows(_ event: DanmakuEvent) -> Bool {
        let raw = Self.content(event)
        let text = Self.normalized(raw)
        guard !text.isEmpty, !blockedRules.contains(where: { $0.matches(raw: raw, normalized: text) }) else { return false }
        guard configuration.mode != .off else { return true }
        let sender = configuration.mode == .sameSender ? event.userName : nil
        let key = Fingerprint(sender: sender, message: text)
        let duplicate = recent.contains(key)
        recent.append(key)
        let window = min(100, max(configuration.mode == .allSenders ? 5 : 1, configuration.window))
        let step = configuration.mode == .allSenders ? 1 : min(20, max(1, configuration.step))
        acceptedSincePrune += 1
        if acceptedSincePrune >= step || recent.count > window + step - 1 {
            if recent.count > window { recent.removeFirst(recent.count - window) }
            acceptedSincePrune = 0
        }
        return !duplicate
    }

    static func message(_ event: DanmakuEvent) -> String {
        normalized(content(event))
    }

    private static func content(_ event: DanmakuEvent) -> String {
        guard event.message.isEmpty else { return event.message }
        return event.spans.map { span in
            switch span {
            case let .text(text): text
            case let .image(url, label): label ?? "[\(url.lastPathComponent)]"
            }
        }.joined()
    }

    private static func normalized(_ content: String) -> String {
        content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct DanmakuFilterStorage: DynamicProperty {
    @AppStorage("simple_live_tvos.danmaku.dedupeMode") var mode = DanmakuDedupeMode.off
    @AppStorage("simple_live_tvos.danmaku.dedupeWindow") var window = 20
    @AppStorage("simple_live_tvos.danmaku.dedupeStep") var step = 2

    func configuration(blockedWords: [String]) -> DanmakuFilterConfiguration {
        DanmakuFilterConfiguration(mode: mode, window: window, step: step, blockedWords: blockedWords)
    }
}

struct BlockedDanmakuWordsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var input = ""
    @State private var invalidPattern = false

    private var trimmedInput: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            Section("添加屏蔽词") {
                TextField("关键词或 /正则表达式/", text: $input)
                    .autocorrectionDisabled()
                    .onChange(of: input) { _, _ in invalidPattern = false }
                Button("添加", systemImage: "plus") {
                    guard DanmakuBlockRule(trimmedInput) != nil else {
                        invalidPattern = true
                        return
                    }
                    library.importBlockedWords([trimmedInput])
                    input = ""
                }
                .disabled(trimmedInput.isEmpty)
                if invalidPattern { Text("正则表达式格式有误").foregroundStyle(.red) }
            }
            Section("已屏蔽") {
                if library.blockedWords.isEmpty { Text("暂无屏蔽词").foregroundStyle(.secondary) }
                ForEach(library.blockedWords, id: \.self) { word in
                    Button("移除：\(word)", systemImage: "minus.circle") { library.removeBlockedWord(word) }
                }
            }
        }
        .navigationTitle("弹幕屏蔽词")
    }
}
