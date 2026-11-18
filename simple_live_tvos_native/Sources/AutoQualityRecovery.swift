import SimpleLiveTVOSCore

enum PlaybackPreferences {
    static let autoQuality = "simple_live_tvos.playback.autoQuality"
}

/// Track distinct stalls after playback starts. A persistent stall is handled by line failover.
struct AutoQualityRecovery {
    private var warmupUntil: ContinuousClock.Instant?
    private var lastStart: ContinuousClock.Instant?
    private var lastDowngrade: ContinuousClock.Instant?
    private var buffering = false

    mutating func observe(_ state: PlaybackState, now: ContinuousClock.Instant) -> Bool {
        switch state {
        case .playing:
            warmupUntil = warmupUntil ?? now.advanced(by: .seconds(8))
            buffering = false
        case .buffering:
            guard !buffering else { return false }
            buffering = true
            guard let warmupUntil, now >= warmupUntil else { return false }
            defer { lastStart = now }
            guard let lastStart, lastStart.duration(to: now) <= .seconds(30),
                  lastDowngrade.map({ $0.duration(to: now) >= .seconds(30) }) ?? true else { return false }
            return true
        default:
            warmupUntil = nil
            lastStart = nil
            buffering = false
        }
        return false
    }

    mutating func markDowngraded(at time: ContinuousClock.Instant) {
        lastDowngrade = time
        lastStart = nil
    }

    static func nextLower(from current: LiveQuality, choices: [LiveQuality]) -> LiveQuality? {
        guard let currentRank = current.recoveryRank else { return nil }
        return choices.compactMap { quality -> (Int, LiveQuality)? in
            guard quality.id != current.id, let rank = quality.recoveryRank, rank < currentRank else { return nil }
            return (rank, quality)
        }.max { $0.0 < $1.0 }?.1
    }
}
