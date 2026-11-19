import Foundation
import CoreFoundation

enum SyncCategory: String, CaseIterable, Identifiable {
    case follows, histories, shields, settings, accounts

    var id: Self { self }
    var title: String {
        switch self {
        case .follows: "关注"
        case .histories: "观看历史"
        case .shields: "屏蔽词"
        case .settings: "通用设置"
        case .accounts: "账号"
        }
    }

    static let library: Set<Self> = [.follows, .histories, .shields]
}

enum SyncError: LocalizedError {
    case invalidProfile, unsupportedVersion, invalidCategory(SyncCategory), tooLarge
    case noSelection, confirmationRequired, busy, accountsUnavailable
    case invalidChunk, incompleteTransfer, invalidAddress, connectionFailed
    case invalidArchive, httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidProfile: "配置包格式无效"
        case .unsupportedVersion: "暂不支持该配置包版本"
        case let .invalidCategory(category): "\(category.title)数据格式无效"
        case .tooLarge: "同步数据超过大小限制"
        case .noSelection: "没有可导入的已选类别"
        case .confirmationRequired: "请确认覆盖已有数据"
        case .busy: "已有同步导入正在处理"
        case .accountsUnavailable: "当前账号接口无法导入所选凭据"
        case .invalidChunk: "分块编号、范围或内容不一致"
        case .incompleteTransfer: "分块传输不完整，请重新发送"
        case .invalidAddress: "地址格式无效"
        case .connectionFailed: "连接失败，请检查网络和服务地址"
        case .invalidArchive: "备份 ZIP 格式无效"
        case let .httpStatus(code): "服务器返回 HTTP \(code)"
        }
    }
}

struct SyncAccount: Equatable {
    let slot: String
    let cookie: String
    var kww: String? = nil
    var expiresAt: Date? = nil
}

struct SyncSelection {
    var categories: Set<SyncCategory> = SyncCategory.library
    var accountSites: Set<String>? = nil
}

struct SyncImportPlan {
    var favorites: [FavoriteEntry]?
    var histories: [HistoryEntry]?
    var shields: [String]?
    var settings: [String: Any]?
    var accounts: [SyncAccount]?
    var mergeOnly: Set<SyncCategory> = []
    var skipped = 0

    var hasData: Bool { favorites != nil || histories != nil || shields != nil || settings != nil || accounts != nil }
    var summary: String {
        var parts: [String] = []
        if let favorites { parts.append("关注 \(Set(favorites.map(\.id)).count) 条") }
        if let histories { parts.append("历史 \(Set(histories.map(\.id)).count) 条") }
        if let shields { parts.append("屏蔽词 \(Set(shields).count) 条") }
        if let settings { parts.append("设置 \(settings.count) 项") }
        if let accounts { parts.append("账号 \(accounts.count) 个") }
        if skipped > 0 { parts.append("跳过 \(skipped) 条") }
        return parts.joined(separator: "，")
    }
}

struct SyncProfile {
    static let maxBytes = 16 * 1024 * 1024
    static let sites: Set<String> = ["bilibili", "douyu", "huya", "douyin", "kuaishou", "xiaohongshu"]
    static let accountSites = sites.subtracting(["huya"])

    var values: [SyncCategory: Any] = [:]
    var legacySettings: [String: Any] = [:]

    init() {}

    init(data: Data) throws {
        guard data.count <= Self.maxBytes else { throw SyncError.tooLarge }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.invalidProfile
        }
        try self.init(payload: payload)
    }

    init(payload: [String: Any]) throws {
        if let schema = payload["schema"] {
            guard schema as? String == "simple_live_profile" else { throw SyncError.invalidProfile }
            let version = payload["schemaVersion"] ?? 2
            guard let number = version as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  [2.0, 3.0, 4.0].contains(number.doubleValue) else { throw SyncError.unsupportedVersion }
            if number.intValue < 4 { legacySettings = payload["settings"] as? [String: Any] ?? [:] }
            values[.settings] = payload["settings"]
            values[.accounts] = payload["accounts"]
            values[.shields] = payload["danmuShield"]
        } else if payload["type"] as? String == "simple_live" {
            values[.settings] = payload["config"]
            legacySettings = payload["config"] as? [String: Any] ?? [:]
            if let shield = payload["shield"] {
                guard let map = shield as? [String: Any] else { throw SyncError.invalidCategory(.shields) }
                values[.shields] = map.keys.sorted().compactMap { map[$0] }
            }
        }
        values[.follows] = Self.firstValue(payload, keys: ["followUsers", "follows", "favorites"])
        values[.histories] = Self.firstValue(payload, keys: ["histories", "history"])
        if let data = payload["data"] as? [Any], let first = data.first {
            if let room = first as? [String: Any] {
                values[room["updateTime"] != nil ? .histories : .follows] = data
            } else if first is String {
                values[.shields] = data
            } else {
                throw SyncError.invalidProfile
            }
        }
        guard !values.isEmpty || !legacySettings.isEmpty || payload["schema"] != nil
              || payload["type"] as? String == "simple_live" else { throw SyncError.invalidProfile }
    }

    func prepare(_ selection: SyncSelection) throws -> SyncImportPlan {
        var plan = SyncImportPlan()
        if selection.categories.contains(.follows), let value = values[.follows] {
            let rows = try Self.rooms(value, category: .follows, plan: &plan)
            plan.favorites = rows.map { room, row in
                FavoriteEntry(room: room, isPriority: (row["isSpecialFollow"] as? NSNumber)?.intValue == 1)
            }
        }
        if selection.categories.contains(.histories), let value = values[.histories] {
            let rows = try Self.rooms(value, category: .histories, plan: &plan)
            plan.histories = try rows.map { room, row in
                let stamp = row["updateTime"]
                guard stamp == nil || stamp is NSNull || (stamp is String) else {
                    throw SyncError.invalidCategory(.histories)
                }
                let text = stamp as? String ?? ""
                let date = Self.parseDate(text)
                guard text.isEmpty || date != nil else { throw SyncError.invalidCategory(.histories) }
                return HistoryEntry(room: room, watchedAt: date)
            }
        }
        if selection.categories.contains(.shields), let value = values[.shields] {
            var words = [String]()
            if let shield = value as? [String: Any] {
                for key in ["raw", "keywords"] where shield[key] != nil {
                    words += try Self.strings(shield[key])
                }
                if shield["raw"] != nil || shield["keywords"] != nil { plan.shields = words }
            } else {
                plan.shields = try Self.strings(value)
            }
        }
        if selection.categories.contains(.settings), let value = values[.settings] {
            guard let settings = value as? [String: Any] else { throw SyncError.invalidCategory(.settings) }
            let mapped = try SyncPreferences.nativeValues(settings)
            if !mapped.isEmpty { plan.settings = mapped }
        }
        if selection.categories.contains(.accounts) {
            let accounts = try accountEntries(sites: selection.accountSites ?? Self.accountSites)
            if !accounts.isEmpty { plan.accounts = accounts }
        }
        guard plan.hasData else { throw SyncError.noSelection }
        return plan
    }

    private static func firstValue(_ payload: [String: Any], keys: [String]) -> Any? {
        keys.compactMap { payload[$0] }.first.map { value in
            (value as? [String: Any])?["data"] ?? value
        }
    }

    private static func strings(_ value: Any?) throws -> [String] {
        guard let strings = value as? [String] else { throw SyncError.invalidCategory(.shields) }
        return strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func rooms(_ value: Any, category: SyncCategory,
                              plan: inout SyncImportPlan) throws -> [(RoomDescriptor, [String: Any])] {
        guard let rows = value as? [[String: Any]] else { throw SyncError.invalidCategory(category) }
        var rooms: [(RoomDescriptor, [String: Any])] = []
        for row in rows {
            let site = (row["siteId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let id = ((row["roomId"] as? String) ?? (row["roomId"] as? NSNumber)?.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !site.isEmpty, !id.isEmpty, id != "null" else { throw SyncError.invalidCategory(category) }
            guard sites.contains(site) else {
                plan.skipped += 1
                plan.mergeOnly.insert(category)
                continue
            }
            let name = row["userName"] as? String ?? ""
            let title = row["roomTitle"] as? String ?? ""
            let cover = row["roomCover"] as? String ?? ""
            rooms.append((RoomDescriptor(provider: site, roomId: id,
                                         title: title.isEmpty ? (name.isEmpty ? id : name) : title,
                                         cover: cover.isEmpty ? (row["face"] as? String ?? "") : cover,
                                         userName: name), row))
        }
        return rooms
    }

    static func accountItem(site: String, object: [String: Any]) throws -> [String: Any] {
        guard accountSites.contains(site) else { throw SyncError.invalidCategory(.accounts) }
        var item = object
        if let credentials = object["credentials"] as? [String: Any] {
            guard object["accountType"] as? String == site else { throw SyncError.invalidCategory(.accounts) }
            item = credentials
        }
        item["siteId"] = site
        return item
    }

    private func accountEntries(sites: Set<String>) throws -> [SyncAccount] {
        var items: [[String: Any]] = []
        if let value = values[.accounts] {
            guard let object = value as? [String: Any],
                  let rows = object["items"] as? [[String: Any]] else {
                throw SyncError.invalidCategory(.accounts)
            }
            items = rows
        }
        var entries: [String: SyncAccount] = [:]
        func add(_ slot: String, _ raw: [String: Any]) throws {
            guard entries[slot] == nil, let value = raw["cookie"], !(value is NSNull) else { return }
            guard let cookie = value as? String else { throw SyncError.invalidCategory(.accounts) }
            guard !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard cookie.utf8.count <= 32_768, !cookie.contains("\r"), !cookie.contains("\n") else {
                throw SyncError.invalidCategory(.accounts)
            }
            let expiresAt = (raw["cookieExpiresAt"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue / 1000)
            } ?? Self.parseDate(raw["cookieExpiresAt"] as? String ?? "")
            entries[slot] = SyncAccount(slot: slot, cookie: cookie, kww: raw["kww"] as? String, expiresAt: expiresAt)
        }
        for item in items {
            guard let site = (item["siteId"] as? String)?.lowercased(), sites.contains(site) else { continue }
            if site == "kuaishou", let raw = item["slots"] {
                guard let slots = raw as? [String: [String: Any]] else { throw SyncError.invalidCategory(.accounts) }
                if let slot = slots["primary"] { try add(site, slot) }
                if let slot = slots["secondary"] { try add("kuaishou.secondary", slot) }
            }
            try add(site, item)
        }
        let legacy = ["bilibili": "Bilibili", "douyin": "Douyin", "douyu": "Douyu",
                      "xiaohongshu": "Xiaohongshu", "kuaishou": "Kuaishou"]
        for (site, prefix) in legacy where sites.contains(site) {
            let slots = site == "kuaishou" ? [(site, prefix), ("kuaishou.secondary", "KuaishouSecondary")] : [(site, prefix)]
            for (slot, key) in slots {
                var raw: [String: Any] = [:]
                raw["cookie"] = legacySettings[key + "Cookie"]
                raw["kww"] = legacySettings[key + "Kww"]
                raw["cookieExpiresAt"] = legacySettings[key + "CookieExpiresAt"]
                try add(slot, raw)
            }
        }
        return entries.values.sorted { $0.slot < $1.slot }
    }

    private static func parseDate(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        let normalized = text.replacingOccurrences(of: " ", with: "T")
        if normalized.last != "Z", !normalized.dropFirst(10).contains("+"), !normalized.dropFirst(10).contains("-") {
            let local = DateFormatter()
            local.locale = Locale(identifier: "en_US_POSIX")
            local.timeZone = .current
            local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            let parts = normalized.split(separator: ".", maxSplits: 1)
            guard let first = parts.first, first.count == 19,
                  let base = local.date(from: String(first)) else { return nil }
            guard parts.count > 1 else { return base }
            guard parts[1].utf8.allSatisfy({ (48...57).contains($0) }),
                  let fraction = Double("0." + parts[1]) else { return nil }
            return base.addingTimeInterval(fraction)
        }
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(normalized) { return date }
        return try? Date.ISO8601FormatStyle().parse(normalized)
    }
}

@MainActor
final class SyncImporter {
    typealias PrepareAccounts = @MainActor ([SyncAccount]) async throws -> (@MainActor () throws -> Void)
    private let library: LibraryStore
    private let prepareAccounts: PrepareAccounts?
    private var importing = false

    init(library: LibraryStore, prepareAccounts: PrepareAccounts? = nil) {
        self.library = library
        self.prepareAccounts = prepareAccounts
    }

    func apply(_ plan: SyncImportPlan, overwrite: Bool, confirmed: Bool) async throws {
        guard !overwrite || confirmed else { throw SyncError.confirmationRequired }
        guard !importing else { throw SyncError.busy }
        importing = true
        defer { importing = false }
        try Task.checkCancellation()
        var commitAccounts: (@MainActor () throws -> Void)?
        if let accounts = plan.accounts {
            guard let prepareAccounts else { throw SyncError.accountsUnavailable }
            commitAccounts = try await prepareAccounts(accounts)
        }
        try Task.checkCancellation()
        try library.applySync(plan, overwrite: overwrite, beforeCommit: commitAccounts)
    }
}
