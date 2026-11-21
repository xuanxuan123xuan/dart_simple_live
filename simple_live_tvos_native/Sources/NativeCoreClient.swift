import Combine
import Foundation
import SimpleLiveTVOSCore

@MainActor
final class NativeCoreClient: ObservableObject {
    struct PhoneConnection {
        let id = UUID()
        let address: String
    }

    let providers = [
        ProviderDescriptor(id: "bilibili", title: "哔哩哔哩", supportLabel: "扫码登录"),
        ProviderDescriptor(id: "huya", title: "虎牙", supportLabel: "游客观看"),
        ProviderDescriptor(id: "douyu", title: "斗鱼", supportLabel: "扫码登录"),
        ProviderDescriptor(id: "douyin", title: "抖音", supportLabel: "Cookie 登录"),
        ProviderDescriptor(id: "kuaishou", title: "快手", supportLabel: "Cookie 登录"),
        ProviderDescriptor(id: "xiaohongshu", title: "小红书", supportLabel: "手机列表 · 链接进房"),
    ]

    @Published private(set) var accountStatuses: [AccountSlot: AccountStatus] = [:]
    @Published private(set) var xiaohongshuPhone: PhoneConnection?

    private let bilibili: BilibiliService
    private let huya = HuyaService()
    private let douyu: DouyuService
    private let douyin: DouyinService
    private let kuaishou: KuaishouService
    private var xiaohongshu: XiaohongshuService
    private let accountStore: any AccountSessionStore
    private let requestCredentials: AccountRequestCredentials
    private let validateForTesting: ((AccountSlot, AccountCredential) async throws -> AccountCredential)?
    private var hasRestored = false
    private var edits: [AccountSlot: UUID] = [:]
    private var restorations: [AccountSlot: UUID] = [:]
    private var accountRevisions: [AccountSlot: UUID] = [:]

    let accountSlots: [AccountSlot] = AccountSlot.allCases

    init(accountStore: (any AccountSessionStore)? = nil,
         requestCredentials: AccountRequestCredentials = AccountRequestCredentials(),
         validateForTesting: ((AccountSlot, AccountCredential) async throws -> AccountCredential)? = nil) {
        self.accountStore = accountStore ?? KeychainSessionStore()
        self.requestCredentials = requestCredentials
        self.validateForTesting = validateForTesting
        bilibili = BilibiliService(accounts: requestCredentials)
        douyu = DouyuService(accounts: requestCredentials)
        xiaohongshu = XiaohongshuService(accounts: requestCredentials)
        kuaishou = KuaishouService(accounts: requestCredentials)
        douyin = DouyinService(accounts: requestCredentials)
    }

    var loginProviders: [ProviderDescriptor] {
        providers.filter { $0.id == "bilibili" || $0.id == "douyu" }
    }

    var authenticated: Set<String> {
        Set(accountStatuses.compactMap { $0.value == .verified ? $0.key.rawValue : nil })
    }

    func accountStatus(_ slot: AccountSlot) -> AccountStatus {
        accountStatuses[slot, default: .signedOut]
    }

    func start() async {
        guard !hasRestored else { return }
        hasRestored = true
        await withTaskGroup(of: Void.self) { group in
            for slot in accountSlots {
                group.addTask { await self.restoreAccount(slot) }
            }
        }
    }

    func restoreAccount(_ slot: AccountSlot) async {
        guard accountSlots.contains(slot), restorations[slot] == nil,
              requestCredentials.credential(for: slot) == nil else { return }
        let request = UUID()
        restorations[slot] = request
        defer {
            if restorations[slot] == request { restorations[slot] = nil }
        }
        do {
            guard let stored = try accountStore.read(slot) else {
                accountStatuses[slot] = .signedOut
                return
            }
            accountStatuses[slot] = .checking
            let validated = try await validateAccount(stored, for: slot)
            guard restorations[slot] == request else { return }
            try Task.checkCancellation()
            if stored != validated.credential { try accountStore.save(validated.credential, for: slot) }
            publish(validated.credential, for: slot, status: validated.status)
        } catch {
            guard restorations[slot] == request else { return }
            switch error {
            case LiveProviderError.authenticationRequired, AccountCredentialError.invalidFormat:
                accountStatuses[slot] = .invalid
            default:
                accountStatuses[slot] = .unavailable
            }
        }
    }

    func service(_ provider: String) throws -> any LiveProviderService {
        switch ProviderID(rawValue: provider) {
        case .bilibili: bilibili
        case .huya: huya
        case .douyu: douyu
        case .douyin: douyin
        case .kuaishou: kuaishou
        case .xiaohongshu: xiaohongshu
        default: throw LiveProviderError.unsupported
        }
    }

    func connectXiaohongshuPhone(address: String, code: String) async throws {
        let phone = try XiaohongshuPhoneDiscovery(address: address, code: code)
        _ = try await phone.categories()
        try Task.checkCancellation()
        xiaohongshu = XiaohongshuService(accounts: requestCredentials, phone: phone)
        xiaohongshuPhone = PhoneConnection(address: phone.address)
    }

    func disconnectXiaohongshuPhone() {
        xiaohongshu = XiaohongshuService(accounts: requestCredentials)
        xiaohongshuPhone = nil
    }

    func resolveRoomInput(_ input: String, provider: String) async throws -> RoomDescriptor {
        let target = try await LiveRoomInput { try await ProviderHTTP.publicShare.shareLocation($0) }
            .resolve(input, defaultProvider: provider)
        if target.isDouyinReflow {
            return try await douyin.resolveReflow(target.roomID, secUserID: target.douyinUserID)
        }
        return try await service(target.provider).resolveRoom(target.roomID)
    }

    func danmaku(for room: RoomDescriptor) throws -> AsyncThrowingStream<DanmakuEvent, Error> {
        guard let source = try service(room.provider) as? any DanmakuService else {
            throw LiveProviderError.unsupported
        }
        return source.danmaku(roomId: room.roomId)
    }

    func loginChallenge(provider: String) async throws -> LoginChallenge {
        try await accountService(provider).makeLoginChallenge()
    }

    func pollLogin(_ challenge: LoginChallenge, provider: String) async throws -> LoginResult {
        try await accountService(provider).pollLogin(challenge)
    }

    func finishLogin(cookie: String, provider: String) async throws {
        guard let slot = AccountSlot(rawValue: provider) else { throw LiveProviderError.unsupported }
        try await saveAccount(AccountCredential(cookie: cookie), for: slot)
    }

    func saveAccount(_ credential: AccountCredential, for slot: AccountSlot) async throws {
        guard accountSlots.contains(slot) else { throw LiveProviderError.unsupported }
        let request = UUID()
        edits[slot] = request
        defer {
            if edits[slot] == request { edits[slot] = nil }
        }
        let validated = try await validateAccount(credential, for: slot)
        try Task.checkCancellation()
        guard edits[slot] == request else { throw CancellationError() }
        try applyAccounts([slot: validated])
    }

    func exportSyncAccounts() throws -> [SyncAccount] {
        try accountSlots.compactMap { slot in
            guard let credential = try accountStore.read(slot) else { return nil }
            return SyncAccount(slot: slot.rawValue, cookie: credential.cookie,
                               kww: credential.kww, expiresAt: credential.expiresAt)
        }
    }

    func signOut(provider: String) async throws {
        guard let slot = AccountSlot(rawValue: provider) else { throw LiveProviderError.unsupported }
        try signOut(slot)
    }

    func signOut(_ slot: AccountSlot) throws {
        guard accountSlots.contains(slot) else { throw LiveProviderError.unsupported }
        try accountStore.clear(slot)
        edits[slot] = nil
        restorations[slot] = nil
        accountRevisions[slot] = UUID()
        publish(nil, for: slot, status: .signedOut)
    }

    /// Validates selected credentials and returns a synchronous commit for the sync importer.
    /// Unselected slots are preserved and all selected credentials are written in one Keychain update.
    func prepareAccountImport(_ entries: [AccountSlot: AccountCredential]) async throws -> (@MainActor () throws -> Void) {
        let snapshots = try entries.keys.map { slot in
            (slot: slot, credential: try accountStore.read(slot), edit: edits[slot], revision: accountRevisions[slot])
        }
        var validated: [AccountSlot: ValidatedAccount] = [:]
        for slot in accountSlots {
            guard let credential = entries[slot] else { continue }
            try Task.checkCancellation()
            validated[slot] = try await validateAccount(credential, for: slot)
        }
        try Task.checkCancellation()
        try requireDistinctKuaishouAccounts(validated.mapValues(\.credential))
        return { [self] in
            try Task.checkCancellation()
            for state in snapshots {
                guard edits[state.slot] == state.edit, accountRevisions[state.slot] == state.revision,
                      try accountStore.read(state.slot) == state.credential else {
                    throw AccountCredentialError.changedDuringImport
                }
            }
            try applyAccounts(validated)
        }
    }

    private func applyAccounts(_ accounts: [AccountSlot: ValidatedAccount]) throws {
        guard !accounts.isEmpty else { return }
        let credentials = accounts.mapValues(\.credential)
        try requireDistinctKuaishouAccounts(credentials)
        try accountStore.saveBatch(credentials)
        for slot in accounts.keys {
            edits[slot] = nil
            restorations[slot] = nil
            accountRevisions[slot] = UUID()
        }
        requestCredentials.set(credentials)
        accountStatuses.merge(accounts.mapValues(\.status)) { _, new in new }
    }

    private func requireDistinctKuaishouAccounts(_ replacements: [AccountSlot: AccountCredential]) throws {
        guard replacements.keys.contains(where: \.isKuaishou),
              let primary = try replacements[.kuaishou] ?? accountStore.read(.kuaishou),
              let secondary = try replacements[.kuaishouSecondary] ?? accountStore.read(.kuaishouSecondary),
              ProviderAccountValidation.sameKuaishouAccount(primary, secondary) else { return }
        throw AccountCredentialError.duplicateKuaishouAccount
    }

    private func validateAccount(_ credential: AccountCredential, for slot: AccountSlot) async throws -> ValidatedAccount {
        switch slot {
        case .douyin: return try ProviderAccountValidation.douyin(credential)
        case .kuaishou, .kuaishouSecondary: return try ProviderAccountValidation.kuaishou(credential)
        case .xiaohongshu: return try ProviderAccountValidation.xiaohongshu(credential)
        case .bilibili, .douyu:
            let cookie = try AccountCookie(credential.cookie)
            let normalized = AccountCredential(cookie: cookie.header)
            if let validateForTesting {
                let validated = try await validateForTesting(slot, normalized)
                return ValidatedAccount(credential: validated, status: .verified)
            }
            if slot == .douyu, let configured = ProviderAccountValidation.douyuWithoutRefresh(cookie) {
                return configured
            }
            let validated = try await accountService(slot.rawValue).validate(normalized.cookie)
            return ValidatedAccount(credential: AccountCredential(cookie: validated), status: .verified)
        }
    }

    private func publish(_ credential: AccountCredential?, for slot: AccountSlot, status: AccountStatus) {
        requestCredentials.set(credential, for: slot)
        accountStatuses[slot] = status
    }

    private func accountService(_ provider: String) throws -> any ProviderSessionService {
        guard let service = try service(provider) as? any ProviderSessionService else { throw LiveProviderError.unsupported }
        return service
    }
}

/// Each results view owns a store so navigation and overlapping requests do not share pagination.
@MainActor
final class RoomResultsStore: ObservableObject {
    struct Query: Hashable {
        let provider: String
        let listing: RoomListing
        let retry: Int
    }

    enum Status: Equatable {
        case idle, loading, loaded, failed(String)
    }

    @Published private(set) var query: Query?
    @Published private(set) var rooms: [RoomDescriptor] = []
    @Published private(set) var status = Status.idle
    @Published private(set) var hasMore = false
    private var page = 0
    private var generation = 0

    func load(_ query: Query, next: Bool = false, fetch: (Int) async throws -> RoomPage) async {
        if next {
            guard self.query == query, hasMore, status != .loading else { return }
        } else {
            guard self.query != query || status == .idle || (status == .loading && page == 0) else { return }
            self.query = query
            rooms = []
            hasMore = false
            page = 0
        }

        generation += 1
        let request = generation
        let nextPage = page + 1
        status = .loading
        defer {
            if generation == request, status == .loading { status = next ? .loaded : .idle }
        }

        do {
            let result = try await fetch(nextPage)
            guard generation == request, !Task.isCancelled else { return }
            var seen = Set(rooms.map(\.key))
            rooms += result.rooms.filter { seen.insert($0.key).inserted }
            hasMore = result.hasMore
            page = nextPage
            status = .loaded
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            status = .failed(error.localizedDescription)
        }
    }
}
