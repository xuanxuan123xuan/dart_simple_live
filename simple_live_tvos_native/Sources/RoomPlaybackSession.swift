import Combine
import Observation
import SimpleLiveTVOSCore
import SwiftUI

struct RoomPlaybackHandoff: Hashable {
    let room: RoomDescriptor
    let volume: Int
    let muted: Bool
    let paused: Bool
    let danmakuEnabled: Bool
    let qualities: [LiveQuality]
    let quality: LiveQuality?
    let line: Int?
}

@MainActor
@Observable
final class RoomPlaybackSession {
    let room: RoomDescriptor
    let engine: PlaybackEngine
    let danmakuEvents = PassthroughSubject<DanmakuEvent, Never>()

    var danmakuOverride: Bool?
    private(set) var playbackIssue: PlaybackIssue?
    private(set) var danmakuError: String?
    private(set) var qualityRecoveryMessage: String?
    private(set) var qualities: [LiveQuality] = []
    private(set) var selectedQuality: LiveQuality?
    private(set) var danmakuRefresh = 0

    private var resources: [PlaybackResource] = []
    private var preferredLine: Int?
    private var retry = 0
    private var isRetired = false
    private var qualityRecovery = AutoQualityRecovery()

    init(room: RoomDescriptor, danmakuEnabled: Bool? = nil, restoring handoff: RoomPlaybackHandoff? = nil) {
        self.room = room
        if let handoff, handoff.room.key == room.key {
            engine = PlaybackEngine(initialVolume: handoff.volume)
            engine.setMuted(handoff.muted)
            engine.setPaused(handoff.paused)
            danmakuOverride = handoff.danmakuEnabled
            qualities = handoff.qualities
            selectedQuality = handoff.quality
            preferredLine = handoff.line
        } else {
            engine = PlaybackEngine()
            danmakuOverride = danmakuEnabled
        }
    }

    var availableLines: [Int] { Set(resources.map(\.lineIndex)).sorted() }

    var playbackStatus: String {
        if let playbackIssue { return playbackIssue.title }
        switch engine.state {
        case .idle, .preparing: return "连接中"
        case .buffering: return "缓冲中"
        case .playing: return "正在播放"
        case .paused: return "已暂停"
        case .failed: return "播放失败"
        case .stopped: return "已停止"
        }
    }

    func handoff(danmakuEnabled: Bool) -> RoomPlaybackHandoff {
        .init(room: room, volume: engine.volume, muted: engine.isMuted, paused: engine.pausedByUser,
              danmakuEnabled: danmakuEnabled, qualities: qualities, quality: selectedQuality,
              line: engine.currentLine ?? preferredLine)
    }

    func refresh() {
        qualityRecoveryMessage = nil
        resources = []
        danmakuRefresh += 1
        restart()
    }

    func selectQuality(_ quality: LiveQuality, automatically: Bool = false) {
        guard selectedQuality != quality else { return }
        qualityRecoveryMessage = automatically ? "网络波动，已切换至\(quality.name)" : nil
        resources = []
        preferredLine = nil
        selectedQuality = quality
        restart()
    }

    func selectLine(_ line: Int) {
        guard line != engine.currentLine, availableLines.contains(line) else { return }
        preferredLine = line
        restart()
    }

    private func restart() {
        retry += 1
        stop()
    }

    func stop() {
        engine.stop()
    }

    func retire() {
        isRetired = true
        stop()
    }

    func resetQualityRecovery() {
        qualityRecovery = AutoQualityRecovery()
    }

    func observeQualityRecovery(_ state: PlaybackState) {
        let now = ContinuousClock.now
        guard qualityRecovery.observe(state, now: now), let selectedQuality,
              let lower = AutoQualityRecovery.nextLower(from: selectedQuality, choices: qualities) else { return }
        qualityRecovery.markDowngraded(at: now)
        selectQuality(lower, automatically: true)
    }

    struct Request: Hashable {
        let quality: LiveQuality?
        let retry: Int
        let active: Bool
    }

    func request(active: Bool) -> Request {
        Request(quality: selectedQuality, retry: retry, active: active)
    }

    func run(_ request: Request, core: NativeCoreClient, library: LibraryStore) async {
        guard !Task.isCancelled, request.retry == retry, !isRetired else { return }
        guard request.active else {
            stop()
            resources = []
            return
        }
        playbackIssue = nil
        let requestedLine = preferredLine
        do {
            let service = try core.service(room.provider)
            guard let quality = request.quality else {
                let values = try await service.qualities(roomId: room.roomId)
                try check(request)
                qualities = values
                guard let first = PlaybackTuning().defaultQuality.select(from: values) else {
                    throw LiveProviderError.noPlayback
                }
                selectedQuality = first
                return
            }
            let current = resources.isEmpty
                ? try await service.playback(roomId: room.roomId, quality: quality)
                : resources
            try check(request)

            let history = Task {
                while !Task.isCancelled {
                    if engine.state == .playing {
                        library.visit(room)
                        return
                    }
                    try await Task.sleep(for: .milliseconds(300))
                }
            }
            defer { history.cancel() }

            do {
                try await play(current, preferredLine: requestedLine)
            } catch LiveProviderError.noPlayback {
                try check(request)
                let fresh = try await service.playback(roomId: room.roomId, quality: quality)
                try check(request)
                if fresh == current { throw LiveProviderError.noPlayback }
                try await play(fresh, preferredLine: requestedLine)
            }
        } catch {
            guard !Task.isCancelled, request.retry == retry, !isRetired else { return }
            let issue = await PlaybackIssue.classify(error) {
                try await core.service(room.provider).resolveRoom(room.roomId).isLive
            }
            if !Task.isCancelled, request.retry == retry, !isRetired { playbackIssue = issue }
        }
    }

    private func check(_ request: Request) throws {
        try Task.checkCancellation()
        guard request.retry == retry, !isRetired else { throw CancellationError() }
    }

    private func play(_ resources: [PlaybackResource], preferredLine: Int?) async throws {
        self.resources = resources
        try await engine.run(resources: resources, preferredLine: preferredLine)
    }

    func runDanmaku(enabled: Bool, stream: () throws -> AsyncThrowingStream<DanmakuEvent, Error>) async {
        danmakuError = nil
        guard enabled, !Task.isCancelled, !isRetired else { return }
        do {
            for try await event in try stream() {
                try Task.checkCancellation()
                guard !isRetired else { return }
                if engine.state == .playing { danmakuEvents.send(event) }
            }
        } catch {
            if !Task.isCancelled { danmakuError = "弹幕暂不可用" }
        }
    }
}

struct RoomPlaybackActivity: ViewModifier {
    @EnvironmentObject private var core: NativeCoreClient
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PlaybackPreferences.autoQuality) private var autoQuality = true

    let session: RoomPlaybackSession
    var isEnabled = true
    let showsDanmaku: Bool

    func body(content: Content) -> some View {
        let active = isEnabled && scenePhase == .active
        let playback = session.request(active: active)
        let danmaku = DanmakuRequest(active: active && showsDanmaku, refresh: session.danmakuRefresh)
        content
            .task(id: playback) { await session.run(playback, core: core, library: library) }
            .task(id: danmaku) {
                await session.runDanmaku(enabled: danmaku.active) { try core.danmaku(for: session.room) }
            }
            .onChange(of: session.engine.state) { _, state in
                if autoQuality, active { session.observeQualityRecovery(state) }
            }
            .onChange(of: autoQuality) { _, _ in session.resetQualityRecovery() }
            .onDisappear { session.stop() }
    }

    private struct DanmakuRequest: Equatable {
        let active: Bool
        let refresh: Int
    }
}
