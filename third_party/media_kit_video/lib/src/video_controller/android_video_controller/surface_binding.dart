import 'dart:async';

import 'package:synchronized/synchronized.dart';

typedef AndroidSurfacePropertyWriter =
    Future<void> Function(String key, String value);

/// Serializes Android surface property updates with video lifecycle work.
///
/// The caller owns [lock] so resize, initialization, load hooks, video
/// parameters, and disposal can all use the same non-reentrant lock.
class AndroidSurfaceBinding {
  AndroidSurfaceBinding({
    Lock? lock,
    required AndroidSurfacePropertyWriter writeProperty,
    required this.vo,
    required this.compatibilityMode,
  }) : lock = lock ?? Lock(),
       _writeProperty = writeProperty;

  final Lock lock;
  final AndroidSurfacePropertyWriter _writeProperty;
  final String vo;
  final bool compatibilityMode;

  int? _wid;
  int _width = 1;
  int _height = 1;
  bool _initialized = false;
  bool _dirty = true;
  bool _closed = false;

  /// Writes initial mpv properties and binds the latest surface atomically.
  Future<void> initialize(Map<String, String> properties) {
    return lock.synchronized(() async {
      if (_closed) return;

      if (!_initialized) {
        for (final entry in properties.entries) {
          await _writeProperty(entry.key, entry.value);
        }
        _initialized = true;
        _dirty = true;
      }

      if (_dirty) {
        await _bindCurrentSurface();
      }
    });
  }

  /// Handles a native resize and updates controller notifiers under the lock.
  Future<void> handleResize({
    required int? wid,
    required int width,
    required int height,
    required FutureOr<void> Function() updateNotifiers,
  }) {
    return lock.synchronized(() async {
      if (_closed) return;
      _setSurface(wid: wid, width: width, height: height);
      await updateNotifiers();
      if (_initialized && _dirty) {
        await _bindCurrentSurface();
      }
    });
  }

  /// Applies a wid notifier change using the same serialized property path.
  Future<void> updateSurface({
    required int? wid,
    required int width,
    required int height,
  }) {
    return lock.synchronized(() async {
      if (_closed) return;
      _setSurface(wid: wid, width: width, height: height);
      if (_initialized && _dirty) {
        await _bindCurrentSurface();
      }
    });
  }

  /// Runs video-parameter work in the controller's serialized lifecycle.
  Future<void> runExclusive(Future<void> Function() action) {
    return lock.synchronized(() async {
      if (_closed) return;
      await action();
    });
  }

  /// Enables the configured output only after initialization and a valid wid.
  ///
  /// [isRectValid] is evaluated while [lock] is held, so callers can safely
  /// check their current notifier state without taking the lock again.
  Future<void> onLoad({bool Function()? isRectValid}) {
    return lock.synchronized(() async {
      if (_closed || !_initialized || _dirty || _wid == null || _wid == 0) {
        return;
      }
      if (!(isRectValid?.call() ?? (_width > 1 && _height > 1))) {
        return;
      }
      await _writeProperty('vo', vo);
    });
  }

  /// Detaches mpv's output before the video output is unloaded.
  Future<void> onUnload() {
    return lock.synchronized(() async {
      if (_closed) return;
      await _writeProperty('vo', 'null');
    });
  }

  /// Closes the binding before running notifier and controller cleanup.
  Future<void> close(Future<void> Function() cleanup) {
    return lock.synchronized(() async {
      if (_closed) return;
      _closed = true;
      await cleanup();
    });
  }

  void _setSurface({
    required int? wid,
    required int width,
    required int height,
  }) {
    if (_wid == wid && _width == width && _height == height) return;
    _wid = wid;
    _width = width;
    _height = height;
    _dirty = true;
  }

  Future<void> _bindCurrentSurface() async {
    final wid = _wid ?? 0;
    final attached = wid != 0;

    // Reinitialize --vo after the surface size and wid have been assigned.
    await _writeProperty('vo', 'null');
    await _writeProperty('android-surface-size', '${_width}x$_height');
    await _writeProperty('wid', '$wid');
    await _writeProperty('vo', attached ? vo : 'null');

    // Reinitialize --vid for mediacodec_embed after changing --vo.
    if (compatibilityMode) {
      await _writeProperty('vid', attached ? 'auto' : 'no');
    }

    _dirty = false;
  }
}
