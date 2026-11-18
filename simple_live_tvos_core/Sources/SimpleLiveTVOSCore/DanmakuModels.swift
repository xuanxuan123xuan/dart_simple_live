import Foundation

public struct DanmakuColor: Codable, Equatable, Sendable {
    public let red: Int
    public let green: Int
    public let blue: Int

    public init(red: Int, green: Int, blue: Int) {
        self.red = min(max(red, 0), 255)
        self.green = min(max(green, 0), 255)
        self.blue = min(max(blue, 0), 255)
    }
}

public enum DanmakuSpan: Codable, Equatable, Sendable {
    case text(String)
    case image(url: URL, fallbackText: String?)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case fallbackText
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "text":
            self = .text(try container.decode(String.self, forKey: .value))
        case "image":
            self = .image(
                url: try container.decode(URL.self, forKey: .value),
                fallbackText: try container.decodeIfPresent(String.self, forKey: .fallbackText)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown danmaku span kind"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode("text", forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .image(url, fallbackText):
            try container.encode("image", forKey: .kind)
            try container.encode(url, forKey: .value)
            try container.encodeIfPresent(fallbackText, forKey: .fallbackText)
        }
    }
}

public struct DanmakuEvent: Codable, Equatable, Sendable {
    public let id: String
    public let room: RoomKey
    public let userName: String
    public let message: String
    public let color: DanmakuColor
    public let spans: [DanmakuSpan]

    public init(
        id: String,
        room: RoomKey,
        userName: String,
        message: String,
        color: DanmakuColor,
        spans: [DanmakuSpan] = []
    ) {
        self.id = id
        self.room = room
        self.userName = userName
        self.message = message
        self.color = color
        self.spans = spans
    }
}
