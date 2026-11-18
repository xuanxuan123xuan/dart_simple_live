import CommonCrypto
import Foundation
import SimpleLiveTVOSCore

enum KuaishouDanmaku {
    static func socketFrame(type: UInt64, content: Data) -> Data {
        var frame = ProtoWriter()
        frame.number(1, type)
        frame.bytes(3, content)
        return frame.data
    }

    static func join(token: String, stream: String, expTag: String, attach: String) -> Data {
        var payload = ProtoWriter()
        payload.text(1, token)
        payload.text(2, stream)
        payload.text(5, expTag)
        payload.text(6, attach)
        payload.text(7, String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)))
        return socketFrame(type: 200, content: payload.data)
    }

    static func heartbeat() -> Data {
        var payload = ProtoWriter()
        payload.number(1, UInt64(Date().timeIntervalSince1970 * 1000))
        return socketFrame(type: 1, content: payload.data)
    }

    static func decode(_ bytes: Data, roomID: String) throws -> [DanmakuEvent] {
        let frame = try ProtoMessage(bytes)
        let kind = frame.number(1)
        if kind == 103 { throw LiveProviderError.authenticationRequired }
        guard kind == 310 else { return [] }
        let data = frame.data(3)
        let payload: Data
        switch frame.number(2) {
        case 0, 1: payload = data
        case 2: payload = try DanmakuCompression.inflate(data)
        case 3: payload = try decrypt(data)
        default: return []
        }
        return try ProtoMessage(payload).values(5).prefix(128).compactMap { bytes in
            let comment = try ProtoMessage(bytes)
            let text = comment.text(3)
            guard !text.isEmpty, comment.number(7) != 2 else { return nil }
            let author = try ProtoMessage(comment.data(2)).text(2)
            let colorText = comment.text(6).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            let color = colorText.count == 6 ? Int(colorText, radix: 16) ?? 0xffffff : 0xffffff
            return DanmakuEvent(id: UUID().uuidString, room: RoomKey(provider: .kuaishou, roomId: roomID),
                                userName: author, message: text,
                                color: DanmakuColor(red: (color >> 16) & 255, green: (color >> 8) & 255, blue: color & 255),
                                spans: [.text(text)])
        }
    }

    private static func decrypt(_ payload: Data) throws -> Data {
        guard !payload.isEmpty, payload.count.isMultiple(of: 16) else { throw LiveProviderError.invalidResponse }
        // Wire constants from simple_live_core's existing WebSocket decoder.
        let key = Data("PPbzKKL7NB15leYy".utf8)
        let iv = Data("JRODKJiolJ9xqso0".utf8)
        let capacity = payload.count + 16
        var decoded = Data(count: capacity)
        var length: size_t = 0
        let result = decoded.withUnsafeMutableBytes { output in
            payload.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                input.baseAddress, payload.count, output.baseAddress, capacity, &length)
                    }
                }
            }
        }
        guard result == kCCSuccess else { throw LiveProviderError.invalidResponse }
        return Data(decoded.prefix(length))
    }
}
