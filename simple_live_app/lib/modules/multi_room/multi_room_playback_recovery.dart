/// One player participating in a bounded multi-room playback recovery pass.
class MultiRoomPlaybackRecoveryTarget {
  const MultiRoomPlaybackRecoveryTarget({
    required this.roomKey,
    required this.shouldPlay,
    required this.isPlaying,
    required this.requestPlay,
    required this.waitUntilPlaying,
  });

  final String roomKey;
  final bool Function() shouldPlay;
  final bool Function() isPlaying;
  final Future<void> Function() requestPlay;
  final Future<bool> Function(Duration timeout) waitUntilPlaying;
}

/// Restores players interrupted by another native player's `open` call.
///
/// Recovery is deliberately bounded and serial. Every play request is guarded
/// by [MultiRoomPlaybackRecoveryTarget.shouldPlay], so a pause selected while a
/// recovery pass is queued always wins over the automatic recovery.
class MultiRoomPlaybackRecoveryCoordinator {
  const MultiRoomPlaybackRecoveryCoordinator({
    this.maxAttempts = 3,
    this.confirmTimeout = const Duration(milliseconds: 700),
    this.retryDelay = const Duration(milliseconds: 250),
  }) : assert(maxAttempts > 0);

  final int maxAttempts;
  final Duration confirmTimeout;
  final Duration retryDelay;

  Future<bool> recover({
    required List<MultiRoomPlaybackRecoveryTarget> targets,
    required bool Function() isCancelled,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
      if (isCancelled()) return false;

      for (final target in targets) {
        if (isCancelled()) return false;
        // 不因 isPlaying() 跳过：iOS 上被抢占的格 state 可能滞后为 true，
        // 依赖它判断会漏掉真正需要恢复的格。requestPlay 按业务意图幂等
        // 发起（play 已播状态为 no-op），isPlaying 仅用于确认与重试。
        if (!target.shouldPlay()) continue;

        try {
          await target.requestPlay();
          if (isCancelled()) return false;
          if (!target.shouldPlay()) continue;
          if (!target.isPlaying()) {
            await target.waitUntilPlaying(confirmTimeout);
          }
        } catch (_) {
          // Disposal or route changes can close a shared mutation queue while
          // a recovery pass is waiting. Treat that attempt as failed; the
          // cancellation predicate decides whether another attempt is valid.
          if (isCancelled()) return false;
        }
      }

      if (isCancelled()) return false;
      final recovered = targets.every(
        (target) => !target.shouldPlay() || target.isPlaying(),
      );
      if (recovered) return true;

      if (attempt + 1 < maxAttempts && retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }
    }

    return !isCancelled() &&
        targets.every(
          (target) => !target.shouldPlay() || target.isPlaying(),
        );
  }
}
