import 'dart:async';

import 'package:flutter/foundation.dart';

/// Tracks whether the multi-room playback controls should be visible.
class MultiRoomOverlayController extends ChangeNotifier {
  MultiRoomOverlayController({
    this.idleDuration = const Duration(seconds: 5),
    this.onBeforeHide,
  }) {
    _restartIdleTimer();
  }

  final Duration idleDuration;
  final VoidCallback? onBeforeHide;

  Timer? _idleTimer;
  int _holdCount = 0;
  bool _visible = true;
  bool _hiding = false;
  bool _disposed = false;

  bool get visible => _visible;

  /// Shows the controls and restarts the idle timer unless they are held.
  void activity() {
    if (_disposed || _hiding) return;

    if (!_visible) {
      _visible = true;
      notifyListeners();
    }

    if (_holdCount == 0) {
      _restartIdleTimer();
    } else {
      _cancelIdleTimer();
    }
  }

  /// Keeps the controls visible until the returned closure is called.
  ///
  /// Holds can be nested. Each returned closure releases only its own hold and
  /// may be called more than once safely.
  VoidCallback hold() {
    if (_disposed || _hiding) return _noOp;

    activity();
    if (_disposed || _hiding) return _noOp;

    _holdCount++;
    _cancelIdleTimer();

    var released = false;
    return () {
      if (released) return;
      released = true;
      if (_disposed || _holdCount == 0) return;

      _holdCount--;
      if (_holdCount == 0) _restartIdleTimer();
    };
  }

  /// Hides the controls unless an interaction currently holds them open.
  void hide() {
    if (_disposed || _hiding || _holdCount > 0 || !_visible) return;

    _cancelIdleTimer();
    _hiding = true;
    Object? callbackError;
    StackTrace? callbackStackTrace;
    try {
      onBeforeHide?.call();
    } catch (error, stackTrace) {
      callbackError = error;
      callbackStackTrace = stackTrace;
    } finally {
      _hiding = false;
    }

    _visible = false;
    _cancelIdleTimer();
    if (!_disposed) notifyListeners();

    if (callbackError != null) {
      Error.throwWithStackTrace(callbackError, callbackStackTrace!);
    }
  }

  void _restartIdleTimer() {
    _cancelIdleTimer();
    if (_disposed || _hiding || _holdCount > 0 || !_visible) return;

    _idleTimer = Timer(idleDuration, () {
      _idleTimer = null;
      hide();
    });
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  static void _noOp() {}

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelIdleTimer();
    super.dispose();
  }
}
