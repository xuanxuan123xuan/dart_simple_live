import 'dart:async';

enum PlayerHandoffStatus { ready, timedOut, releaseFailed, cancelled }

enum PlayerOpenStatus { opened, stale, timedOut }

/// Serializes native opens without treating a timeout as cancellation.
///
/// A timeout only tells the caller that it should stop waiting. The native
/// future remains the owner of the queue until it actually settles, so a
/// later open and player disposal cannot race an in-flight native request.
class PlayerNativeOpenQueue {
  Future<void>? _active;

  bool get hasInflight => _active != null;

  Future<PlayerOpenStatus> open({
    required Future<void> Function() operation,
    required bool Function() isCurrent,
    required Duration timeout,
    required void Function(Object, StackTrace) onPreviousError,
  }) async {
    final deadline = Stopwatch()..start();
    while (true) {
      if (!isCurrent()) return PlayerOpenStatus.stale;
      final active = _active;
      if (active == null) break;
      final remaining = timeout - deadline.elapsed;
      if (remaining <= Duration.zero) {
        return isCurrent() ? PlayerOpenStatus.timedOut : PlayerOpenStatus.stale;
      }
      try {
        await active.timeout(remaining);
      } on TimeoutException {
        return isCurrent() ? PlayerOpenStatus.timedOut : PlayerOpenStatus.stale;
      } catch (error, stackTrace) {
        onPreviousError(error, stackTrace);
      }
    }

    if (!isCurrent()) return PlayerOpenStatus.stale;
    late final Future<void> opening;
    opening = Future<void>.microtask(() async {
      // If cancellation wins before this microtask starts, do not issue a new
      // native request. Once operation() has started, its future remains the
      // queue owner even if the caller later times out.
      if (!isCurrent()) return;
      await operation();
    });
    _active = opening;
    void clear() {
      if (identical(_active, opening)) _active = null;
    }

    // The error callback consumes the completion error after clearing the
    // ownership marker. The caller still receives the error below when it
    // observes the opening future directly.
    unawaited(opening.then<void>(
      (_) => clear(),
      onError: (Object _, StackTrace __) => clear(),
    ));

    final remaining = timeout - deadline.elapsed;
    if (remaining <= Duration.zero) {
      return isCurrent() ? PlayerOpenStatus.timedOut : PlayerOpenStatus.stale;
    }
    try {
      await opening.timeout(remaining);
      return isCurrent() ? PlayerOpenStatus.opened : PlayerOpenStatus.stale;
    } on TimeoutException {
      return isCurrent() ? PlayerOpenStatus.timedOut : PlayerOpenStatus.stale;
    }
  }

  /// Waits without a timeout. Disposal uses this method so a timed-out open
  /// can never be followed by a racing native dispose.
  Future<void> waitUntilIdle() async {
    while (true) {
      final active = _active;
      if (active == null) return;
      try {
        await active;
      } catch (_) {
        // The native operation is settled, so the queue can be released even
        // when the operation itself failed.
      }
    }
  }

  Future<bool> waitUntilIdleWithTimeout(Duration timeout) async {
    try {
      await waitUntilIdle().timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }
}

/// Coordinates ownership handoff between single-room player instances.
///
/// Multi-room players intentionally do not register here. Their native
/// players are independent and must remain active while a single-room route
/// is being prepared.
class PlayerRetirementCoordinator {
  PlayerRetirementCoordinator();

  static final PlayerRetirementCoordinator shared =
      PlayerRetirementCoordinator();

  static int _nextInstanceId = 0;

  final Map<int, _PlayerRetirement> _retiring = {};

  int get pendingCount => _retiring.length;

  int register() {
    final instanceId = ++_nextInstanceId;
    _retiring[instanceId] = _PlayerRetirement();
    return instanceId;
  }

  Future<PlayerHandoffStatus> initializeWhenReleased({
    required int instanceId,
    required Duration timeout,
    required bool Function() isCurrent,
    required void Function() initialize,
    Future<void>? cancelled,
  }) async {
    final status = await waitUntilReleased(
      instanceId: instanceId,
      timeout: timeout,
      cancelled: cancelled,
    );
    if (!isCurrent()) return PlayerHandoffStatus.cancelled;
    if (status != PlayerHandoffStatus.ready) return status;
    initialize();
    return PlayerHandoffStatus.ready;
  }

  /// Registers a release future exactly once. A release failure remains
  /// visible to later owners, because handing off after an unknown native
  /// state is unsafe.
  void retire(int instanceId, Future<void> release) {
    var retirement = _retiring[instanceId] ??= _PlayerRetirement();
    if (retirement.releaseAttached && !retirement.failed) return;
    if (retirement.failed) {
      retirement = _PlayerRetirement();
      _retiring[instanceId] = retirement;
    }
    retirement.releaseAttached = true;
    release.then<void>(
      (_) => _complete(instanceId, retirement),
      onError: (Object error, StackTrace stackTrace) {
        retirement.failed = true;
        _complete(instanceId, retirement);
      },
    );
  }

  void _complete(int instanceId, _PlayerRetirement retirement) {
    if (identical(_retiring[instanceId], retirement)) {
      if (retirement.failed) {
        // Keep a failed retirement as a hard handoff barrier.
      } else {
        _retiring.remove(instanceId);
      }
    }
    if (!retirement.completed.isCompleted) {
      retirement.completed.complete();
    }
  }

  Future<PlayerHandoffStatus> waitUntilReleased({
    required int instanceId,
    Duration? timeout,
    Future<void>? cancelled,
  }) async {
    final deadline = timeout == null ? null : (Stopwatch()..start());
    while (true) {
      final pending = _retiring.entries
          .where((entry) => entry.key != instanceId)
          .map((entry) => entry.value)
          .toList();
      if (pending.any((entry) => entry.failed)) {
        return PlayerHandoffStatus.releaseFailed;
      }
      if (pending.isEmpty) return PlayerHandoffStatus.ready;

      final remaining = deadline == null ? null : timeout! - deadline.elapsed;
      if (remaining != null && remaining <= Duration.zero) {
        return PlayerHandoffStatus.timedOut;
      }
      final released = Future.wait<void>(
        pending.map((entry) => entry.completed.future),
      ).then((_) => PlayerHandoffStatus.ready);
      Future<PlayerHandoffStatus> outcome = released;
      if (cancelled != null) {
        outcome = Future.any<PlayerHandoffStatus>([
          released,
          cancelled.then((_) => PlayerHandoffStatus.cancelled),
        ]);
      }
      final status = remaining == null
          ? await outcome
          : await outcome.timeout(
              remaining,
              onTimeout: () => PlayerHandoffStatus.timedOut,
            );
      if (status != PlayerHandoffStatus.ready) return status;
    }
  }
}

class _PlayerRetirement {
  final completed = Completer<void>();
  bool releaseAttached = false;
  bool failed = false;
}

class PlayerCleanupStep {
  const PlayerCleanupStep(this.name, this.run);

  final String name;
  final FutureOr<void> Function() run;
}

/// Runs every cleanup step and always attempts the final native dispose.
Future<void> releasePlayerResources({
  required List<PlayerCleanupStep> steps,
  required Future<void> Function() dispose,
  required void Function(String, Object, StackTrace) onError,
  Future<void> Function()? beforeDispose,
}) async {
  for (final step in steps) {
    try {
      await step.run();
    } catch (error, stackTrace) {
      onError(step.name, error, stackTrace);
    }
  }
  if (beforeDispose != null) {
    try {
      await beforeDispose();
    } catch (error, stackTrace) {
      onError('beforeDispose', error, stackTrace);
      return;
    }
  }
  await dispose();
}
