import SwiftUI

enum DanmakuLayout: String, CaseIterable {
    case area, lines

    var title: String { self == .lines ? "按行数" : "按区域" }
}

struct DanmakuStyle: Equatable {
    var fontSize: Double = 36
    var crossingSeconds: Double = 9
    var opacity: Double = 1
    var outlineWidth: Double = 8
    var layout: DanmakuLayout = .area
    var area: Double = 0.25
    var lines = 3

    func laneCount(height: CGFloat, topInset: CGFloat, lineHeight: CGFloat) -> Int {
        let available = max(0, height - topInset)
        switch layout {
        case .area:
            return max(0, Int((height * area - topInset) / lineHeight))
        case .lines:
            return min(lines, Int(available / lineHeight))
        }
    }
}

struct DanmakuStyleStorage: DynamicProperty {
    @AppStorage("simple_live_tvos.danmaku.font") var fontSize = 36.0
    @AppStorage("simple_live_tvos.danmaku.speed") var crossingSeconds = 9.0
    @AppStorage("simple_live_tvos.danmaku.opacity") var opacity = 1.0
    @AppStorage("simple_live_tvos.danmaku.stroke") var outlineWidth = 8.0
    @AppStorage("simple_live_tvos.danmaku.layout") var layout = DanmakuLayout.area
    @AppStorage("simple_live_tvos.danmaku.area") var area = 0.25
    @AppStorage("simple_live_tvos.danmaku.lines") var lines = 3

    var style: DanmakuStyle {
        DanmakuStyle(fontSize: clamp(fontSize, to: 20...64, fallback: 36),
                     crossingSeconds: clamp(crossingSeconds, to: 3...18, fallback: 9),
                     opacity: clamp(opacity, to: 0.1...1, fallback: 1),
                     outlineWidth: clamp(outlineWidth, to: 0...16, fallback: 8),
                     layout: layout, area: clamp(area, to: 0.25...1, fallback: 0.25),
                     lines: min(6, max(1, lines)))
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

struct DanmakuSettingsView: View {
    @AppStorage("simple_live_tvos.danmaku") private var enabled = true
    private var storage = DanmakuStyleStorage()

    var body: some View {
        List {
            Section("显示") {
                Toggle("显示直播弹幕", isOn: $enabled)
                Picker("弹幕大小", selection: storage.$fontSize) {
                    ForEach([24.0, 30, 36, 42, 48, 56, 64], id: \.self) { Text("\(Int($0))").tag($0) }
                }
                Picker("弹幕速度", selection: storage.$crossingSeconds) {
                    ForEach([15.0, 12, 9, 6, 4], id: \.self) { Text("\(Int($0)) 秒横穿画面").tag($0) }
                }
                Picker("不透明度", selection: storage.$opacity) {
                    ForEach(1...10, id: \.self) { Text("\($0 * 10)%").tag(Double($0) / 10) }
                }
                Picker("描边宽度", selection: storage.$outlineWidth) {
                    ForEach(Array(stride(from: 0, through: 16, by: 2)), id: \.self) { Text("\($0)").tag(Double($0)) }
                }
            }
            Section("弹幕位置") {
                Picker("范围模式", selection: storage.$layout) {
                    ForEach(DanmakuLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if storage.layout == .lines {
                    Picker("最多行数", selection: storage.$lines) {
                        ForEach(1...6, id: \.self) { Text("\($0) 行").tag($0) }
                    }
                } else {
                    Picker("弹幕区域", selection: storage.$area) {
                        Text("1/4").tag(0.25)
                        Text("1/2").tag(0.5)
                        Text("3/4").tag(0.75)
                        Text("全屏").tag(1.0)
                    }
                }
            }
        }
        .navigationTitle("弹幕设置")
    }
}
