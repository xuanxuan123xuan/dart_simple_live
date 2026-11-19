import CoreFoundation
import Foundation

/// Only preferences with equivalent tvOS controls are transported.
enum SyncPreferences {
    private struct Mapping {
        let dart: String
        let native: String
        let read: (Any) -> Any?
        let write: (Any) -> Any?

        init(_ dart: String, _ native: String, transform: @escaping (Any) -> Any?) {
            self.init(dart, native, read: transform, write: transform)
        }

        init(_ dart: String, _ native: String, read: @escaping (Any) -> Any?, write: @escaping (Any) -> Any?) {
            self.dart = dart
            self.native = "simple_live_tvos." + native
            self.read = read
            self.write = write
        }
    }

    private static let mappings = [
        Mapping("DanmuEnable", "danmaku", transform: boolean),
        Mapping("DanmuRenderEmoji", "danmaku.stickers", transform: boolean),
        Mapping("DanmuOpacity", "danmaku.opacity", transform: clamped(0.1...1)),
        Mapping("DanmuArea", "danmaku.area", transform: clamped(0.25...1)),
        Mapping("DanmuDisplayMode", "danmaku.layout", transform: choice(["area", "lines"])),
        Mapping("DanmuMaxLines", "danmaku.lines", transform: whole(1...6)),
        Mapping("DanmuDedupeWindow", "danmaku.dedupeWindow", transform: whole(1...100)),
        Mapping("DanmuDedupeStep", "danmaku.dedupeStep", transform: whole(1...5)),
        Mapping("LiveEventFlowEnable", "danmaku.highlights.enabled", transform: boolean),
        Mapping("LiveEventFlowOverlayEnable", "danmaku.highlights.fullScreen", transform: boolean),
        Mapping("LiveEventFlowWindowSeconds", "danmaku.highlights.window", transform: whole(1...120)),
        Mapping("LiveEventFlowDisplaySeconds", "danmaku.highlights.displayTime", transform: whole(1...60)),
        Mapping("LiveEventFlowMinCount", "danmaku.highlights.minimumCount", transform: whole(2...20)),
        Mapping("FollowOnlyLive", "follow.onlyLive", transform: boolean),
        Mapping("FollowRefreshOnEnter", "follow.refreshOnEnter", transform: boolean),
        Mapping("FollowShowLiveCover", "follow.showLiveCover", transform: boolean),
        Mapping("FollowPageSize", "follow.pageSize", transform: whole(2...400)),
        Mapping("FollowDisplayStyle", "follow.layout", read: { value in
            (value as? String) == "default" ? "standard" : choice(["compact", "card"])(value)
        }, write: { value in
            (value as? String) == "standard" ? "default" : choice(["compact", "card"])(value)
        }),
    ]
    private static let refreshKey = "simple_live_tvos.follow.refreshMinutes"
    private static let dedupeKey = "simple_live_tvos.danmaku.dedupeMode"

    static func nativeValues(_ values: [String: Any]) throws -> [String: Any] {
        var output: [String: Any] = [:]
        for mapping in mappings {
            guard let value = values[mapping.dart] else { continue }
            guard let mapped = mapping.read(value) else { throw SyncError.invalidCategory(.settings) }
            output[mapping.native] = mapped
        }
        if let enabled = values["AutoUpdateFollowEnable"] {
            guard let enabled = boolean(enabled) as? Bool else { throw SyncError.invalidCategory(.settings) }
            let minutes = values["AutoUpdateFollowDuration"].flatMap(whole(1...120)) as? Int ?? 10
            output[refreshKey] = enabled ? minutes : 0
        }
        if let enabled = values["DanmuDedupeEnable"] {
            guard let enabled = boolean(enabled) as? Bool else { throw SyncError.invalidCategory(.settings) }
            output[dedupeKey] = enabled ? ((values["DanmuDedupeMode"] as? Int == 1) ? "allSenders" : "sameSender") : "off"
        }
        return output
    }

    static func dartValues(_ values: [String: Any]) -> [String: Any] {
        var output: [String: Any] = [:]
        for mapping in mappings {
            if let value = values[mapping.native] { output[mapping.dart] = mapping.write(value) }
        }
        if let minutes = values[refreshKey] as? Int {
            output["AutoUpdateFollowEnable"] = minutes > 0
            if minutes > 0 { output["AutoUpdateFollowDuration"] = minutes }
        }
        if let mode = values[dedupeKey] as? String {
            output["DanmuDedupeEnable"] = mode != "off"
            output["DanmuDedupeMode"] = mode == "allSenders" ? 1 : 0
        }
        return output
    }

    static func read(_ defaults: UserDefaults) -> [String: Any] {
        let keys = mappings.map(\.native) + [refreshKey, dedupeKey]
        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in defaults.object(forKey: key).map { (key, $0) } })
    }

    private static func boolean(_ value: Any) -> Any? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func choice(_ accepted: Set<String>) -> (Any) -> Any? {
        { value in (value as? String).flatMap { accepted.contains($0) ? $0 : nil } }
    }

    private static func clamped(_ range: ClosedRange<Double>) -> (Any) -> Any? {
        { value in
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite else { return nil }
            return min(range.upperBound, max(range.lowerBound, number.doubleValue))
        }
    }

    private static func whole(_ range: ClosedRange<Int>) -> (Any) -> Any? {
        { value in
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let integer = Int(exactly: number.doubleValue) else { return nil }
            return min(range.upperBound, max(range.lowerBound, integer))
        }
    }
}
