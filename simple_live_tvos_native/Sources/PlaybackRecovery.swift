import Foundation

enum PlaybackIssue: Equatable {
    case offline
    case failed(String)

    var title: String {
        switch self {
        case .offline: "直播间当前未开播"
        case .failed: "播放失败"
        }
    }

    @MainActor
    static func classify(_ error: Error, lookupPresence: () async throws -> Bool?) async -> Self {
        if case LiveProviderError.offline = error { return .offline }
        if case LiveProviderError.noPlayback = error {
            do {
                if try await lookupPresence() == false { return .offline }
            } catch LiveProviderError.offline {
                return .offline
            } catch {
                // Preserve the original problem if status could not be confirmed.
            }
        }
        return .failed(error.localizedDescription)
    }
}

enum SleepTimerDisplay {
    static func remaining(until deadline: Date, now: Date) -> String {
        let seconds = Int(max(0, ceil(deadline.timeIntervalSince(now))))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
