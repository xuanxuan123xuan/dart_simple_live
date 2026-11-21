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
            Section {
                SettingsPicker("画面比例", selection: $aspect, options: PlaybackAspect.allCases) {
                    Text($0.title)
                }
                .accessibilityIdentifier("playback-aspect")
                SettingsPicker("默认清晰度", selection: $defaultQuality, options: PlaybackQualityPreference.allCases) {
                    Text($0.title)
                }
                SettingsPicker("初始音量", selection: Binding(get: { validVolume }, set: { initialVolume = $0 }),
                               options: volumeChoices) {
                    Text("\($0)%")
                }
                Toggle("网络波动时自动降低清晰度", isOn: $autoQuality)
                NavigationLink("频道轮播") { ChannelRotationSettingsView() }
            } header: {
                Text("默认播放")
            } footer: {
                Text("「适应」保留完整画面，「铺满」可能裁切边缘，「拉伸」会让画面填满可用空间，可能改变原比例。画面比例也应用于多屏。默认清晰度和初始音量在打开新的直播间时生效，清晰度依据平台提供的档位选择。")
            }
            Section {
                Toggle("KSPlayer 硬件解码", isOn: $hardwareDecode)
                SettingsPicker("播放缓冲", selection: $buffering, options: PlaybackBuffering.allCases) {
                    Text($0.title)
                }
            } header: {
                Text("原生播放引擎")
            } footer: {
                Text("较低延迟减少等待，较稳定增加预缓冲。缓冲和解码在下次连接时生效。硬件解码开关仅控制 KSPlayer，AVPlayer 由系统决定解码方式。")
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
