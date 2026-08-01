import 'dart:async';

/// Serializes mutations which may reopen or tear down a native player.
///
/// A queue may be shared by all players on a page. A failed mutation only
/// fails its own future; later mutations are still allowed to run.
class PlayerMutationQueue {
  Future<void> _tail = Future<void>.value();
  bool _closed = false;
  int _pendingCount = 0;

  bool get isClosed => _closed;
  int get pendingCount => _pendingCount;

  /// Completes after every operation which was enqueued before this call.
  Future<void> get idle => _tail;

  Future<T> run<T>(Future<T> Function() operation) {
    if (_closed) {
      return Future<T>.error(
        StateError('PlayerMutationQueue is closed'),
      );
    }

    _pendingCount += 1;
    final completer = Completer<T>();
    final scheduled = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _pendingCount -= 1;
      }
    });
    // Keep the tail successful so one failed operation never poisons the
    // queue. Errors are delivered through [completer].
    _tail = scheduled.catchError((Object _) {});
    return completer.future;
  }

  /// Prevents new work. Already queued operations are allowed to finish.
  Future<void> close() async {
    _closed = true;
    await _tail;
  }
}
