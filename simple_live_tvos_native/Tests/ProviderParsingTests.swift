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

    func testSSRDataPreservesQuotedUndefinedAndBalancesNestedObjects() throws {
        let page = #"<script>window.__INITIAL_STATE__ = {"title":"undefined and }","body":{"missing":undefined}}</script>"#
        let state = try EmbeddedPageData.initialState(in: page)
        XCTAssertEqual(state.text("title"), "undefined and }")
        XCTAssertTrue(state["body"].fields["missing"] is NSNull)
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
