import SwiftUI

enum DanmakuLayout: String, CaseIterable {
    case area, lines

    var title: String { self == .lines ? "按行数" : "按区域" }
}

struct DanmakuStyle: Equatable {
    var fontSize: Double = 36
    var crossingSeconds: Double = 9
    var opacity: Double = 1
    var renderStickers = true
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
    @AppStorage("simple_live_tvos.danmaku.stickers") var renderStickers = true
    @AppStorage("simple_live_tvos.danmaku.stroke") var outlineWidth = 8.0
    @AppStorage("simple_live_tvos.danmaku.layout") var layout = DanmakuLayout.area
    @AppStorage("simple_live_tvos.danmaku.area") var area = 0.25
    @AppStorage("simple_live_tvos.danmaku.lines") var lines = 3

    var style: DanmakuStyle {
        DanmakuStyle(fontSize: clamp(fontSize, to: 20...64, fallback: 36),
                     crossingSeconds: clamp(crossingSeconds, to: 3...18, fallback: 9),
                     opacity: clamp(opacity, to: 0.1...1, fallback: 1), renderStickers: renderStickers,
                     outlineWidth: clamp(outlineWidth, to: 0...16, fallback: 8),
                     layout: layout, area: clamp(area, to: 0.25...1, fallback: 0.25),
                     lines: min(6, max(1, lines)))
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

struct DanmakuSettingsView: View {
    @AppStorage(MultiRoomPreferences.globalDanmakuKey) private var enabled = true
    private var storage = DanmakuStyleStorage()
    private var filtering = DanmakuFilterStorage()
    private var highlightStorage = DanmakuHighlightsStorage()

    var body: some View {
        List {
            Section {
                Toggle("显示直播弹幕", isOn: $enabled)
                Toggle("显示图片表情", isOn: storage.$renderStickers)
                SettingsPicker("弹幕字号", selection: storage.$fontSize, options: [24, 30, 36, 42, 48, 56, 64]) {
                    Text("\(Int($0))")
                }
                SettingsPicker("滚动速度", selection: storage.$crossingSeconds, options: [15, 12, 9, 6, 4]) {
                    Text("\(Int($0)) 秒横穿画面")
                }
                SettingsPicker("弹幕不透明度", selection: storage.$opacity,
                               options: (1...10).map { Double($0) / 10 }.includingSelection(storage.opacity)) {
                    Text($0, format: .percent.precision(.fractionLength(0...2)))
                }
                SettingsPicker("文字描边宽度", selection: storage.$outlineWidth,
                               options: [0, 2, 4, 6, 8, 10, 12, 14, 16]) {
                    Text("\(Int($0))")
                }
            } header: {
                Text("显示")
            } footer: {
                Text("横穿画面用时越短，弹幕滚动越快。关闭直播弹幕会同时隐藏滚动弹幕和重点动态。多屏可单独设置是否开启弹幕，图片表情需平台提供。")
            }
            Section {
                SettingsPicker("范围设置方式", selection: storage.$layout, options: DanmakuLayout.allCases) {
                    Text($0.title)
                }
                if storage.layout == .lines {
                    SettingsPicker("最多行数", selection: storage.$lines, options: Array(1...6)) {
                        Text("\($0) 行")
                    }
                } else {
                    SettingsPicker("弹幕区域", selection: storage.$area,
                                   options: [0.25, 0.5, 0.75, 1].includingSelection(storage.area)) { value in
                        value == 1 ? Text("全屏") : Text(value, format: .percent.precision(.fractionLength(0...2)))
                    }
                }
            } header: {
                Text("弹幕位置")
            } footer: {
                Text("弹幕从画面顶部排列。按行数设置的是上限，实际可显示的行数取决于画面高度和弹幕大小。")
            }
            Section {
                Toggle("显示重点动态", isOn: highlightStorage.$enabled)
                if highlightStorage.enabled {
                    Toggle("隐藏控制面板时显示", isOn: highlightStorage.$fullScreen)
                    SettingsPicker("重复弹幕统计时长", selection: highlightStorage.$window,
                                   options: [5, 10, 15, 30, 60, 120].includingSelection(highlightStorage.window)) {
                        Text("\($0) 秒")
                    }
                    SettingsPicker("重点动态停留时间", selection: highlightStorage.$displayTime,
                                   options: [3, 5, 10, 15, 30, 60].includingSelection(highlightStorage.displayTime)) {
                        Text("\($0) 秒")
                    }
                    SettingsPicker("触发重点动态的最少次数", selection: highlightStorage.$minimumCount,
                                   options: [2, 3, 5, 8, 10, 20].includingSelection(highlightStorage.minimumCount)) {
                        Text("\($0) 次")
                    }
                }
            } header: {
                Text("重点动态")
            } footer: {
                Text("重点动态会汇总通过过滤的重复弹幕。关闭「隐藏控制面板时显示」后，汇总只在控制面板打开时出现。")
            }
            Section {
                NavigationLink("屏蔽词") { BlockedDanmakuWordsView() }
                SettingsPicker("重复过滤模式", selection: filtering.$mode, options: DanmakuDedupeMode.allCases) {
                    Text($0.title)
                }
                if filtering.mode != .off {
                    let presets = filtering.mode == .allSenders ? [5, 10, 20, 30, 50, 100] : [1, 5, 10, 20, 30, 50, 100]
                    SettingsPicker("比较最近多少条弹幕", selection: filtering.$window,
                                   options: presets.includingSelection(filtering.window)) {
                        Text("\($0) 条")
                    }
                    if filtering.mode == .sameSender {
                        SettingsPicker("每隔多少条清理过滤记录", selection: filtering.$step,
                                       options: [1, 2, 3, 5].includingSelection(filtering.step)) {
                            Text("\($0) 条")
                        }
                    }
                }
            } header: {
                Text("过滤")
            } footer: {
                Text("重复过滤按弹幕条数向前比较。同一用户模式下，会定期清理过滤记录。")
            }
        }
        .onChange(of: filtering.mode) { _, mode in
            if mode == .allSenders { filtering.window = max(5, filtering.window) }
        }
        .navigationTitle("弹幕设置")
    }
}
