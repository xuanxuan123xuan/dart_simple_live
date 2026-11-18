import Foundation
import SimpleLiveTVOSCore

enum DouyinDanmaku {
    static func heartbeat() -> Data {
        var frame = ProtoWriter()
        frame.text(7, "hb")
        return frame.data
    }

    static func decode(_ bytes: Data, webID: String) throws -> (events: [DanmakuEvent], reply: Data?) {
        let frame = try ProtoMessage(bytes)
        var payload = frame.data(8)
        if payload.isEmpty { return ([], nil) }
        if frame.text(6) == "gzip" || payload.starts(with: [0x1f, 0x8b]) {
            payload = try DanmakuCompression.inflate(payload)
        }
        let result = try ProtoMessage(payload)
        var response: Data?
        if result.number(9) != 0 {
            var ack = ProtoWriter()
            ack.number(2, frame.number(2))
            ack.text(7, "ack")
            ack.bytes(8, result.data(5))
            response = ack.data
        }
        let events = try result.values(1).prefix(128).compactMap { bytes -> DanmakuEvent? in
            let message = try ProtoMessage(bytes)
            guard message.text(1) == "WebcastChatMessage" else { return nil }
            let chat = try ProtoMessage(message.data(2))
            let content = chat.text(3)
            guard !content.isEmpty else { return nil }
            let name = try ProtoMessage(chat.data(2)).text(3)
            let msgID = message.number(3)
            let id = msgID == 0 ? UUID().uuidString : String(msgID)
            return DanmakuEvent(id: id, room: RoomKey(provider: .douyin, roomId: webID), userName: name, message: content,
                                color: DanmakuColor(red: 255, green: 255, blue: 255), spans: [.text(content)])
        }
        return (events, response)
    }
}
