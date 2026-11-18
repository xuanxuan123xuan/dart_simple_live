import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case bilibili
    case huya
    case douyu
    case douyin
    case kuaishou
    case xiaohongshu
}

public struct RoomKey: Codable, Hashable, Sendable {
    public let provider: ProviderID
    public let roomId: String

    public init(provider: ProviderID, roomId: String) {
        self.provider = provider
        self.roomId = roomId
    }
}
