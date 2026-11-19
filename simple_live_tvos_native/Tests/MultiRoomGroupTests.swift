import Combine
import SimpleLiveTVOSCore
@testable import SimpleLiveTVOS
import XCTest

final class MultiRoomGroupTests: XCTestCase {
    @MainActor
    func testEditingPreservesRetainedSessionsAndRepairsGroupFocusAndAudio() throws {
        let rooms = makeRooms()
        let group = MultiRoomGroup(rooms: Array(rooms.prefix(3)), preferences: try defaultPreferences())
        defer { group.retire() }
        let first = group.sessions[0]
        let second = group.sessions[1]

        group.makePrimary(first.room.key)
        group.toggleExpanded(first.room.key)
        group.setAudioFocus(first.room.key)
        second.engine.setVolume(40)
        second.engine.setPaused(true)
        second.danmakuOverride = false

        XCTAssertTrue(group.replaceRooms([rooms[1], rooms[2], rooms[3]]))
        XCTAssertTrue(group.sessions[0] === second)
        XCTAssertEqual(first.engine.state, .stopped)
        XCTAssertEqual(group.selectedKey, second.room.key)
        XCTAssertEqual(group.primaryKey, second.room.key)
        XCTAssertEqual(group.audioKey, second.room.key)
        XCTAssertNil(group.expandedKey)
        XCTAssertEqual(second.engine.volume, 40)
        XCTAssertTrue(second.engine.pausedByUser)
        XCTAssertEqual(second.danmakuOverride, false)
        XCTAssertFalse(group.sessions[2].engine.pausedByUser)
        XCTAssertFalse(group.replaceRooms([rooms[1], rooms[1]]))
        XCTAssertEqual(group.sessions.count, 3)
    }

    @MainActor
    func testFourAudioIntentsStayIndependentAcrossRoutingAndHandoff() throws {
        let group = MultiRoomGroup(rooms: makeRooms(), preferences: try defaultPreferences())
        defer { group.retire() }
        let second = group.sessions[1]
        let first = group.sessions[0]
        XCTAssertEqual(group.sessions.map { $0.engine.isEffectivelyMuted }, [false, true, true, true])
        group.select(second.room.key)
        group.makePrimary(second.room.key)
        XCTAssertEqual(group.audioKey, first.room.key)

        first.engine.setMuted(true)
        second.engine.setVolume(35)
        group.setAudioFocus(second.room.key)
        XCTAssertEqual(group.sessions.map { $0.engine.isEffectivelyMuted }, [true, false, true, true])
        group.setAudioMode(.mixed)
        XCTAssertEqual(group.sessions.map { $0.engine.isEffectivelyMuted }, [true, false, false, false])
        group.setAudioMode(.single)
        XCTAssertEqual(group.sessions.map { $0.engine.isEffectivelyMuted }, [true, false, true, true])

        group.setDanmaku(true)
        second.danmakuOverride = false
        XCTAssertEqual(group.sessions.map(\.danmakuOverride), [true, false, true, true])
        group.setPaused(true)
        XCTAssertTrue(group.allPaused)
        second.engine.setPaused(false)
        XCTAssertFalse(group.allPaused)

        let handoff = second.handoff(danmakuEnabled: second.danmakuOverride == true)
        let restored = RoomPlaybackSession(room: second.room, restoring: handoff)
        XCTAssertEqual(restored.engine.volume, 35)
        XCTAssertFalse(restored.engine.isMuted)
        XCTAssertFalse(restored.engine.pausedByUser)
        XCTAssertEqual(restored.danmakuOverride, false)
    }

    func testGridAndPrimaryFramesFitWithoutIntersecting() {
        for size in [CGSize(width: 1920, height: 1080), CGSize(width: 1280, height: 720)] {
            for count in 2...4 {
                for layout in MultiRoomLayout.allCases {
                    let frames = MultiRoomGeometry.frames(count: count, size: size, layout: layout, primaryIndex: count - 1)
                    XCTAssertEqual(frames.count, count)
                    for (index, frame) in frames.enumerated() {
                        XCTAssertEqual(frame.width / frame.height, 16.0 / 9.0, accuracy: 0.001)
                        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(frame))
                        XCTAssertFalse(frames.dropFirst(index + 1).contains { $0.intersects(frame) })
                    }
                    if layout == .primary {
                        XCTAssertGreaterThan(frames[count - 1].width, frames[0].width)
                    } else if count == 2 {
                        XCTAssertEqual(frames[0].midY, size.height / 2)
                        XCTAssertEqual(frames[1].midY, size.height / 2)
                    }
                }
            }
        }
    }

    @MainActor
    func testRetiringAGroupReleasesFourPreparedAVPlayerItems() async throws {
        let group = MultiRoomGroup(rooms: makeRooms(), preferences: try defaultPreferences())
        let url = try XCTUnwrap(URL(string: "https://127.0.0.1:1/fixture.m3u8"))
        let resource = PlaybackResource(url: url, protocolKind: .hls)
        // Paused sessions prepare the local player objects without waiting on a media server.
        group.setPaused(true)
        let tasks = group.sessions.map { session in
            Task { try await session.engine.run(resources: [resource]) }
        }
        defer {
            tasks.forEach { $0.cancel() }
            group.retire()
        }

        try await waitUntil { group.sessions.allSatisfy { $0.engine.player?.currentItem != nil } }
        let players = try group.sessions.map { try XCTUnwrap($0.engine.player) }
        XCTAssertEqual(Set(players.map(ObjectIdentifier.init)).count, 4)
        XCTAssertEqual(players.map(\.isMuted), [false, true, true, true])
        group.sessions[2].engine.setVolume(25)
        group.setAudioFocus(group.sessions[2].room.key)
        XCTAssertEqual(players.map(\.isMuted), [true, true, false, true])
        XCTAssertEqual(players[2].volume, 0.25)

        let removed = group.sessions[0]
        group.remove(removed.room.key)
        XCTAssertNil(removed.engine.player)
        XCTAssertNil(players[0].currentItem)
        XCTAssertNotNil(players[1].currentItem)
        group.retire()
        XCTAssertTrue(players.allSatisfy { $0.currentItem == nil })
        XCTAssertTrue(group.sessions.allSatisfy { $0.engine.player == nil && $0.engine.nativeView == nil })
        for task in tasks { _ = await task.result }
    }

    @MainActor
    func testFourPlayersAdvanceAndDanmakuStreamsStaySeparate() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMPLELIVE_LIVE_SMOKE"] == "1",
                          "Set SIMPLELIVE_LIVE_SMOKE=1 to stream the public media fixtures")
        let hls = try XCTUnwrap(URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"))
        let flv = try XCTUnwrap(URL(string: "https://samples.ffmpeg.org/FLV/zeldaHQ.flv"))
        let media = [PlaybackResource(url: hls, protocolKind: .hls), PlaybackResource(url: flv, protocolKind: .flv),
                     PlaybackResource(url: hls, protocolKind: .hls), PlaybackResource(url: hls, protocolKind: .hls)]
        let group = MultiRoomGroup(rooms: makeRooms(), preferences: try defaultPreferences())
        let playback = zip(group.sessions, media).map { session, resource in
            Task { try await session.engine.run(resources: [resource]) }
        }
        let streams = group.sessions.map { _ in AsyncThrowingStream<DanmakuEvent, Error>.makeStream() }
        var received = Array(repeating: [String](), count: streams.count)
        let subscriptions = group.sessions.enumerated().map { index, session in
            session.danmakuEvents.sink { received[index].append($0.message) }
        }
        let terminations = streams.indices.map { expectation(description: "弹幕连接 \($0) 取消") }
        let danmaku = zip(group.sessions, streams).enumerated().map { index, pair in
            let (session, stream) = pair
            stream.continuation.onTermination = { _ in terminations[index].fulfill() }
            return Task { await session.runDanmaku(enabled: true) { stream.stream } }
        }
        defer {
            playback.forEach { $0.cancel() }
            danmaku.forEach { $0.cancel() }
            group.retire()
            subscriptions.forEach { $0.cancel() }
        }

        try await waitUntil(timeout: .seconds(25)) { group.sessions.allSatisfy { $0.engine.state == .playing } }
        XCTAssertNotNil(group.sessions[1].engine.nativeView)
        for (index, stream) in streams.enumerated() {
            stream.continuation.yield(event(index, "第\(index)路"))
        }
        try await waitUntil { received.allSatisfy { $0.count == 1 } }
        XCTAssertEqual(received, [["第0路"], ["第1路"], ["第2路"], ["第3路"]])

        group.sessions[1].engine.setPaused(true)
        group.setAudioFocus(group.sessions[2].room.key)
        streams[1].continuation.yield(event(1, "暂停"))
        streams[2].continuation.yield(event(2, "继续"))
        try await waitUntil { received[2].count == 2 }
        XCTAssertEqual(received[1], ["第1路"])
        XCTAssertEqual(group.sessions[2].engine.player?.isMuted, false)
        XCTAssertEqual(group.sessions[0].engine.player?.isMuted, true)
        XCTAssertEqual(group.sessions[3].engine.state, .playing)

        group.retire()
        danmaku.forEach { $0.cancel() }
        await fulfillment(of: terminations, timeout: 5)
        XCTAssertTrue(group.sessions.allSatisfy { $0.engine.player == nil && $0.engine.nativeView == nil })
        for task in playback { _ = await task.result }
    }

    @MainActor
    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { throw TestTimeout() }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func defaultPreferences() throws -> MultiRoomPreferences {
        let name = "multi-room-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        return MultiRoomPreferences(defaults: defaults)
    }

    private struct TestTimeout: Error {}

    private func event(_ index: Int, _ message: String) -> DanmakuEvent {
        DanmakuEvent(id: UUID().uuidString, room: RoomKey(provider: .bilibili, roomId: String(index + 1)),
                     userName: "测试", message: message, color: DanmakuColor(red: 255, green: 255, blue: 255))
    }

    private func makeRooms() -> [RoomDescriptor] {
        (1...4).map { RoomDescriptor(provider: "bilibili", roomId: String($0), title: "直播 \($0)", cover: "", userName: "") }
    }
}
