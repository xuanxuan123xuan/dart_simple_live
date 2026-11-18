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

struct DanmakuFilter {
    private struct Fingerprint: Hashable {
        var sender: String?
        var message: String
    }

    private let configuration: DanmakuFilterConfiguration
    private var recent: [Fingerprint] = []
    private var acceptedSincePrune = 0

    init(_ configuration: DanmakuFilterConfiguration = DanmakuFilterConfiguration()) {
        self.configuration = configuration
    }

    mutating func allows(_ event: DanmakuEvent) -> Bool {
        let text = Self.message(event)
        guard !text.isEmpty, !configuration.blockedWords.contains(where: { text.contains($0) }) else { return false }
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
        let fallback = event.spans.map { span in
            switch span {
            case let .text(text): text
            case let .image(url, label): label ?? "[\(url.lastPathComponent)]"
            }
        }.joined()
        let content = event.message.isEmpty ? fallback : event.message
        return content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
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

    var body: some View {
        List {
            Section("添加文字关键词") {
                TextField("输入要屏蔽的文字", text: $input)
                    .autocorrectionDisabled()
                Button("添加", systemImage: "plus") {
                    library.importBlockedWords([input])
                    input = ""
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
