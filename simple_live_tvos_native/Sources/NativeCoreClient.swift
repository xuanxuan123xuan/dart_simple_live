import Combine
import Foundation
import SimpleLiveTVOSCore

@MainActor
final class NativeCoreClient: ObservableObject {
    let providers = [
        ProviderDescriptor(id: "bilibili", title: "哔哩哔哩", supportLabel: "扫码登录"),
        ProviderDescriptor(id: "huya", title: "虎牙", supportLabel: "游客观看"),
        ProviderDescriptor(id: "douyu", title: "斗鱼", supportLabel: "扫码登录"),
        ProviderDescriptor(id: "douyin", title: "抖音", supportLabel: "游客观看"),
        ProviderDescriptor(id: "kuaishou", title: "快手", supportLabel: "游客观看"),
        ProviderDescriptor(id: "xiaohongshu", title: "小红书", supportLabel: "链接进房"),
    ]

    @Published private(set) var rooms: [RoomDescriptor] = []
    @Published private(set) var categories: [CategoryDescriptor] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var authenticated: Set<String> = []

    private let bilibili = BilibiliService()
    private let huya = HuyaService()
    private let douyu = DouyuService()
    private let douyin = DouyinService()
    private let kuaishou = KuaishouService()
    private let xiaohongshu = XiaohongshuService()
    private let keychain = KeychainSessionStore()
    private var roomRequest = 0
    private var categoryRequest = 0
    private var page = 0
    private var context: (provider: String, listing: RoomListing)?
    private var hasRestored = false
    private var sessionChanges: Set<String> = []

    var loginProviders: [ProviderDescriptor] {
        providers.filter { $0.id == "bilibili" || $0.id == "douyu" }
    }

    func start() async {
        guard !hasRestored else { return }
        hasRestored = true
        for provider in loginProviders where !sessionChanges.contains(provider.id) {
            let id = provider.id
            do {
                guard let cookie = try keychain.readCookie(provider: id) else { continue }
                let session = try accountService(id)
                try await session.validate(cookie)
                guard !sessionChanges.contains(id) else { continue }
                await session.setVerifiedCookie(cookie)
                if !sessionChanges.contains(id) { authenticated.insert(id) }
            } catch {
                continue
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

    func danmaku(for room: RoomDescriptor) throws -> AsyncThrowingStream<DanmakuEvent, Error> {
        guard let source = try service(room.provider) as? any DanmakuService else {
            throw LiveProviderError.unsupported
        }
        return source.danmaku(roomId: room.roomId)
    }

    func loadCategories(provider: String) async {
        categoryRequest += 1
        let request = categoryRequest
        categories = []
        do {
            let result = try await service(provider).categories()
            guard request == categoryRequest, !Task.isCancelled else { return }
            categories = result
        } catch {
            return
        }
    }

    func isCurrentRoomListing(provider: String, listing: RoomListing) -> Bool {
        context?.provider == provider && context?.listing == listing
    }

    func loadRooms(provider: String, listing: RoomListing, append: Bool = false) async {
        if append {
            guard !isLoading, hasMore, isCurrentRoomListing(provider: provider, listing: listing) else { return }
        } else {
            context = (provider, listing)
            rooms = []
            hasMore = false
            page = 0
        }
        roomRequest += 1
        let request = roomRequest
        isLoading = true
        errorMessage = nil
        defer { if request == roomRequest { isLoading = false } }

        do {
            if case .search = listing, !append { try await Task.sleep(for: .milliseconds(350)) }
            let nextPage = page + 1
            let result = try await service(provider).rooms(in: listing, page: nextPage)
            guard request == roomRequest, !Task.isCancelled else { return }
            var seen = Set(rooms.map(\.key))
            rooms.append(contentsOf: result.rooms.filter { seen.insert($0.key).inserted })
            hasMore = result.hasMore
            page = nextPage
        } catch {
            guard request == roomRequest, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loginChallenge(provider: String) async throws -> LoginChallenge {
        try await accountService(provider).makeLoginChallenge()
    }

    func pollLogin(_ challenge: LoginChallenge, provider: String) async throws -> LoginResult {
        try await accountService(provider).pollLogin(challenge)
    }

    func finishLogin(cookie: String, provider: String) async throws {
        let session = try accountService(provider)
        try await session.validate(cookie)
        try Task.checkCancellation()
        try keychain.saveCookie(provider: provider, cookie: cookie)
        sessionChanges.insert(provider)
        await session.setVerifiedCookie(cookie)
        authenticated.insert(provider)
    }

    func signOut(provider: String) async throws {
        let session = try accountService(provider)
        try keychain.clearCookie(provider: provider)
        sessionChanges.insert(provider)
        await session.setVerifiedCookie(nil)
        authenticated.remove(provider)
    }

    private func accountService(_ provider: String) throws -> any ProviderSessionService {
        guard let service = try service(provider) as? any ProviderSessionService else { throw LiveProviderError.unsupported }
        return service
    }
}
