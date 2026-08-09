import 'dart:math' as math;

import 'package:simple_live_core/simple_live_core.dart';

typedef MpvPlaybackSpeedWriter = Future<void> Function(double speed);
typedef MpvPlaybackSpeedReader = Future<double?> Function();

/// Thresholds for one live-stream catch-up loop.
class MpvLiveLatencyChasePolicy {
  const MpvLiveLatencyChasePolicy._({
    required this.enabled,
    required this.stopThresholdSeconds,
    required this.resumeThresholdSeconds,
    required this.hardFloorSeconds,
    required this.maximumCatchUpMultiplier,
  });

  const MpvLiveLatencyChasePolicy.disabled()
      : enabled = false,
        stopThresholdSeconds = 0,
        resumeThresholdSeconds = 0,
        hardFloorSeconds = 0,
        maximumCatchUpMultiplier = 1;

  final bool enabled;
  final double stopThresholdSeconds;
  final double resumeThresholdSeconds;
  final double hardFloorSeconds;
  final double maximumCatchUpMultiplier;

  factory MpvLiveLatencyChasePolicy.forStream({
    required String latencyMode,
    required LiveStreamProtocol protocol,
  }) {
    if (latencyMode == 'off') {
      return const MpvLiveLatencyChasePolicy.disabled();
    }
    if (protocol == LiveStreamProtocol.unknown) {
      return const MpvLiveLatencyChasePolicy.disabled();
    }

    final isLowLatencyProtocol = protocol == LiveStreamProtocol.flv ||
        protocol == LiveStreamProtocol.rtmp;
    final isAggressive = latencyMode == 'aggressive';
    if (isLowLatencyProtocol) {
      return MpvLiveLatencyChasePolicy._(
        enabled: true,
        stopThresholdSeconds: isAggressive ? 0.8 : 1.2,
        resumeThresholdSeconds: isAggressive ? 1.4 : 2.0,
        hardFloorSeconds: isAggressive ? 0.4 : 0.6,
        maximumCatchUpMultiplier: isAggressive ? 1.08 : 1.06,
      );
    }

    return MpvLiveLatencyChasePolicy._(
      enabled: true,
      stopThresholdSeconds: isAggressive ? 1.4 : 1.8,
      resumeThresholdSeconds: isAggressive ? 2.4 : 3.0,
      hardFloorSeconds: isAggressive ? 0.8 : 1.0,
      maximumCatchUpMultiplier: isAggressive ? 1.06 : 1.04,
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
    this.bufferingCooldown = const Duration(seconds: 15),
    this.safetyCooldown = const Duration(seconds: 10),
    this.predictionHorizon = const Duration(seconds: 3),
    DateTime Function()? clock,
    void Function(Object error)? onWriteError,
  })  : _writeSpeed = writeSpeed,
        _readSpeed = readSpeed,
        _clock = clock ?? DateTime.now,
        _onWriteError = onWriteError;

  static const double normalSpeed = 1.0;

  /// Small, quantized catch-up steps avoid consuming the safety cache at a
  /// fixed high rate all the way to the live edge.
  static const double minimumCatchUpDelta = 0.01;

  final MpvPlaybackSpeedWriter _writeSpeed;
  final MpvPlaybackSpeedReader? _readSpeed;
  final DateTime Function() _clock;
  final void Function(Object error)? _onWriteError;
  final Duration minimumDwell;
  final Duration bufferingCooldown;
  final Duration safetyCooldown;
  final Duration predictionHorizon;

  MpvLiveLatencyChasePolicy _policy =
      const MpvLiveLatencyChasePolicy.disabled();
  DateTime? _lastSpeedChangeAt;
  double _currentSpeed = normalSpeed;
  double _baselineSpeed = normalSpeed;
  bool _hasBaselineSpeed = false;
  bool _baselineRestorePending = false;
  bool _catchingUp = false;
  bool _enabled = false;
  DateTime? _cooldownUntil;
  DateTime? _previousSampledAt;
  double? _previousCacheSeconds;
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
      final streamPolicy = MpvLiveLatencyChasePolicy.forStream(
        latencyMode: latencyMode,
        protocol: protocol,
      );
      // Respect explicit user playback speeds. The captured value is still
      // retained so lifecycle cleanup can restore it, but automatic chasing
      // must never multiply a deliberately slow or fast baseline.
      final usesChaseSafeBaseline =
          capturedSpeed >= 0.95 && capturedSpeed <= 1.05;
      _policy = usesChaseSafeBaseline
          ? streamPolicy
          : const MpvLiveLatencyChasePolicy.disabled();
      _enabled = _policy.enabled;
      _catchingUp = false;
      _cooldownUntil = null;
      _clearCacheTrend();
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
    if (isBuffering) {
      await _enterSafetyCooldown(now, bufferingCooldown);
      _clearCacheTrend();
      return;
    }
    if (cache == null || !cache.isFinite || cache < 0) {
      await _enterSafetyCooldown(now, safetyCooldown);
      _clearCacheTrend();
      return;
    }

    final cacheSlope = _recordCacheSample(cache, now);
    final predictedCache = cacheSlope == null
        ? cache
        : cache +
            cacheSlope *
                (predictionHorizon.inMicroseconds /
                    Duration.microsecondsPerSecond);
    if (cache <= _policy.hardFloorSeconds ||
        predictedCache <= _policy.hardFloorSeconds ||
        (cacheSlope != null && cacheSlope < -0.10)) {
      await _enterSafetyCooldown(now, safetyCooldown);
      return;
    }

    final cooldownUntil = _cooldownUntil;
    if (cooldownUntil != null && now.isBefore(cooldownUntil)) {
      _catchingUp = false;
      await _restoreNormalSpeed(now, bypassDwell: true);
      return;
    }
    if (cooldownUntil != null) {
      _cooldownUntil = null;
    }

    if (cache <= _policy.stopThresholdSeconds) {
      _catchingUp = false;
      await _restoreNormalSpeed(now, bypassDwell: true);
      return;
    }

    final shouldCatchUp = _catchingUp
        ? cache > _policy.stopThresholdSeconds
        : cache >= _policy.resumeThresholdSeconds;
    if (shouldCatchUp) {
      _catchingUp = true;
      final desiredSpeed = _catchUpSpeedFor(cache, cacheSlope: cacheSlope);
      if (_canChangeSpeed(now, desiredSpeed)) {
        await _applySpeed(desiredSpeed, sampledAt: now);
      }
      return;
    }

    _catchingUp = false;
    await _restoreNormalSpeed(now, bypassDwell: true);
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
      _cooldownUntil = null;
      _clearCacheTrend();
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
      _cooldownUntil = null;
      _clearCacheTrend();
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

  double _catchUpSpeedFor(
    double cacheDurationSeconds, {
    required double? cacheSlope,
  }) {
    final maxDelta = _policy.maximumCatchUpMultiplier - normalSpeed;
    double delta;
    if (cacheDurationSeconds >= 5) {
      delta = maxDelta;
    } else if (cacheDurationSeconds >= 3) {
      delta = math.min(maxDelta, 0.05);
    } else if (cacheDurationSeconds >= _policy.resumeThresholdSeconds) {
      delta = math.min(maxDelta, 0.03);
    } else if (cacheDurationSeconds >= _policy.stopThresholdSeconds + 0.5) {
      delta = math.min(maxDelta, 0.02);
    } else {
      delta = math.min(maxDelta, minimumCatchUpDelta);
    }

    // A falling cache moves down one speed step before prediction reaches the
    // hard floor. A steep fall is handled above as an immediate protection.
    if (cacheSlope != null && cacheSlope < -0.02) {
      delta = math.max(minimumCatchUpDelta, delta - 0.01);
    }
    final multiplier = normalSpeed + delta;
    return _baselineSpeed * multiplier;
  }

  bool _canChangeSpeed(DateTime now, double desiredSpeed) {
    if ((desiredSpeed - _currentSpeed).abs() < 0.001) {
      return false;
    }
    // Reducing catch-up speed is a safety action. Only increases are subject
    // to the dwell that protects the native player from write churn.
    if (desiredSpeed < _currentSpeed) {
      return true;
    }
    final changedAt = _lastSpeedChangeAt;
    return changedAt == null || now.difference(changedAt) >= minimumDwell;
  }

  Future<void> _enterSafetyCooldown(DateTime now, Duration duration) async {
    final proposedUntil = now.add(duration);
    final currentUntil = _cooldownUntil;
    if (currentUntil == null || proposedUntil.isAfter(currentUntil)) {
      _cooldownUntil = proposedUntil;
    }
    _catchingUp = false;
    await _restoreNormalSpeed(now, bypassDwell: true);
  }

  double? _recordCacheSample(double cacheSeconds, DateTime sampledAt) {
    double? slope;
    final previousAt = _previousSampledAt;
    final previousCache = _previousCacheSeconds;
    if (previousAt != null && previousCache != null) {
      final elapsedMicros = sampledAt.difference(previousAt).inMicroseconds;
      if (elapsedMicros > 0) {
        slope = (cacheSeconds - previousCache) /
            (elapsedMicros / Duration.microsecondsPerSecond);
      }
    }
    _previousSampledAt = sampledAt;
    _previousCacheSeconds = cacheSeconds;
    return slope;
  }

  void _clearCacheTrend() {
    _previousSampledAt = null;
    _previousCacheSeconds = null;
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
