import 'dart:math' as math;

import 'package:simple_live_core/simple_live_core.dart';

typedef MpvPlaybackSpeedWriter = Future<void> Function(double speed);
typedef MpvPlaybackSpeedReader = Future<double?> Function();

/// Thresholds for one live-stream catch-up loop.
class MpvLiveLatencyChasePolicy {
  const MpvLiveLatencyChasePolicy._({
    required this.enabled,
    required this.targetCacheSeconds,
    required this.catchUpThresholdSeconds,
    required this.releaseThresholdSeconds,
    required this.minimumCacheSeconds,
  });

  const MpvLiveLatencyChasePolicy.disabled()
      : enabled = false,
        targetCacheSeconds = 0,
        catchUpThresholdSeconds = 0,
        releaseThresholdSeconds = 0,
        minimumCacheSeconds = 0;

  final bool enabled;
  final double targetCacheSeconds;
  final double catchUpThresholdSeconds;
  final double releaseThresholdSeconds;
  final double minimumCacheSeconds;

  factory MpvLiveLatencyChasePolicy.forStream({
    required String latencyMode,
    required LiveStreamProtocol protocol,
  }) {
    if (latencyMode == 'off') {
      return const MpvLiveLatencyChasePolicy.disabled();
    }

    final isLowLatencyProtocol = protocol == LiveStreamProtocol.flv ||
        protocol == LiveStreamProtocol.rtmp;
    final targetCacheSeconds =
        latencyMode == 'aggressive' || isLowLatencyProtocol ? 0.5 : 1.0;
    final catchUpMargin = targetCacheSeconds <= 0.5 ? 0.35 : 0.5;
    final releaseMargin = targetCacheSeconds <= 0.5 ? 0.1 : 0.2;
    return MpvLiveLatencyChasePolicy._(
      enabled: true,
      targetCacheSeconds: targetCacheSeconds,
      catchUpThresholdSeconds: targetCacheSeconds + catchUpMargin,
      releaseThresholdSeconds: targetCacheSeconds + releaseMargin,
      minimumCacheSeconds: targetCacheSeconds * 0.6,
    );
  }
}

/// Gently brings a libmpv live stream back toward its intended cache window.
///
/// The loop raises playback speed relative to the stream's original speed.
/// Buffering, missing telemetry, and low cache have priority over the dwell
/// timer and restore that original speed immediately.
class MpvLiveLatencyChaseService {
  MpvLiveLatencyChaseService({
    required MpvPlaybackSpeedWriter writeSpeed,
    MpvPlaybackSpeedReader? readSpeed,
    this.minimumDwell = const Duration(seconds: 10),
    DateTime Function()? clock,
    void Function(Object error)? onWriteError,
  })  : _writeSpeed = writeSpeed,
        _readSpeed = readSpeed,
        _clock = clock ?? DateTime.now,
        _onWriteError = onWriteError;

  static const double normalSpeed = 1.0;

  /// Catch-up multipliers applied to the speed present before chasing starts.
  static const double minimumCatchUpSpeed = 1.05;
  static const double maximumCatchUpSpeed = 1.08;

  final MpvPlaybackSpeedWriter _writeSpeed;
  final MpvPlaybackSpeedReader? _readSpeed;
  final DateTime Function() _clock;
  final void Function(Object error)? _onWriteError;
  final Duration minimumDwell;

  MpvLiveLatencyChasePolicy _policy =
      const MpvLiveLatencyChasePolicy.disabled();
  DateTime? _lastSpeedChangeAt;
  double _currentSpeed = normalSpeed;
  double _baselineSpeed = normalSpeed;
  bool _hasBaselineSpeed = false;
  bool _baselineRestorePending = false;
  bool _catchingUp = false;
  bool _enabled = false;
  Future<void> _operationChain = Future<void>.value();

  bool get isEnabled => _enabled;
  bool get isCatchingUp => _catchingUp;
  bool get isBaselineRestorePending => _baselineRestorePending;
  double get currentSpeed => _currentSpeed;
  double get baselineSpeed => _baselineSpeed;
  MpvLiveLatencyChasePolicy get policy => _policy;

  /// Resets the current stream before sampling its cache duration.
  Future<void> start({
    required String latencyMode,
    required LiveStreamProtocol protocol,
    double? baselineSpeed,
    DateTime? startedAt,
  }) {
    return _enqueue(() async {
      final now = startedAt ?? _clock();
      if (!await _restoreBaselineSpeed(now, bypassDwell: true)) {
        return;
      }
      final capturedSpeed = await _captureBaselineSpeed(baselineSpeed);
      if (capturedSpeed == null) {
        _policy = const MpvLiveLatencyChasePolicy.disabled();
        _disable();
        return;
      }
      _baselineSpeed = capturedSpeed;
      _hasBaselineSpeed = true;
      _currentSpeed = capturedSpeed;
      _baselineRestorePending = false;
      _policy = MpvLiveLatencyChasePolicy.forStream(
        latencyMode: latencyMode,
        protocol: protocol,
      );
      _enabled = _policy.enabled;
      _catchingUp = false;
      _lastSpeedChangeAt = null;
    });
  }

  /// Consumes the latest [demuxer-cache-duration] sample.
  Future<void> observe({
    required double? cacheDurationSeconds,
    bool isBuffering = false,
    DateTime? sampledAt,
  }) {
    return _enqueue(() {
      return _observe(
        cacheDurationSeconds: cacheDurationSeconds,
        isBuffering: isBuffering,
        sampledAt: sampledAt,
      );
    });
  }

  Future<void> _observe({
    required double? cacheDurationSeconds,
    required bool isBuffering,
    required DateTime? sampledAt,
  }) async {
    if (!_enabled) {
      return;
    }
    final now = sampledAt ?? _clock();
    final cache = cacheDurationSeconds;
    if (isBuffering ||
        cache == null ||
        !cache.isFinite ||
        cache < 0 ||
        cache <= _policy.minimumCacheSeconds) {
      _catchingUp = false;
      await _restoreNormalSpeed(now, bypassDwell: true);
      return;
    }

    final shouldCatchUp = _catchingUp
        ? cache > _policy.releaseThresholdSeconds
        : cache >= _policy.catchUpThresholdSeconds;
    if (shouldCatchUp) {
      _catchingUp = true;
      final desiredSpeed = _catchUpSpeedFor(cache);
      if (_canChangeSpeed(now, desiredSpeed)) {
        await _applySpeed(desiredSpeed, sampledAt: now);
      }
      return;
    }

    _catchingUp = false;
    await _restoreNormalSpeed(now);
  }

  /// Immediately drops back to the saved baseline after a buffering signal.
  Future<void> protect({DateTime? sampledAt}) {
    return observe(
      cacheDurationSeconds: null,
      isBuffering: true,
      sampledAt: sampledAt,
    );
  }

  /// Clears accumulated state while keeping the configured stream active.
  Future<void> reset({DateTime? sampledAt}) {
    return _enqueue(() async {
      _catchingUp = false;
      _lastSpeedChangeAt = null;
      await _restoreBaselineSpeed(
        sampledAt ?? _clock(),
        bypassDwell: true,
        trackDwell: false,
      );
    });
  }

  /// Stops the loop and restores the saved baseline before player disposal.
  Future<void> stop({DateTime? stoppedAt}) {
    return _enqueue(() async {
      _enabled = false;
      _catchingUp = false;
      _lastSpeedChangeAt = null;
      _policy = const MpvLiveLatencyChasePolicy.disabled();
      final restored = await _restoreBaselineSpeed(
        stoppedAt ?? _clock(),
        bypassDwell: true,
        trackDwell: false,
      );
      if (restored && !_baselineRestorePending) {
        _hasBaselineSpeed = false;
        _baselineSpeed = normalSpeed;
        _currentSpeed = normalSpeed;
      }
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _operationChain.then((_) => operation());
    _operationChain = result.catchError((Object _) {});
    return result;
  }

  double _catchUpSpeedFor(double cacheDurationSeconds) {
    final excess = cacheDurationSeconds - _policy.catchUpThresholdSeconds;
    final multiplier = (minimumCatchUpSpeed + math.min(0.03, excess * 0.02))
        .clamp(minimumCatchUpSpeed, maximumCatchUpSpeed)
        .toDouble();
    return _baselineSpeed * multiplier;
  }

  bool _canChangeSpeed(DateTime now, double desiredSpeed) {
    if ((desiredSpeed - _currentSpeed).abs() < 0.001) {
      return false;
    }
    final changedAt = _lastSpeedChangeAt;
    return changedAt == null || now.difference(changedAt) >= minimumDwell;
  }

  Future<bool> _restoreNormalSpeed(
    DateTime now, {
    bool bypassDwell = false,
  }) {
    return _restoreBaselineSpeed(now, bypassDwell: bypassDwell);
  }

  Future<bool> _restoreBaselineSpeed(
    DateTime now, {
    required bool bypassDwell,
    bool trackDwell = true,
  }) async {
    if (!_hasBaselineSpeed ||
        (!_baselineRestorePending &&
            (_baselineSpeed - _currentSpeed).abs() < 0.001)) {
      return true;
    }
    if (!bypassDwell && !_canChangeSpeed(now, _baselineSpeed)) {
      return true;
    }
    return _applySpeed(
      _baselineSpeed,
      sampledAt: now,
      trackDwell: trackDwell,
      force: _baselineRestorePending,
    );
  }

  Future<double?> _captureBaselineSpeed(double? requestedSpeed) async {
    double? speed = requestedSpeed;
    if (speed == null) {
      try {
        speed = _readSpeed == null ? normalSpeed : await _readSpeed!.call();
      } catch (_) {
        return null;
      }
    }
    if (speed == null || !speed.isFinite || speed <= 0) {
      return null;
    }
    return speed;
  }

  Future<bool> _applySpeed(
    double speed, {
    required DateTime sampledAt,
    bool trackDwell = true,
    bool force = false,
  }) async {
    if (!force && (speed - _currentSpeed).abs() < 0.001) {
      return true;
    }
    try {
      await _writeSpeed(speed);
      _currentSpeed = speed;
      _baselineRestorePending = (speed - _baselineSpeed).abs() >= 0.001;
      if (trackDwell) {
        _lastSpeedChangeAt = sampledAt;
      }
      return true;
    } catch (error) {
      _baselineRestorePending = true;
      _disable(error);
      if ((speed - _baselineSpeed).abs() >= 0.001) {
        try {
          await _writeSpeed(_baselineSpeed);
          _currentSpeed = _baselineSpeed;
          _baselineRestorePending = false;
        } catch (_) {
          // The native player may already be disposing; no error escapes.
        }
      }
      return false;
    }
  }

  void _disable([Object? error]) {
    _catchingUp = false;
    _enabled = false;
    if (error != null) {
      try {
        _onWriteError?.call(error);
      } catch (_) {
        // Error reporting must not prevent restoration of the baseline speed.
      }
    }
  }
}
