/// One player participating in a bounded multi-room playback recovery pass.
class MultiRoomPlaybackRecoveryTarget {
  const MultiRoomPlaybackRecoveryTarget({
    required this.roomKey,
    required this.shouldPlay,
    required this.requestPlay,
    required this.waitUntilPlaying,
  });

  final String roomKey;
  final bool Function() shouldPlay;
  final Future<void> Function(bool forceRestart) requestPlay;
  final Future<bool> Function(Duration timeout) waitUntilPlaying;
}

/// Restores players interrupted by another native player's `open` call.
///
/// Recovery is deliberately bounded. Mutations are requested serially, then
/// every desired player is verified concurrently so all streams must make
/// progress in the same observation window. Every request is guarded by
/// [MultiRoomPlaybackRecoveryTarget.shouldPlay], so a pause selected while a
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
    Set<String>? retryRoomKeys;
    for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
      if (isCancelled()) return false;

      for (final target in targets) {
        if (isCancelled()) return false;
        if (!target.shouldPlay()) continue;
        if (retryRoomKeys != null && !retryRoomKeys.contains(target.roomKey)) {
          continue;
        }

        try {
          // The first pass is non-disruptive. A target which still fails the
          // real-progress check gets a pause/play cycle on the next pass to
          // rebuild an interrupted native output without restarting healthy
          // players.
          await target.requestPlay(attempt > 0);
          if (isCancelled()) return false;
        } catch (_) {
          // Disposal or route changes can close a shared mutation queue while
          // a recovery pass is waiting. Treat that attempt as failed; the
          // cancellation predicate decides whether another attempt is valid.
          if (isCancelled()) return false;
        }
      }

      if (isCancelled()) return false;
      // Verify every desired player over the same observation window. Serial
      // verification can report an early player as healthy before a later
      // audio-session activation interrupts it.
      final desiredTargets = targets.where((target) => target.shouldPlay());
      final verification = await Future.wait(
        desiredTargets.map((target) async {
          if (isCancelled()) return MapEntry(target.roomKey, false);
          try {
            final advancing = await target.waitUntilPlaying(confirmTimeout);
            return MapEntry(
              target.roomKey,
              !target.shouldPlay() || advancing,
            );
          } catch (_) {
            return MapEntry(target.roomKey, !target.shouldPlay());
          }
        }),
      );
      if (isCancelled()) return false;
      retryRoomKeys = {
        for (final result in verification)
          if (!result.value) result.key,
      };
      if (retryRoomKeys.isEmpty) return true;

      if (attempt + 1 < maxAttempts && retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }
    }

    return !isCancelled() && (retryRoomKeys?.isEmpty ?? true);
  }
}
