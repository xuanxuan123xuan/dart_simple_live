import Foundation
import SimpleLiveTVOSCore
import XCTest
@testable import SimpleLiveTVOS

final class ProviderParsingTests: XCTestCase {
    func testDouyinCategoryTreePreservesThreeLevelsAndParentKeys() throws {
        let fixture = #"""
            {"catalog":[{"partition":{"id_str":"1","type":1,"title":"游戏"},"sub_partition":[
                {"partition":{"id":2,"type":2,"title":"主机"},"sub_partition":[
                    {"partition":{"id":3,"type":3,"title":"动作"}},
                    {"partition":{"id":3,"type":3,"title":"重复"}}
                ]}
            ]}]}
            """#
        let data = try JSONObject.decode(Data(fixture.utf8))
        let roots = DouyinService.parseCategories(data.objects("catalog"))
        let root = try XCTUnwrap(roots.first)
        let branch = try XCTUnwrap(root.children.first)
        XCTAssertTrue(root.canBrowseRooms)
        XCTAssertEqual(branch.parentId, "1,1")
        XCTAssertEqual(branch.children.map(\.name), ["动作"])
        XCTAssertEqual(branch.children.first?.parentId, "2,2")
    }

    func testAnchorResultPreservesProviderRoomIdentityAndLiveStatus() throws {
        let payload = try JSONObject.decode(Data(#"{"roomid":25,"uname":"<em>直播</em>昵称","uface":"//images.example/host.png","is_live":false}"#.utf8))
        let anchor = try XCTUnwrap(RoomDescriptor.anchor(provider: "bilibili", id: payload.text("roomid"),
            name: payload.text("uname"), avatar: payload.text("uface"), isLive: payload.bool("is_live")))
        XCTAssertEqual(anchor.key, "bilibili:25")
        XCTAssertEqual(anchor.title, "直播昵称")
        XCTAssertEqual(anchor.cover, "https://images.example/host.png")
        XCTAssertEqual(anchor.isLive, false)
        XCTAssertNil(payload.bool("unknown"))
        XCTAssertNil(RoomDescriptor.anchor(provider: "bilibili", id: "null", name: "主播", avatar: "", isLive: true))
    }

    func testSSRDataPreservesQuotedUndefinedAndBalancesNestedObjects() throws {
        let page = #"<script>window.__INITIAL_STATE__ = {"title":"undefined and }","body":{"missing":undefined}}</script>"#
        let state = try EmbeddedPageData.initialState(in: page)
        XCTAssertEqual(state.text("title"), "undefined and }")
        XCTAssertTrue(state["body"].fields["missing"] is NSNull)
    }

    func testLiveRoomInputRoutesShareTextAndBareRoomNumbers() async throws {
        let parser = LiveRoomInput { _ in throw LiveProviderError.invalidRoom }
        let fixtures = [
            ("看看这个直播 https://live.bilibili.com/52？", "douyu", "bilibili", "52"),
            ("https://www.douyin.com/follow/live/987", "bilibili", "douyin", "987"),
            ("https://www.douyu.com/topic/game?rid=63", "huya", "douyu", "63"),
            ("https://live.kuaishou.com/u/aB_9", "huya", "kuaishou", "aB_9"),
            ("https://live-room.xiaohongshu.com/hina/livestream/123456789/0", "huya", "xiaohongshu", "123456789"),
            ("  76  ", "huya", "huya", "76"),
        ]
        for (input, fallback, provider, id) in fixtures {
            let target = try await parser.resolve(input, defaultProvider: fallback)
            XCTAssertEqual(target, LiveRoomTarget(provider: provider, roomID: id))
        }
        let reflow = try await parser.resolve("https://webcast.amemv.com/reflow/12345?sec_user_id=abc", defaultProvider: "huya")
        XCTAssertTrue(reflow.isDouyinReflow)
        XCTAssertEqual(reflow.douyinUserID, "abc")
    }

    func testLiveRoomInputRestrictsRedirectsAndRejectsUntrustedLinks() async throws {
        let short = URL(string: "https://v.kuaishou.com/demo")!
        var redirects: [URL] = []
        let parser = LiveRoomInput { url in
            redirects.append(url)
            return URL(string: "https://m.chenzhongtech.com/fw/live/host9")!
        }
        let result = try await parser.resolve(short.absoluteString, defaultProvider: "bilibili")
        XCTAssertEqual(result, LiveRoomTarget(provider: "kuaishou", roomID: "host9"))
        XCTAssertEqual(redirects, [short])

        let invalid = ["https://live.bilibili.com.example/123", "https://user@live.bilibili.com/123",
                       "https://live.bilibili.com:8000/123", "https://www.douyin.com/video/123",
                       "https://live.kuaishou.com/u/ab%2Fcd"]
        for link in invalid {
            do {
                _ = try await parser.resolve(link, defaultProvider: "bilibili")
                XCTFail("Accepted invalid link: \(link)")
            } catch LiveProviderError.invalidRoom {}
        }
        XCTAssertEqual(redirects.count, 1)

        let crossPlatform = LiveRoomInput { _ in URL(string: "https://b23.tv/another")! }
        do {
            _ = try await crossPlatform.resolve(short.absoluteString, defaultProvider: "bilibili")
            XCTFail("Short link redirected to an unrelated platform")
        } catch LiveProviderError.invalidRoom {}

        var hops = 0
        let looping = LiveRoomInput { url in hops += 1; return url }
        do {
            _ = try await looping.resolve(short.absoluteString, defaultProvider: "bilibili")
            XCTFail("Short link exceeded redirect limit")
        } catch LiveProviderError.invalidRoom {}
        XCTAssertEqual(hops, 5)
    }

    func testRoomLinksRejectUntrustedHostsAndPathTraversal() throws {
        XCTAssertEqual(try normalizedRoomID("https://live.bilibili.com/123?from=share", hosts: ["live.bilibili.com"]), "123")
        XCTAssertThrowsError(try normalizedRoomID("https://live.bilibili.com.example/123", hosts: ["live.bilibili.com"]))
        XCTAssertThrowsError(try normalizedRoomID("../123", hosts: ["live.bilibili.com"]))
    }

    func testBilibiliFramesAcceptMultipleMessagesAndStopAtMalformedFrame() throws {
        let room = RoomKey(provider: .bilibili, roomId: "123")
        let event = Data(#"{"cmd":"DANMU_MSG","info":[[0,0,0,65280],"你好",[1,"主播"]]}"#.utf8)
        var frames = BilibiliPacket.make(operation: 5, body: event)
        frames.append(BilibiliPacket.make(operation: 5, body: event))
        frames.append(Data(repeating: 0, count: 16))
        let messages = BilibiliPacket.messages(frames, room: room)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?.message, "你好")
        XCTAssertEqual(messages.first?.room, room)
        XCTAssertEqual(messages.first?.color.green, 255)
    }

    func testDouyuPacketUsesUTF8ByteLengthAndDecodesSTT() {
        let room = RoomKey(provider: .douyu, roomId: "123")
        let packet = DouyuPackets.make("type@=chatmsg/dms@=1/nn@=测试/txt@=甲@S乙@A丙/")
        let messages = DouyuPackets.messages(packet, room: room)
        XCTAssertEqual(messages.first?.message, "甲/乙@丙")
        XCTAssertEqual(messages.first?.userName, "测试")
        XCTAssertTrue(DouyuPackets.messages(Data(packet.dropLast()), room: room).isEmpty)
    }

    func testDouyuChatUsesOfficialEmojiThenTwemojiAndKeepsUnknownText() throws {
        let room = RoomKey(provider: .douyu, roomId: "123")
        let content = "😀斗鱼[大笑][未来表情][笑哭][大笑]收尾"
        let packet = DouyuPackets.make("type@=chatmsg/dms@=1/txt@=\(content)/")
        let event = try XCTUnwrap(DouyuPackets.messages(packet, room: room).first)
        let official = try XCTUnwrap(URL(string: "https://shark2.douyucdn.cn/front-publish/live-next-player-aside-master/assets/images/daxiao_1d13a5a.png"))
        let common = try XCTUnwrap(URL(string: "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f602.png"))
        XCTAssertEqual(event.message, content)
        XCTAssertEqual(event.spans, [.text("😀斗鱼"), .image(url: official, fallbackText: "[大笑]"),
                                     .text("[未来表情]"), .image(url: common, fallbackText: "[笑哭]"),
                                     .image(url: official, fallbackText: "[大笑]"), .text("收尾")])
        XCTAssertTrue(DanmakuStickerURL.permits(official))
        XCTAssertTrue(DanmakuStickerURL.permits(common))
        XCTAssertNil(DanmakuStickerURL.bilibili(official.absoluteString))
        XCTAssertFalse(DanmakuStickerURL.permits(URL(string: "https://cdn.jsdelivr.net/npm/unrelated/image.png")!))
        XCTAssertFalse(DanmakuStickerURL.permits(URL(string: "https://shark2.douyucdn.cn.example.org/a.png")!))
    }

    func testHuyaChatUsesBothOfficialCDNsAndTwemojiFallback() throws {
        func byteList(tag: UInt8, payload: Data) -> Data {
            Data([tag << 4 | 13, 0, 0, UInt8(payload.count)]) + payload
        }
        let content = "虎牙[大笑][动漫哇][未来表情][哈哈]"
        let notice = Data([0x36, UInt8(content.utf8.count)]) + Data(content.utf8)
        let push = Data([0x11, 0x05, 0x78]) + byteList(tag: 2, payload: notice)
        let frame = Data([0, 7]) + byteList(tag: 1, payload: push)
        let event = try XCTUnwrap(HuyaDanmaku.decode(frame, roomID: "123"))
        let official = try XCTUnwrap(URL(string: "https://cdnfile2.msstatic.com/cdnfile/material_manage/web_base_material_16141715551855_pic.png"))
        let animation = try XCTUnwrap(URL(string: "https://materials-g-ai.msstatic.com/banshen/prod/banshen_00226/stickers/aiwa/aiwa%4056x48.png"))
        let common = try XCTUnwrap(URL(string: "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f604.png"))
        XCTAssertEqual(event.room, RoomKey(provider: .huya, roomId: "123"))
        XCTAssertEqual(event.message, content)
        XCTAssertEqual(event.spans, [.text("虎牙"), .image(url: official, fallbackText: "[大笑]"),
                                     .image(url: animation, fallbackText: "[动漫哇]"), .text("[未来表情]"),
                                     .image(url: common, fallbackText: "[哈哈]")])
        XCTAssertFalse(DanmakuStickerURL.permits(URL(string: "https://unrelated.msstatic.com/a.png")!))
    }

    func testKuaishouChatUsesMobileEmojiAndAliasesAndStripsMalformedTail() throws {
        let prefix = "快手[奸笑][未来表情][ILOVEU][點讚]"
        let truncated = Data((prefix + "[新").utf8) + Data([0xe5, 0x88])
        let events = try KuaishouDanmaku.decode(kuaishouFrame([truncated]), roomID: "123")
        let event = try XCTUnwrap(events.first)
        let grin = try XCTUnwrap(URL(string: "https://p4-plat.wsbkwai.com/kimg/bs2/emotion/CigxNzA0Nzc2MDU5ODE2dGhpcmRfcGFydHlfczEyOTY3NDgwNTIucG5nEIfN1y8.webp"))
        let love = try XCTUnwrap(URL(string: "https://p4-plat.wsbkwai.com/kimg/bs2/emotion/CigxNzM1MTIwMDYyODIydGhpcmRfcGFydHlfczIwNDA2NzY0ODcucG5nEIfN1y8.webp"))
        let like = try XCTUnwrap(URL(string: "https://p4-plat.wsbkwai.com/kimg/bs2/emotion/CigxNzA0NzAxNzczNzQ1dGhpcmRfcGFydHlfczEyOTU5NjUzODIucG5nEIfN1y8.webp"))
        XCTAssertEqual(event.message, prefix)
        XCTAssertEqual(event.spans, [.text("快手"), .image(url: grin, fallbackText: "[奸笑]"), .text("[未来表情]"),
                                     .image(url: love, fallbackText: "[ILOVEU]"), .image(url: like, fallbackText: "[點讚]")])
        XCTAssertTrue(DanmakuStickerURL.permits(URL(string: "https://p66-plat.ndcjl.com/bs2/emotion/a.png")!))
        XCTAssertFalse(DanmakuStickerURL.permits(URL(string: "https://p4-plat.wsbkwai.com.example.org/a.png")!))
    }

    func testKuaishouChatDropsOnlyShortUnclosedTailAndSkipsEmptyResult() throws {
        let messages = ["[新表", "尾[", "保留[123456789", "[未知]", "长[😂😂😂😂😂", "短[😂😂😂😂"]
        let events = try KuaishouDanmaku.decode(kuaishouFrame(messages.map { Data($0.utf8) }), roomID: "123")
        XCTAssertEqual(events.map(\.message), ["尾", "保留[123456789", "[未知]", "长[😂😂😂😂😂", "短"])
        XCTAssertTrue(events.allSatisfy { $0.spans == [.text($0.message)] })
    }

    private func kuaishouFrame(_ messages: [Data]) -> Data {
        var payload = ProtoWriter()
        for message in messages {
            var comment = ProtoWriter()
            comment.bytes(3, message)
            payload.bytes(5, comment.data)
        }
        return KuaishouDanmaku.socketFrame(type: 310, content: payload.data)
    }

    func testMediaURLsRejectCredentialsAndNonMediaSchemes() {
        XCTAssertNil(MediaVariant.url("https://alice:secret@example.com/a.flv"))
        XCTAssertNil(MediaVariant.url("file:///tmp/a.m3u8"))
        XCTAssertEqual(MediaVariant.url("https://example.com/a.m3u8?token=opaque")?.1, .hls)
        XCTAssertEqual(MediaVariant.url("rtmp://example.com/live/stream")?.1, .rtmp)
    }

    func testProtobufRejectsTruncatedLengthAndOverflowingVarint() throws {
        XCTAssertThrowsError(try ProtoMessage(Data([0x0a, 0x05, 0x01])))
        XCTAssertThrowsError(try ProtoMessage(Data([0x08] + Array(repeating: 0xff, count: 10))))
        let encoded = KuaishouDanmaku.join(token: "sample", stream: "stream-id", expTag: "", attach: "")
        let envelope = try ProtoMessage(encoded)
        let payload = try ProtoMessage(envelope.data(3))
        XCTAssertEqual(envelope.number(1), 200)
        XCTAssertEqual(payload.text(1), "sample")
        XCTAssertEqual(payload.text(2), "stream-id")
        XCTAssertEqual(payload.values(5).count, 0)
    }
}

final class ProviderSmokeTests: XCTestCase {
    func testBilibiliQRChallenge() async throws {
        try requireNetwork()
        let service = BilibiliService()
        let challenge = try await service.makeLoginChallenge()
        XCTAssertGreaterThan(challenge.expiration, Date())
        guard case .waiting = try await service.pollLogin(challenge) else {
            return XCTFail("New Bilibili challenge was not awaiting scan")
        }
    }

    func testDouyuQRChallenge() async throws {
        try requireNetwork()
        let service = DouyuService()
        let challenge = try await service.makeLoginChallenge()
        XCTAssertGreaterThan(challenge.expiration, Date())
        guard case .waiting = try await service.pollLogin(challenge) else {
            return XCTFail("New Douyu challenge was not awaiting scan")
        }
    }

    func testHuyaCatalog() async throws {
        try requireNetwork()
        let rooms = try await HuyaService().rooms(in: .recommended, page: 1)
        XCTAssertFalse(rooms.rooms.isEmpty)
        XCTAssertTrue(rooms.rooms.allSatisfy { $0.provider == "huya" })
    }

    func testBilibiliLiveRoomPlayback() async throws {
        try await verifyLiveRoom(using: BilibiliService())
    }

    func testHuyaLiveRoomPlayback() async throws {
        try await verifyLiveRoom(using: HuyaService())
    }

    func testDouyuLiveRoomPlayback() async throws {
        try await verifyLiveRoom(using: DouyuService())
    }

    func testDouyinLiveRoomPlayback() async throws {
        try await verifyLiveRoom(using: DouyinService())
    }

    func testKuaishouLiveRoomPlayback() async throws {
        try await verifyLiveRoom(using: KuaishouService())
    }

    @MainActor
    func testXiaohongshuSharedLiveRoomPlayback() async throws {
        try requireNetwork()
        let environment = ProcessInfo.processInfo.environment
        guard let shareURL = environment["SIMPLELIVE_XIAOHONGSHU_SHARE_URL"], !shareURL.isEmpty else {
            throw XCTSkip("Supply a current public Xiaohongshu live share link in SIMPLELIVE_XIAOHONGSHU_SHARE_URL")
        }
        let service = XiaohongshuService()
        let room = try await service.resolveRoom(shareURL)
        XCTAssertEqual(room.provider, "xiaohongshu")
        XCTAssertFalse(room.title.isEmpty)
        try await verifyPlayback(in: room, using: service, minimumPlaybackSeconds: 5)
    }

    @MainActor
    func testHLSAndFLVReachPlayingState() async throws {
        try requireNetwork()
        let fixtures: [(String, StreamProtocol)] = [
            ("https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8", .hls),
            ("https://samples.ffmpeg.org/FLV/zeldaHQ.flv", .flv),
        ]
        for (value, kind) in fixtures {
            let url = try XCTUnwrap(URL(string: value))
            let engine = PlaybackEngine()
            let task = Task { try await engine.run(resources: [PlaybackResource(url: url, protocolKind: kind)]) }
            defer { task.cancel(); engine.stop() }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(20))
            while engine.state != .playing && clock.now < deadline {
                try await Task.sleep(for: .milliseconds(150))
            }
            XCTAssertEqual(engine.state, .playing, "Backend \(kind.rawValue) never advanced playback")
        }
    }

    private func requireNetwork() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMPLELIVE_LIVE_SMOKE"] == "1",
                          "Set SIMPLELIVE_LIVE_SMOKE=1 to contact the public providers and fixture servers")
    }

    @MainActor
    private func verifyLiveRoom(using service: any LiveProviderService) async throws {
        try requireNetwork()
        let available = try await service.rooms(in: .recommended, page: 1)
        let room = try XCTUnwrap(available.rooms.first)
        try await verifyPlayback(in: room, using: service)
    }

    @MainActor
    private func verifyPlayback(in room: RoomDescriptor, using service: any LiveProviderService, minimumPlaybackSeconds: Int = 0) async throws {
        let qualities = try await service.qualities(roomId: room.roomId)
        let quality = try XCTUnwrap(qualities.first)
        let resources = try await service.playback(roomId: room.roomId, quality: quality)
        XCTAssertFalse(resources.isEmpty)
        let engine = PlaybackEngine()
        let playback = Task { try await engine.run(resources: resources) }
        defer { playback.cancel(); engine.stop() }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(25))
        while engine.state != .playing && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTAssertEqual(engine.state, .playing, "\(room.provider) did not advance live playback")
        if engine.state == .playing, minimumPlaybackSeconds > 0 {
            try await Task.sleep(for: .seconds(minimumPlaybackSeconds))
            XCTAssertEqual(engine.state, .playing, "\(room.provider) did not sustain live playback")
        }
    }
}
