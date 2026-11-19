import SwiftUI

extension PlaybackPreferences {
    static let hardwareDecode = "simple_live_tvos.playback.hardwareDecode"
    static let buffering = "simple_live_tvos.playback.buffering"
    static let defaultQuality = "simple_live_tvos.playback.defaultQuality"
    static let initialVolume = "simple_live_tvos.playback.initialVolume"
    static let aspect = "simple_live_tvos.playback.aspect"
}

enum PlaybackBuffering: String, CaseIterable {
    case automatic, lowLatency, stable

    var seconds: Double? {
        switch self {
        case .automatic: nil
        case .lowLatency: 1.5
        case .stable: 8
        }
    }

    var title: String {
        switch self {
        case .automatic: "系统默认"
        case .lowLatency: "较低延迟"
        case .stable: "较稳定"
        }
    }
}

enum PlaybackQualityPreference: String, CaseIterable {
    case providerDefault, highest, middle, lowest

    var title: String {
        switch self {
        case .providerDefault: "平台默认"
        case .highest: "优先最高已知档"
        case .middle: "优先中等已知档"
        case .lowest: "优先最低已知档"
        }
    }

    func select(from choices: [LiveQuality]) -> LiveQuality? {
        let ranked = choices.compactMap { quality in quality.recoveryRank.map { ($0, quality) } }
        switch self {
        case .providerDefault: return choices.first
        case .highest: return ranked.max { $0.0 < $1.0 }?.1 ?? choices.first
        case .middle:
            let ordered = ranked.sorted { $0.0 < $1.0 }
            return ordered.isEmpty ? choices.first : ordered[(ordered.count - 1) / 2].1
        case .lowest: return ranked.min { $0.0 < $1.0 }?.1 ?? choices.first
        }
    }
}

enum PlaybackAspect: String, CaseIterable {
    case fit, fill, stretch, wide, standard

    var title: String {
        switch self {
        case .fit: "适应"
        case .fill: "铺满"
        case .stretch: "拉伸"
        case .wide: "16:9"
        case .standard: "4:3"
        }
    }

    var ratio: CGFloat? {
        switch self {
        case .wide: 16.0 / 9.0
        case .standard: 4.0 / 3.0
        default: nil
        }
    }
}

struct PlaybackTuning {
    var hardwareDecode: Bool
    var buffering: PlaybackBuffering
    var defaultQuality: PlaybackQualityPreference
    var initialVolume: Int

    init(defaults: UserDefaults = .standard) {
        hardwareDecode = defaults.object(forKey: PlaybackPreferences.hardwareDecode) as? Bool ?? true
        buffering = PlaybackBuffering(rawValue: defaults.string(forKey: PlaybackPreferences.buffering) ?? "") ?? .automatic
        defaultQuality = PlaybackQualityPreference(rawValue: defaults.string(forKey: PlaybackPreferences.defaultQuality) ?? "") ?? .providerDefault
        initialVolume = min(100, max(0, (defaults.object(forKey: PlaybackPreferences.initialVolume) as? Int) ?? 100))
    }
}

struct PlaybackSettingsView: View {
    @AppStorage(PlaybackPreferences.autoQuality) private var autoQuality = true
    @AppStorage(PlaybackPreferences.hardwareDecode) private var hardwareDecode = true
    @AppStorage(PlaybackPreferences.buffering) private var buffering = PlaybackBuffering.automatic
    @AppStorage(PlaybackPreferences.defaultQuality) private var defaultQuality = PlaybackQualityPreference.providerDefault
    @AppStorage(PlaybackPreferences.initialVolume) private var initialVolume = 100
    @AppStorage(PlaybackPreferences.aspect) private var aspect = PlaybackAspect.fit

    var body: some View {
        List {
            Section("默认播放") {
                Picker("画面比例", selection: $aspect) {
                    ForEach(PlaybackAspect.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("playback-aspect")
                Picker("默认清晰度", selection: $defaultQuality) {
                    ForEach(PlaybackQualityPreference.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("初始音量", selection: Binding(get: { validVolume }, set: { initialVolume = $0 })) {
                    ForEach(volumeChoices, id: \.self) { Text("\($0)%").tag($0) }
                }
                Toggle("网络波动时自动降低清晰度", isOn: $autoQuality)
                NavigationLink("频道轮播") { ChannelRotationSettingsView() }
            }
            Section("原生播放引擎") {
                Toggle("KSPlayer 硬件解码", isOn: $hardwareDecode)
                Picker("播放缓冲", selection: $buffering) {
                    ForEach(PlaybackBuffering.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("缓冲与解码设置对下一次连接生效。AVPlayer 由系统决定解码方式。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("恢复默认播放设置") {
                autoQuality = true
                hardwareDecode = true
                buffering = .automatic
                defaultQuality = .providerDefault
                initialVolume = 100
                aspect = .fit
            }
        }
        .navigationTitle("播放设置")
    }

    private var validVolume: Int { min(100, max(0, initialVolume)) }

    private var volumeChoices: [Int] {
        let steps = Set(stride(from: 0, through: 100, by: 10))
        return steps.union([validVolume]).sorted()
    }
}
