import Foundation

enum MultiRoomLayout: String, CaseIterable {
    case grid, primary

    var title: String {
        switch self {
        case .grid: "均分"
        case .primary: "主次"
        }
    }
}

enum MultiRoomAudioMode: String, CaseIterable {
    case single, mixed

    var title: String {
        switch self {
        case .single: "单路有声"
        case .mixed: "多路混音"
        }
    }
}

enum MultiRoomDanmaku: String, CaseIterable {
    case inherited, enabled, disabled

    var title: String {
        switch self {
        case .inherited: "跟随全局弹幕设置"
        case .enabled: "全部开启"
        case .disabled: "全部关闭"
        }
    }

    func resolve(global: Bool) -> Bool {
        switch self {
        case .inherited: global
        case .enabled: true
        case .disabled: false
        }
    }
}

enum MultiRoomSpacing: Int, CaseIterable {
    case none = 0
    case narrow = 4
    case compact = 8
    case normal = 12
    case loose = 16
    case wide = 24

    var title: String { "\(rawValue) 点" }
}

struct MultiRoomPreferences {
    static let layoutKey = "simple_live_tvos.multiRoom.layout"
    static let spacingKey = "simple_live_tvos.multiRoom.spacing"
    static let audioKey = "simple_live_tvos.multiRoom.audio"
    static let danmakuKey = "simple_live_tvos.multiRoom.danmaku"
    static let globalDanmakuKey = "simple_live_tvos.danmaku"

    let layout: MultiRoomLayout
    let spacing: MultiRoomSpacing
    let audioMode: MultiRoomAudioMode
    let danmakuEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        layout = defaults.string(forKey: Self.layoutKey).flatMap(MultiRoomLayout.init(rawValue:)) ?? .grid
        let spacingValue = defaults.object(forKey: Self.spacingKey) as? Int
        spacing = spacingValue.flatMap(MultiRoomSpacing.init(rawValue:)) ?? .normal
        audioMode = defaults.string(forKey: Self.audioKey).flatMap(MultiRoomAudioMode.init(rawValue:)) ?? .single
        let danmaku = defaults.string(forKey: Self.danmakuKey).flatMap(MultiRoomDanmaku.init(rawValue:)) ?? .inherited
        danmakuEnabled = danmaku.resolve(global: defaults.object(forKey: Self.globalDanmakuKey) as? Bool ?? true)
    }
}
