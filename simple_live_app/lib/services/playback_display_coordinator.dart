import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// The only platform-facing gateway used to control playback display state.
///
/// Keeping this boundary small makes lease aggregation and stale-request
/// handling testable without invoking platform channels.
abstract interface class PlaybackDisplayGateway {
  bool get requiresImmersiveRecheck;

  Future<void> setKeepScreenAwake(bool enabled);

  Future<void> setImmersiveSystemUi(bool immersive);
}

class FlutterPlaybackDisplayGateway implements PlaybackDisplayGateway {
  bool get _isSupportedMobile {
    return !Utils.isOhos && (Platform.isAndroid || Platform.isIOS);
  }

  @override
  bool get requiresImmersiveRecheck => _isSupportedMobile && Platform.isIOS;

  @override
  Future<void> setKeepScreenAwake(bool enabled) async {
    if (!_isSupportedMobile) {
      return;
    }
    if (enabled) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  }

  @override
  Future<void> setImmersiveSystemUi(bool immersive) async {
    if (!_isSupportedMobile) {
      return;
    }
    Log.d('SystemUi: coordinator apply immersive=$immersive');
    if (!immersive) {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
      return;
    }
    if (Platform.isIOS) {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: const [],
      );
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
}

typedef PlaybackDisplayFrameScheduler = void Function(VoidCallback callback);
typedef PlaybackDisplayDelay = Future<void> Function(Duration duration);

/// Coordinates display state for every playback surface in the application.
///
/// Keep-awake is the union of all active leases. System UI follows the newest
/// active lease, which lets a pushed route take control while allowing the
/// underlying route to resume automatically when the top lease is disposed.
class PlaybackDisplayCoordinator extends GetxService
    with WidgetsBindingObserver {
  PlaybackDisplayCoordinator({
    PlaybackDisplayGateway? gateway,
    PlaybackDisplayFrameScheduler? scheduleAfterFrame,
    PlaybackDisplayDelay? delay,
    Duration metricsDebounceDuration = const Duration(milliseconds: 350),
  })  : _gateway = gateway ?? FlutterPlaybackDisplayGateway(),
        _scheduleAfterFrame = scheduleAfterFrame ?? _defaultScheduleAfterFrame,
        _delay = delay ?? Future<void>.delayed,
        _metricsDebounceDuration = metricsDebounceDuration;

  static PlaybackDisplayCoordinator get instance => Get.find();

  final PlaybackDisplayGateway _gateway;
  final PlaybackDisplayFrameScheduler _scheduleAfterFrame;
  final PlaybackDisplayDelay _delay;
  final Duration _metricsDebounceDuration;
  final Map<int, _PlaybackDisplayLeaseState> _leases = {};

  Timer? _metricsDebounce;

  bool _initialized = false;
  bool _appActive = true;
  bool _foregroundRestorePending = false;
  bool? _appliedKeepAwake;
  bool? _appliedImmersive;
  int _nextLeaseId = 0;
  int _nextOrder = 0;
  int _resumeGeneration = 0;
  int _revision = 0;
  int _appliedRevision = -1;
  Future<void>? _drainFuture;

  static void _defaultScheduleAfterFrame(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
  }

  Future<void> initialize() async {
    if (_initialized) {
      return settle();
    }
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _invalidate();
    await settle();
  }

  PlaybackDisplayLease acquire({
    String? debugLabel,
    bool keepScreenAwake = false,
    bool immersiveSystemUi = false,
    bool active = true,
  }) {
    final id = ++_nextLeaseId;
    _leases[id] = _PlaybackDisplayLeaseState(
      debugLabel: debugLabel,
      keepScreenAwake: keepScreenAwake,
      immersiveSystemUi: immersiveSystemUi,
      active: active,
      order: ++_nextOrder,
    );
    _invalidate();
    return PlaybackDisplayLease._(this, id);
  }

  @visibleForTesting
  int get activeLeaseCount =>
      _leases.values.where((lease) => lease.active).length;

  @visibleForTesting
  int get revision => _revision;

  void _updateLease(
    int id, {
    bool? keepScreenAwake,
    bool? immersiveSystemUi,
    bool? active,
  }) {
    final lease = _leases[id];
    if (lease == null) {
      return;
    }
    var changed = false;
    if (keepScreenAwake != null && lease.keepScreenAwake != keepScreenAwake) {
      lease.keepScreenAwake = keepScreenAwake;
      changed = true;
    }
    if (immersiveSystemUi != null &&
        lease.immersiveSystemUi != immersiveSystemUi) {
      lease.immersiveSystemUi = immersiveSystemUi;
      changed = true;
    }
    if (active != null && lease.active != active) {
      lease.active = active;
      if (active) {
        lease.order = ++_nextOrder;
      }
      changed = true;
    }
    if (changed) {
      _invalidate();
    }
  }

  void _releaseLease(int id) {
    if (_leases.remove(id) != null) {
      _invalidate();
    }
  }

  @override
  void didChangeMetrics() {
    // iPad 旋转/尺寸变化（含台前调度窗口调整）完成后，UIKit 会重新评估
    // 状态栏外观，把 immersive 隐藏覆盖掉。合并短时间内的连续变化，
    // 延迟后强制重新应用，覆盖"旋转动画结束、viewport 更新"的时刻。
    if (!_appActive || !_gateway.requiresImmersiveRecheck || !_desiredImmersive) {
      return;
    }
    _metricsDebounce?.cancel();
    _metricsDebounce = Timer(_metricsDebounceDuration, () {
      if (_appActive && _desiredImmersive) {
        // 强制重应用：置 null 使 drain 重新执行平台调用。
        _appliedImmersive = null;
        _invalidate();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _resumeGeneration += 1;
      _foregroundRestorePending = false;
      if (_appActive) {
        _appActive = false;
        _invalidate();
      }
      return;
    }
    if (state != AppLifecycleState.resumed) {
      return;
    }

    // Keep the inactive state until the first foreground frame. Besides
    // preventing premature wake-lock restoration, this invalidates any stale
    // delayed iOS fullscreen request from the previous lifecycle.
    _appActive = false;
    _foregroundRestorePending = true;
    _invalidate();
    final resumeGeneration = ++_resumeGeneration;
    _scheduleAfterFrame(() {
      if (!_foregroundRestorePending || resumeGeneration != _resumeGeneration) {
        return;
      }
      _foregroundRestorePending = false;
      _appActive = true;
      _invalidate();
    });
  }

  bool get _desiredKeepAwake {
    return _appActive &&
        _leases.values.any(
          (lease) => lease.active && lease.keepScreenAwake,
        );
  }

  bool get _desiredImmersive {
    if (!_appActive) {
      return false;
    }
    _PlaybackDisplayLeaseState? latest;
    for (final lease in _leases.values) {
      if (lease.active && (latest == null || lease.order > latest.order)) {
        latest = lease;
      }
    }
    return latest?.immersiveSystemUi ?? false;
  }

  void _invalidate() {
    _revision += 1;
    _ensureDrain();
  }

  void _ensureDrain() {
    _drainFuture ??= _drain().whenComplete(() {
      _drainFuture = null;
      if (_appliedRevision != _revision) {
        _ensureDrain();
      }
    });
  }

  Future<void> _drain() async {
    while (_appliedRevision != _revision) {
      final operationRevision = _revision;
      final keepAwake = _desiredKeepAwake;
      final immersive = _desiredImmersive;
      Log.d('SystemUi: coordinator drain revision=$_revision keepAwake=$keepAwake immersive=$immersive appliedRev=$_appliedRevision appliedImm=$_appliedImmersive');

      if (_appliedKeepAwake != keepAwake) {
        try {
          await _gateway.setKeepScreenAwake(keepAwake);
        } catch (error) {
          Log.d('Failed to update playback wakelock: $error');
        }
        _appliedKeepAwake = keepAwake;
      }
      if (operationRevision != _revision) {
        continue;
      }

      if (_appliedImmersive != immersive) {
        try {
          await _gateway.setImmersiveSystemUi(immersive);
        } catch (error) {
          Log.d('Failed to update playback system UI: $error');
        }
        _appliedImmersive = immersive;
      }
      if (operationRevision != _revision) {
        continue;
      }

      if (immersive && _gateway.requiresImmersiveRecheck) {
        Log.d('SystemUi: coordinator iOS recheck scheduled');
        await _delay(const Duration(milliseconds: 120));
        if (operationRevision != _revision || !_desiredImmersive) {
          continue;
        }
        try {
          await _gateway.setImmersiveSystemUi(true);
        } catch (error) {
          Log.d('Failed to reapply iOS playback system UI: $error');
        }
      }
      if (operationRevision == _revision) {
        _appliedRevision = operationRevision;
      }
    }
  }

  Future<void> settle() async {
    while (_drainFuture != null) {
      await _drainFuture;
    }
  }

  @override
  void onClose() {
    _metricsDebounce?.cancel();
    _metricsDebounce = null;
    if (_initialized) {
      WidgetsBinding.instance.removeObserver(this);
      _initialized = false;
    }
    _leases.clear();
    super.onClose();
  }
}

class PlaybackDisplayLease {
  PlaybackDisplayLease._(this._coordinator, this._id);

  final PlaybackDisplayCoordinator _coordinator;
  final int _id;
  bool _disposed = false;

  void setKeepScreenAwake(bool enabled) {
    if (!_disposed) {
      _coordinator._updateLease(_id, keepScreenAwake: enabled);
    }
  }

  void setImmersiveSystemUi(bool immersive) {
    if (!_disposed) {
      _coordinator._updateLease(_id, immersiveSystemUi: immersive);
    }
  }

  void setActive(bool active) {
    if (!_disposed) {
      _coordinator._updateLease(_id, active: active);
    }
  }

  Future<void> settle() => _coordinator.settle();

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _coordinator._releaseLease(_id);
  }
}

class _PlaybackDisplayLeaseState {
  _PlaybackDisplayLeaseState({
    required this.debugLabel,
    required this.keepScreenAwake,
    required this.immersiveSystemUi,
    required this.active,
    required this.order,
  });

  final String? debugLabel;
  bool keepScreenAwake;
  bool immersiveSystemUi;
  bool active;
  int order;
}
