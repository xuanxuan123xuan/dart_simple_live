import 'dart:async';

/// Coordinates the video-track policy used while listening to a live room.
///
/// Playback pause and resume are intentionally outside this session: listening
/// only changes whether video is enabled. Source changes share the same queue
/// so a native source reset cannot race a listening toggle.
class LiveListeningSession {
  LiveListeningSession({
    required Future<void> Function(bool enabled) writeVideoEnabled,
    required bool Function() canChange,
    Future<void> Function()? prepareToListen,
    void Function()? onChanged,
  })  : _writeVideoEnabled = writeVideoEnabled,
        _canChange = canChange,
        _prepareToListen = prepareToListen,
        _onChanged = onChanged;

  final Future<void> Function(bool enabled) _writeVideoEnabled;
  final bool Function() _canChange;
  final Future<void> Function()? _prepareToListen;
  final void Function()? _onChanged;

  Future<void> _queue = Future<void>.value();
  bool _listening = false;
  bool _changing = false;
  bool _closed = false;

  bool get listening => _listening;
  bool get changing => _changing;
  bool get closed => _closed;

  /// Enables or disables listening mode.
  ///
  /// Calls made while another toggle is changing are ignored. The changing
  /// state is published synchronously, before the queued operation begins.
  Future<bool> setListening(bool value) {
    if (_closed || _changing || value == _listening) {
      return Future<bool>.value(false);
    }

    try {
      if (!_canChange()) {
        return Future<bool>.value(false);
      }
    } catch (error, stackTrace) {
      return Future<bool>.error(error, stackTrace);
    }

    final previousListening = _listening;
    _changing = true;
    final operation = _enqueue<bool>(() async {
      var writeAttempted = false;
      try {
        if (_closed) return false;

        if (value) {
          await _prepareToListen?.call();
          if (_closed) return false;
        }

        // Room state can change while preparation is awaiting, so validate it
        // again immediately before touching the native player.
        if (!_canChange() || _closed) return false;

        writeAttempted = true;
        await _writeVideoEnabled(!value);
        if (_closed) return false;

        _listening = value;
        return true;
      } catch (error, stackTrace) {
        if (writeAttempted && !_closed) {
          try {
            await _writeVideoEnabled(!previousListening);
          } catch (_) {
            // Preserve the operation error for the caller. The session state
            // remains at its previous value even if native rollback also fails.
          }
        }
        Error.throwWithStackTrace(error, stackTrace);
      } finally {
        _changing = false;
        if (!_closed) _notifyChanged();
      }
    });

    _notifyChanged();
    return operation;
  }

  /// Runs a source mutation in order with listening toggles.
  ///
  /// When listening is active, video is disabled on both sides of the source
  /// operation because opening a source may reset native track selection.
  Future<void> withSource(Future<void> Function() operation) {
    if (_closed) return Future<void>.value();

    return _enqueue<void>(() async {
      if (_closed) return;

      final reapplyListeningPolicy = _listening;
      if (reapplyListeningPolicy) {
        await _writeVideoEnabled(false);
        if (_closed) return;
      }

      Object? operationError;
      StackTrace? operationStackTrace;
      try {
        await operation();
      } catch (error, stackTrace) {
        operationError = error;
        operationStackTrace = stackTrace;
      }

      if (reapplyListeningPolicy && !_closed && _listening) {
        try {
          await _writeVideoEnabled(false);
        } catch (error, stackTrace) {
          if (operationError == null) {
            Error.throwWithStackTrace(error, stackTrace);
          }
        }
      }

      if (operationError != null) {
        Error.throwWithStackTrace(operationError, operationStackTrace!);
      }
    });
  }

  /// Marks this session closed immediately and waits for queued work to settle.
  Future<void> close() {
    _closed = true;
    return _queue;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _queue.then<T>((_) => operation());
    // Keep the serialization tail usable after a caller observes an error.
    _queue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  void _notifyChanged() {
    if (_closed) return;
    try {
      _onChanged?.call();
    } catch (_) {
      // A view callback must not break a queued player operation.
    }
  }
}
