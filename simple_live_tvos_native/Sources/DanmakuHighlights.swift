import SwiftUI

struct DanmakuHighlightsConfiguration: Equatable {
    var enabled = false
    var fullScreen = true
    var window = 30
    var displayTime = 10
    var minimumCount = 5
}

struct DanmakuHighlights {
    struct Summary: Equatable {
        let text: String
        let count: Int
        let mostRecent: TimeInterval
    }

    private struct Sample {
        let text: String
        let time: TimeInterval
    }

    private var samples: [Sample] = []
    private var start = 0

    mutating func record(_ text: String, now: TimeInterval, window: Int) {
        guard !text.isEmpty else { return }
        prune(now: now, window: window)
        samples.append(Sample(text: String(text.prefix(256)), time: now))
        start = max(start, samples.count - 2_048)
    }

    mutating func summaries(now: TimeInterval, settings: DanmakuHighlightsConfiguration) -> [Summary] {
        prune(now: now, window: settings.window)
        var counts = [String: Summary]()
        for sample in samples.dropFirst(start) {
            counts[sample.text] = Summary(text: sample.text, count: (counts[sample.text]?.count ?? 0) + 1,
                                          mostRecent: sample.time)
        }
        let shown = counts.values.filter {
            $0.count >= max(2, settings.minimumCount) && now - $0.mostRecent <= Double(settings.displayTime)
        }.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            if a.mostRecent != b.mostRecent { return a.mostRecent > b.mostRecent }
            return a.text < b.text
        }
        return Array(shown.prefix(3))
    }

    private mutating func prune(now: TimeInterval, window: Int) {
        let earliest = now - Double(max(1, window))
        while start < samples.count, samples[start].time < earliest { start += 1 }
        if start > 256 && start >= samples.count / 4 {
            samples.removeFirst(start)
            start = 0
        }
    }
}

struct DanmakuHighlightsStorage: DynamicProperty {
    @AppStorage("simple_live_tvos.danmaku.highlights.enabled") var enabled = false
    @AppStorage("simple_live_tvos.danmaku.highlights.fullScreen") var fullScreen = true
    @AppStorage("simple_live_tvos.danmaku.highlights.window") var window = 30
    @AppStorage("simple_live_tvos.danmaku.highlights.displayTime") var displayTime = 10
    @AppStorage("simple_live_tvos.danmaku.highlights.minimumCount") var minimumCount = 5

    var configuration: DanmakuHighlightsConfiguration {
        DanmakuHighlightsConfiguration(enabled: enabled, fullScreen: fullScreen,
            window: min(120, max(5, window)), displayTime: min(60, max(3, displayTime)),
            minimumCount: min(20, max(2, minimumCount)))
    }
}

@MainActor
final class DanmakuHighlightsPresenter: ObservableObject {
    @Published private(set) var visible: [DanmakuHighlights.Summary] = []
    private var aggregator = DanmakuHighlights()
    private var previousWindow: Int?

    func record(_ text: String, window: Int) {
        aggregator.record(text, now: ProcessInfo.processInfo.systemUptime, window: window)
    }

    func refresh(_ settings: DanmakuHighlightsConfiguration) async {
        if !settings.enabled || previousWindow != settings.window {
            aggregator = DanmakuHighlights()
            visible = []
        }
        previousWindow = settings.window
        guard settings.enabled else { return }
        while !Task.isCancelled {
            let next = aggregator.summaries(now: ProcessInfo.processInfo.systemUptime, settings: settings)
            if next != visible { visible = next }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }
}
