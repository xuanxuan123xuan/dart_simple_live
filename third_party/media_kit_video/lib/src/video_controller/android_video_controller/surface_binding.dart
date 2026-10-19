import 'dart:async';

import 'package:synchronized/synchronized.dart';

typedef AndroidSurfacePropertyWriter = Future<void> Function(
    String key, String value);
typedef AndroidSurfaceDiagnosticCallback = void Function(
  String event,
  Map<String, Object?> fields,
);

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
    this.onDiagnostic,
  })  : lock = lock ?? Lock(),
        _writeProperty = writeProperty;

  final Lock lock;
  final AndroidSurfacePropertyWriter _writeProperty;
  final AndroidSurfaceDiagnosticCallback? onDiagnostic;
  final String vo;
  final bool compatibilityMode;

  int? _wid;
  int _width = 1;
  int _height = 1;
  bool _initialized = false;
  bool _dirty = true;
  bool _closed = false;
  bool _videoEnabled = true;

  /// Writes initial mpv properties and binds the latest surface atomically.
  Future<void> initialize(Map<String, String> properties) {
    return lock.synchronized(() async {
      if (_closed) return;

      final initializing = !_initialized;
      if (initializing) {
        _diagnose('init', {
          'stage': 'properties_start',
          'wid': _wid ?? 0,
          'width': _width,
          'height': _height,
          'level': 'info',
        });
      }

      try {
        if (initializing) {
          for (final entry in properties.entries) {
            final value =
                entry.key == 'vid' && !_videoEnabled ? 'no' : entry.value;
            await _writeProperty(entry.key, value);
          }
          _initialized = true;
          _dirty = true;
        }

        if (_dirty) {
          await _bindCurrentSurface(
            oldWid: _wid ?? 0,
            reason: initializing ? 'initialization' : 'retry',
          );
        }

        if (initializing) {
          _diagnose('init', {
            'stage': 'initialized',
            'wid': _wid ?? 0,
            'width': _width,
            'height': _height,
            'level': 'info',
          });
        }
      } catch (error) {
        if (initializing) {
          _diagnose('init', {
            'stage': 'initialization_failed',
            'wid': _wid ?? 0,
            'width': _width,
            'height': _height,
            'reason': 'property_write_failed',
            'level': 'error',
            'error': error.runtimeType.toString(),
          });
        }
        rethrow;
      }
    });
  }

  /// Handles a native resize and updates controller notifiers under the lock.
  Future<void> handleResize({
    required int? wid,
    required int width,
    required int height,
    required FutureOr<void> Function() updateNotifiers,
    int? textureId,
  }) {
    return lock.synchronized(() async {
      if (_closed) return;
      final oldWid = _wid ?? 0;
      final changed = _setSurface(wid: wid, width: width, height: height);
      await updateNotifiers();
      _diagnose('texture_update', {
        if (textureId != null) 'textureId': textureId,
        'oldWid': oldWid,
        'wid': wid ?? 0,
        'width': width,
        'height': height,
        'valid': wid != null && wid != 0,
        'reason':
            wid == null || wid == 0 ? 'surface_detached' : 'surface_updated',
        'level': 'info',
        'stage': 'resize_received',
      });
      if (_initialized && _dirty) {
        await _bindCurrentSurface(
          oldWid: oldWid,
          reason: changed ? 'surface_update' : 'retry',
        );
      }
    });
  }

  /// Applies a surface change through the single serialized resize path.
  Future<void> updateSurface({
    required int? wid,
    required int width,
    required int height,
  }) {
    return handleResize(
      wid: wid,
      width: width,
      height: height,
      updateNotifiers: () {},
    );
  }

  /// Runs video-parameter work in the controller's serialized lifecycle.
  Future<void> runExclusive(Future<void> Function() action) {
    return lock.synchronized(() async {
      if (_closed) return;
      await action();
    });
  }

  /// Enables or disables video while serializing with surface lifecycle work.
  ///
  /// When supplied, [updateVideoTrack] updates the player's track state and
  /// writes `vid` itself. The default writes the equivalent mpv property
  /// directly, which keeps this class independently testable.
  Future<void> setVideoEnabled(
    bool enabled, {
    Future<void> Function(bool enabled)? updateVideoTrack,
  }) {
    return lock.synchronized(() async {
      if (_closed) return;
      if (!_initialized) {
        _videoEnabled = enabled;
        return;
      }
      // A media load can reset mpv's track selection while the requested
      // state remains disabled, so repeat false calls must reassert `vid=no`.
      if (_videoEnabled == enabled && enabled) return;

      final previous = _videoEnabled;
      try {
        await _applyVideoEnabled(enabled, updateVideoTrack);
        _videoEnabled = enabled;
      } catch (_) {
        // A failed property write can leave mpv partway through the change.
        // Restore the previous output and track state before propagating it.
        _videoEnabled = previous;
        try {
          await _applyVideoEnabled(previous, updateVideoTrack);
        } catch (_) {
          // Keep the original failure as the operation's result.
        }
        rethrow;
      }
    });
  }

  Future<void> _applyVideoEnabled(
    bool enabled,
    Future<void> Function(bool enabled)? updateVideoTrack,
  ) async {
    final surfaceReady = _initialized &&
        !_dirty &&
        _wid != null &&
        _wid != 0 &&
        _width > 1 &&
        _height > 1;

    Future<void> setTrack() async {
      if (updateVideoTrack != null) {
        await updateVideoTrack(enabled);
      } else {
        await _writeProperty('vid', enabled ? 'auto' : 'no');
      }
    }

    if (!enabled || !surfaceReady) {
      await _writeProperty('vo', 'null');
      await setTrack();
      return;
    }

    if (compatibilityMode) {
      // mediacodec_embed must be selected before enabling its video track.
      await _writeProperty('vo', vo);
      await setTrack();
    } else {
      // Restore the track before attaching the GPU output.
      await setTrack();
      await _writeProperty('vo', vo);
    }
  }

  /// Enables the configured output only after initialization and a valid wid.
  ///
  /// [isRectValid] is evaluated while [lock] is held, so callers can safely
  /// check their current notifier state without taking the lock again.
  Future<void> onLoad({bool Function()? isRectValid}) {
    return lock.synchronized(() async {
      if (_closed) return;
      final rectValid = isRectValid?.call() ?? (_width > 1 && _height > 1);
      final hasWid = _wid != null && _wid != 0;
      final valid = _initialized && !_dirty && hasWid && rectValid;
      final reason = !_initialized
          ? 'not_initialized'
          : _dirty
              ? 'binding_incomplete'
              : !hasWid
                  ? 'invalid_wid'
                  : !rectValid
                      ? 'invalid_rect'
                      : 'surface_ready';
      _diagnose('load', {
        'wid': _wid ?? 0,
        'width': _width,
        'height': _height,
        'valid': valid,
        'reason': reason,
        'level': valid ? 'info' : 'warning',
        'stage': 'before_vo_enable',
      });
      if (!_initialized) return;
      if (!_videoEnabled) {
        try {
          await _writeProperty('vo', 'null');
          await _writeProperty('vid', 'no');
        } catch (error) {
          _diagnose('load', {
            'wid': _wid ?? 0,
            'width': _width,
            'height': _height,
            'valid': valid,
            'reason': 'property_write_failed',
            'level': 'error',
            'error': error.runtimeType.toString(),
            'stage': 'video_disable_failed',
          });
          rethrow;
        }
        return;
      }
      if (!valid) return;

      try {
        await _writeProperty('vo', vo);
      } catch (error) {
        _diagnose('load', {
          'wid': _wid ?? 0,
          'width': _width,
          'height': _height,
          'valid': true,
          'reason': 'property_write_failed',
          'level': 'error',
          'error': error.runtimeType.toString(),
          'stage': 'vo_enable_failed',
        });
        rethrow;
      }
    });
  }

  /// Detaches mpv's output before the video output is unloaded.
  Future<void> onUnload() {
    return lock.synchronized(() async {
      if (_closed) return;
      _diagnose('unload', {
        'wid': _wid ?? 0,
        'width': _width,
        'height': _height,
        'valid': _wid != null && _wid != 0,
        'reason': 'video_unload',
        'level': 'info',
        'stage': 'before_vo_detach',
      });
      try {
        await _writeProperty('vo', 'null');
        if (!_videoEnabled) {
          await _writeProperty('vid', 'no');
        }
      } catch (error) {
        _diagnose('unload', {
          'wid': _wid ?? 0,
          'width': _width,
          'height': _height,
          'valid': _wid != null && _wid != 0,
          'reason': 'property_write_failed',
          'level': 'error',
          'error': error.runtimeType.toString(),
          'stage': 'vo_detach_failed',
        });
        rethrow;
      }
    });
  }

  /// Closes the binding before running notifier and controller cleanup.
  Future<void> close(Future<void> Function() cleanup) {
    return lock.synchronized(() async {
      if (_closed) return;
      _closed = true;
      _diagnose('dispose', {
        'wid': _wid ?? 0,
        'width': _width,
        'height': _height,
        'valid': _wid != null && _wid != 0,
        'reason': 'controller_dispose',
        'level': 'info',
        'stage': 'closing',
      });
      try {
        await cleanup();
        _diagnose('dispose', {
          'wid': _wid ?? 0,
          'width': _width,
          'height': _height,
          'valid': _wid != null && _wid != 0,
          'reason': 'controller_dispose',
          'level': 'info',
          'stage': 'closed',
        });
      } catch (error) {
        _diagnose('dispose', {
          'wid': _wid ?? 0,
          'width': _width,
          'height': _height,
          'valid': _wid != null && _wid != 0,
          'reason': 'controller_dispose_failed',
          'level': 'error',
          'error': error.runtimeType.toString(),
          'stage': 'dispose_failed',
        });
        rethrow;
      }
    });
  }

  bool _setSurface({
    required int? wid,
    required int width,
    required int height,
  }) {
    if (_wid == wid && _width == width && _height == height) return false;
    _wid = wid;
    _width = width;
    _height = height;
    _dirty = true;
    return true;
  }

  Future<void> _bindCurrentSurface({
    required int oldWid,
    required String reason,
  }) async {
    final wid = _wid ?? 0;
    final attached = wid != 0;
    final fields = <String, Object?>{
      'oldWid': oldWid,
      'wid': wid,
      'width': _width,
      'height': _height,
      'valid': attached,
      'reason': reason,
      'level': 'info',
      'stage': 'surface_binding',
    };

    _diagnose('bind_start', fields);
    try {
      // Reinitialize --vo after the surface size and wid have been assigned.
      await _writeProperty('vo', 'null');
      await _writeProperty('android-surface-size', '${_width}x$_height');
      await _writeProperty('wid', '$wid');
      await _writeProperty(
        'vo',
        attached && _videoEnabled ? vo : 'null',
      );

      // Reinitialize --vid for mediacodec_embed after changing --vo.
      if (compatibilityMode) {
        await _writeProperty(
          'vid',
          attached && _videoEnabled ? 'auto' : 'no',
        );
      } else if (!_videoEnabled) {
        await _writeProperty('vid', 'no');
      }

      _dirty = false;
      _diagnose('bind_complete', fields);
    } catch (error) {
      _diagnose('bind_error', {
        ...fields,
        'reason': 'property_write_failed',
        'level': 'error',
        'error': error.runtimeType.toString(),
        'stage': 'surface_binding',
      });
      rethrow;
    }
  }

  void _diagnose(String event, Map<String, Object?> fields) {
    try {
      onDiagnostic?.call(event, Map<String, Object?>.from(fields));
    } catch (_) {
      // Diagnostic callbacks must not change surface or playback behavior.
    }
  }
}
