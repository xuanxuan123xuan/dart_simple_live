import Foundation
import ZIPFoundation

enum SyncArchive {
    static let profileName = "SimpleLive_Profile_v4.json"
    private static let profiles = [profileName, "SimpleLive_Profile_v3.json", "SimpleLive_Profile_v2.json"]
    private static let settings = "SimpleLive_Settings.json"
    private static let legacyLists: [String: SyncCategory] = [
        "SimpleLive_follows.json": .follows,
        "SimpleLive_histories.json": .histories,
        "SimpleLive_blocked_word.json": .shields,
    ]
    private static let legacyAccounts: [String: String] = [
        "SimpleLive_bilibili_account.json": "bilibili",
        "SimpleLive_douyin_account.json": "douyin",
        "SimpleLive_douyu_account.json": "douyu",
        "SimpleLive_xiaohongshu_account.json": "xiaohongshu",
    ]

    static func decode(_ data: Data, selection: SyncSelection) throws -> SyncProfile {
        guard data.count <= SyncProfile.maxBytes else { throw SyncError.tooLarge }
        let archive = try Archive(data: data, accessMode: .read)
        var files: [String: Entry] = [:]
        for (index, entry) in archive.enumerated() {
            guard index < 128 else { throw SyncError.invalidArchive }
            let name = entry.path
            guard profiles.contains(name) || legacyLists[name] != nil || legacyAccounts[name] != nil || name == settings
            else { continue }
            guard entry.type == .file, files[name] == nil else { throw SyncError.invalidArchive }
            files[name] = entry
        }
        var total = 0
        func extract(_ entry: Entry) throws -> Data {
            guard entry.uncompressedSize <= UInt64(SyncProfile.maxBytes - total) else { throw SyncError.tooLarge }
            var content = Data()
            let checksum = try archive.extract(entry) { buffer in
                guard buffer.count <= SyncProfile.maxBytes - total - content.count else { throw SyncError.tooLarge }
                content.append(buffer)
            }
            guard content.count == entry.uncompressedSize, checksum == entry.checksum else { throw SyncError.invalidArchive }
            total += content.count
            return content
        }
        if let profile = profiles.compactMap({ files[$0] }).first {
            return try SyncProfile(data: extract(profile))
        }
        guard !files.isEmpty else { throw SyncError.invalidArchive }
        func legacyData(_ entry: Entry) throws -> Any {
            guard let object = try JSONSerialization.jsonObject(with: extract(entry)) as? [String: Any],
                  let value = object["data"] else { throw SyncError.invalidArchive }
            return value
        }
        var profile = SyncProfile()
        for (name, category) in legacyLists where selection.categories.contains(category) {
            if let entry = files[name] { profile.values[category] = try legacyData(entry) }
        }
        if selection.categories.contains(.accounts) {
            var items: [[String: Any]] = []
            for (name, site) in legacyAccounts where (selection.accountSites ?? SyncProfile.accountSites).contains(site) {
                guard let entry = files[name] else { continue }
                guard let object = try legacyData(entry) as? [String: Any] else { throw SyncError.invalidArchive }
                items.append(try SyncProfile.accountItem(site: site, object: object))
            }
            if !items.isEmpty { profile.values[.accounts] = ["items": items] }
        }
        if selection.categories.contains(.accounts) || selection.categories.contains(.settings),
           let entry = files[settings] {
            guard let object = try legacyData(entry) as? [String: Any] else { throw SyncError.invalidArchive }
            profile.legacySettings = object
            profile.values[.settings] = object
        }
        return profile
    }

    static func encode(_ plan: SyncImportPlan, now: Date = Date()) throws -> Data {
        let dateFormatter = ISO8601DateFormatter()
        func timestamp(_ date: Date) -> String {
            guard let value = Int64(exactly: (date.timeIntervalSince1970 * 1_000_000).rounded()) else { return "" }
            let fraction = (value % 1_000_000 + 1_000_000) % 1_000_000
            let whole = Date(timeIntervalSince1970: floor(Double(value) / 1_000_000))
            let base = dateFormatter.string(from: whole).dropLast()
            return base + String(format: ".%06dZ", Int32(fraction))
        }
        let stamp = timestamp(now)
        func roomFields(_ room: RoomDescriptor) -> [String: Any] {
            ["id": "\(room.provider)_\(room.roomId)", "siteId": room.provider, "roomId": room.roomId,
             "userName": room.userName, "face": room.cover]
        }
        var profile: [String: Any] = ["schema": "simple_live_profile", "schemaVersion": 4, "platform": "tvos",
                                     "exportedAt": stamp]
        var legacy: [SyncCategory: Any] = [:]
        if let favorites = plan.favorites {
            let rows = favorites.map { entry in
                roomFields(entry.room).merging(["roomTitle": entry.room.title, "roomCover": entry.room.cover,
                                                "addTime": stamp, "isSpecialFollow": entry.isPriority]) { _, value in value }
            }
            profile["followUsers"] = rows
            legacy[.follows] = rows
        }
        if let histories = plan.histories {
            let rows = histories.map { entry in
                roomFields(entry.room).merging(["updateTime": entry.watchedAt.map(timestamp) ?? ""]) {
                    _, value in value
                }
            }
            profile["histories"] = rows
            legacy[.histories] = rows
        }
        if let shields = plan.shields {
            profile["danmuShield"] = ["keywords": shields, "raw": shields]
            legacy[.shields] = shields
        }
        if let settings = plan.settings { profile["settings"] = SyncPreferences.dartValues(settings) }
        if let accounts = plan.accounts {
            var items: [[String: Any]] = []
            var kuaishou: [String: [String: Any]] = [:]
            for account in accounts {
                var fields: [String: Any] = ["cookie": account.cookie]
                fields["kww"] = account.kww
                fields["cookieExpiresAt"] = account.expiresAt.flatMap {
                    Int64(exactly: ($0.timeIntervalSince1970 * 1000).rounded())
                }
                switch account.slot {
                case "kuaishou": kuaishou["primary"] = fields
                case "kuaishou.secondary": kuaishou["secondary"] = fields
                default:
                    fields["siteId"] = account.slot
                    items.append(fields)
                }
            }
            if !kuaishou.isEmpty { items.append(["siteId": "kuaishou", "slots": kuaishou]) }
            profile["accounts"] = ["items": items]
        }

        let archive = try Archive(accessMode: .create)
        var plainBytes = 0
        func add(_ name: String, _ object: Any) throws {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            plainBytes += data.count
            guard plainBytes <= SyncProfile.maxBytes else { throw SyncError.tooLarge }
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count),
                                 compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        try add(profileName, profile)
        for (name, category) in legacyLists {
            if let list = legacy[category] { try add(name, ["data": list]) }
        }
        if let value = profile["settings"] { try add(settings, ["data": value]) }
        guard let data = archive.data else { throw SyncError.invalidArchive }
        guard data.count <= SyncProfile.maxBytes else { throw SyncError.tooLarge }
        return data
    }
}
