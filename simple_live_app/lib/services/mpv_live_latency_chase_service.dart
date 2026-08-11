import 'dart:math' as math;

import 'package:simple_live_core/simple_live_core.dart';

typedef MpvPlaybackSpeedWriter = Future<void> Function(double speed);
typedef MpvPlaybackSpeedReader = Future<double?> Function();

enum MpvLiveLatencyChaseState {
  disabled,
  settling,
  monitoring,
  catchingUp,
  protecting,
  cooldown,
}

enum MpvLiveLatencyProtectionReason {
  buffering,
  audioUnderrun,
  noData,
  insufficientThroughput,
  playbackStalled,
  lifecycleInterrupted,
  userPaused,
  sourceChanged,
  telemetryUnavailable,
  hardFloorReached,
  predictedCacheExhaustion,
  cacheFallingFast,
  catchUpBudgetExhausted,
}

/// Conservative runtime groups. These are policy defaults, not claims that a
/// device family has been calibrated on real hardware.
enum MpvLiveLatencyPlatformProfile {
  conservative,
  resourceConstrained,
  unsupported,
}

enum MpvLiveLatencyPlaybackRole {
  singleRoom,
  multiRoomPrimaryVisible,
  multiRoomSecondaryOrInactive,
}

/// Thresholds and budgets for one live-stream catch-up loop.
class MpvLiveLatencyChasePolicy {
  const MpvLiveLatencyChasePolicy._({
    required this.enabled,
    required this.platformProfile,
    required this.playbackRole,
    required this.stopThresholdSeconds,
    required this.resumeThresholdSeconds,
    required this.hardFloorSeconds,
    required this.maximumCatchUpMultiplier,
    required this.catchUpHardLimit,
    required this.monitoringSampleInterval,
    required this.catchUpSampleInterval,
    required this.nearEdgeSampleInterval,
    required this.cooldownSampleInterval,
  });

  const MpvLiveLatencyChasePolicy.disabled({
    this.platformProfile = MpvLiveLatencyPlatformProfile.conservative,
    this.playbackRole = MpvLiveLatencyPlaybackRole.singleRoom,
  })  : enabled = false,
        stopThresholdSeconds = 0,
        resumeThresholdSeconds = 0,
        hardFloorSeconds = 0,
        maximumCatchUpMultiplier = 1,
        catchUpHardLimit = Duration.zero,
        monitoringSampleInterval = Duration.zero,
        catchUpSampleInterval = Duration.zero,
        nearEdgeSampleInterval = Duration.zero,
        cooldownSampleInterval = Duration.zero;

  final bool enabled;
  final MpvLiveLatencyPlatformProfile platformProfile;
  final MpvLiveLatencyPlaybackRole playbackRole;
  final double stopThresholdSeconds;
  final double resumeThresholdSeconds;
  final double hardFloorSeconds;
  final double maximumCatchUpMultiplier;
  final Duration catchUpHardLimit;
  final Duration monitoringSampleInterval;
  final Duration catchUpSampleInterval;
  final Duration nearEdgeSampleInterval;
  final Duration cooldownSampleInterval;

  factory MpvLiveLatencyChasePolicy.forStream({
    required String latencyMode,
    required LiveStreamProtocol protocol,
    MpvLiveLatencyPlatformProfile platformProfile =
        MpvLiveLatencyPlatformProfile.conservative,
    MpvLiveLatencyPlaybackRole playbackRole =
        MpvLiveLatencyPlaybackRole.singleRoom,
  }) {
    // Only released modes are accepted. In particular, names such as
    // "sports" or "ultraLow" must not accidentally fall through to auto.
    if (latencyMode != 'auto' && latencyMode != 'aggressive') {
      return MpvLiveLatencyChasePolicy.disabled(
        platformProfile: platformProfile,
        playbackRole: playbackRole,
      );
    }
    if (protocol == LiveStreamProtocol.unknown ||
        platformProfile == MpvLiveLatencyPlatformProfile.unsupported ||
        playbackRole ==
            MpvLiveLatencyPlaybackRole.multiRoomSecondaryOrInactive) {
      return MpvLiveLatencyChasePolicy.disabled(
        platformProfile: platformProfile,
        playbackRole: playbackRole,
      );
    }

    final isLowLatencyProtocol = protocol == LiveStreamProtocol.flv ||
        protocol == LiveStreamProtocol.rtmp;
    final isConstrained =
        platformProfile == MpvLiveLatencyPlatformProfile.resourceConstrained;
    final isAggressive = latencyMode == 'aggressive' &&
        playbackRole != MpvLiveLatencyPlaybackRole.multiRoomPrimaryVisible &&
        !isConstrained;
    final configuredMaximum = isLowLatencyProtocol
        ? (isAggressive ? 1.08 : 1.06)
        : (isAggressive ? 1.06 : 1.04);
    final configuredHardLimit = isLowLatencyProtocol
        ? Duration(seconds: isAggressive ? 120 : 90)
        : Duration(seconds: isAggressive ? 90 : 60);
    return MpvLiveLatencyChasePolicy._(
      enabled: true,
      platformProfile: platformProfile,
      playbackRole: playbackRole,
      stopThresholdSeconds: isLowLatencyProtocol
          ? (isAggressive ? 0.8 : 1.2)
          : (isAggressive ? 1.4 : 1.8),
      resumeThresholdSeconds: isLowLatencyProtocol
          ? (isAggressive ? 1.4 : 2.0)
          : (isAggressive ? 2.4 : 3.0),
      hardFloorSeconds: isLowLatencyProtocol
          ? (isAggressive ? 0.4 : 0.6)
          : (isAggressive ? 0.8 : 1.0),
      maximumCatchUpMultiplier:
          isConstrained ? math.min(configuredMaximum, 1.02) : configuredMaximum,
      catchUpHardLimit:
          isConstrained && configuredHardLimit > const Duration(seconds: 60)
              ? const Duration(seconds: 60)
              : configuredHardLimit,
      monitoringSampleInterval: const Duration(seconds: 2),
      catchUpSampleInterval: isConstrained
          ? const Duration(seconds: 1)
          : const Duration(milliseconds: 500),
      // P3 deliberately keeps the documented 250-500 ms range at its
      // conservative edge until device/protocol replay data is available.
      nearEdgeSampleInterval: isConstrained
          ? const Duration(seconds: 1)
          : const Duration(milliseconds: 500),
      cooldownSampleInterval: const Duration(seconds: 1),
    );
  }
}

/// Gently brings a libmpv live stream back toward its intended cache window.
///
/// The service is intentionally player-agnostic so single-room and multi-room
/// playback share the same state machine and policy. It only writes playback
/// speed; it never reopens or switches a stream.
class MpvLiveLatencyChaseService {
  MpvLiveLatencyChaseService({
    required MpvPlaybackSpeedWriter writeSpeed,
    MpvPlaybackSpeedReader? readSpeed,
    this.minimumDwell = const Duration(seconds: 10),
    this.settlingDuration = const Duration(seconds: 10),
    this.stableObservationDuration = const Duration(seconds: 5),
    this.bufferingCooldown = const Duration(seconds: 15),
    this.safetyCooldown = const Duration(seconds: 10),
    this.budgetCooldown = const Duration(seconds: 3),
    this.predictionHorizon = const Duration(seconds: 3),
    this.maximumStableSampleGap = const Duration(seconds: 3),
    DateTime Function()? clock,
    void Function(Object error)? onWriteError,
  })  : _writeSpeed = writeSpeed,
        _readSpeed = readSpeed,
        _clock = clock ?? DateTime.now,
        _onWriteError = onWriteError;

  static const double normalSpeed = 1.0;
  static const double minimumCatchUpDelta = 0.01;
  static const double catchUpBudgetSafetyFactor = 0.60;
  static const double steepCacheFallPerSecond = -0.10;

  final MpvPlaybackSpeedWriter _writeSpeed;
  final MpvPlaybackSpeedReader? _readSpeed;
  final DateTime Function() _clock;
  final void Function(Object error)? _onWriteError;
  final Duration minimumDwell;
  final Duration settlingDuration;
  final Duration stableObservationDuration;
  final Duration bufferingCooldown;
  final Duration safetyCooldown;
  final Duration budgetCooldown;
  final Duration predictionHorizon;
  final Duration maximumStableSampleGap;

  MpvLiveLatencyChasePolicy _policy =
      const MpvLiveLatencyChasePolicy.disabled();
  MpvLiveLatencyChaseState _state = MpvLiveLatencyChaseState.disabled;
  MpvLiveLatencyProtectionReason? _lastProtectionReason;
  DateTime? _lastSpeedChangeAt;
  double _currentSpeed = normalSpeed;
  double _baselineSpeed = normalSpeed;
  bool _hasBaselineSpeed = false;
  bool _baselineRestorePending = false;
  bool _enabled = false;
  DateTime? _cooldownUntil;
  DateTime? _validPlaybackStartedAt;
  DateTime? _stableObservationStartedAt;
  DateTime? _catchUpStartedAt;
  DateTime? _catchUpDeadline;
  double? _latestCacheSeconds;
  final List<_CacheSample> _cacheSamples = <_CacheSample>[];
  Future<void> _operationChain = Future<void>.value();
  int _requestedGeneration = 0;
  int _activeGeneration = 0;

  bool get isEnabled => _enabled;
  bool get isCatchingUp => _state == MpvLiveLatencyChaseState.catchingUp;
  bool get isBaselineRestorePending => _baselineRestorePending;
  double get currentSpeed => _currentSpeed;
  double get baselineSpeed => _baselineSpeed;
  MpvLiveLatencyChasePolicy get policy => _policy;
  MpvLiveLatencyChaseState get state => _state;
  MpvLiveLatencyProtectionReason? get lastProtectionReason =>
      _lastProtectionReason;
  int get generation => _requestedGeneration;

  /// The cadence recommended to the owning sampler. A disabled policy returns
  /// null, allowing diagnostics to stop sampling chase-only telemetry.
  Duration? get recommendedSampleInterval {
    if (!_enabled) {
      return null;
    }
    switch (_state) {
      case MpvLiveLatencyChaseState.disabled:
        return null;
      case MpvLiveLatencyChaseState.settling:
      case MpvLiveLatencyChaseState.monitoring:
        if (_isNearSafetyEdge) {
          return _policy.nearEdgeSampleInterval;
        }
        return _policy.monitoringSampleInterval;
      case MpvLiveLatencyChaseState.catchingUp:
        if (_isNearSafetyEdge) {
          return _policy.nearEdgeSampleInterval;
        }
        return _policy.catchUpSampleInterval;
      case MpvLiveLatencyChaseState.protecting:
      case MpvLiveLatencyChaseState.cooldown:
        return _policy.cooldownSampleInterval;
    }
  }

  bool get _isNearSafetyEdge {
    final cache = _latestCacheSeconds;
    return cache != null && cache <= _policy.stopThresholdSeconds + 0.5;
  }

  /// Resets the current stream before sampling its cache duration.
  Future<void> start({
    required String latencyMode,
    required LiveStreamProtocol protocol,
    MpvLiveLatencyPlatformProfile platformProfile =
        MpvLiveLatencyPlatformProfile.conservative,
    MpvLiveLatencyPlaybackRole playbackRole =
        MpvLiveLatencyPlaybackRole.singleRoom,
    double? baselineSpeed,
    DateTime? startedAt,
  }) {
    final requestedGeneration = _beginGenerationRequest();
    return _enqueue(() async {
      if (!_isCurrentGeneration(requestedGeneration)) {
        return;
      }
      _activeGeneration = requestedGeneration;
      final now = startedAt ?? _clock();
      if (!await _restoreBaselineSpeed(
        now,
        bypassDwell: true,
        generation: requestedGeneration,
      )) {
        return;
      }
      if (!_isCurrentGeneration(requestedGeneration)) {
        return;
      }
      final capturedSpeed = await _captureBaselineSpeed(
        baselineSpeed,
        generation: requestedGeneration,
      );
      if (!_isCurrentGeneration(requestedGeneration)) {
        return;
      }
      if (capturedSpeed == null) {
        _policy = MpvLiveLatencyChasePolicy.disabled(
          platformProfile: platformProfile,
          playbackRole: playbackRole,
        );
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
        platformProfile: platformProfile,
        playbackRole: playbackRole,
      );
      final usesChaseSafeBaseline =
          capturedSpeed >= 0.95 && capturedSpeed <= 1.05;
      _policy = usesChaseSafeBaseline
          ? streamPolicy
          : MpvLiveLatencyChasePolicy.disabled(
              platformProfile: platformProfile,
              playbackRole: playbackRole,
            );
      _enabled = _policy.enabled;
      _state = _enabled
          ? MpvLiveLatencyChaseState.settling
          : MpvLiveLatencyChaseState.disabled;
      _cooldownUntil = null;
      _validPlaybackStartedAt = null;
      _stableObservationStartedAt = null;
      _clearCatchUpBudget();
      _clearCacheTrend();
      _lastProtectionReason = null;
      _lastSpeedChangeAt = null;
    });
  }

  /// Consumes the latest [demuxer-cache-duration] sample.
  Future<void> observe({
    required double? cacheDurationSeconds,
    bool isBuffering = false,
    DateTime? sampledAt,
    int? generation,
  }) {
    final observedGeneration = generation ?? _requestedGeneration;
    return _enqueue(() {
      if (observedGeneration != _requestedGeneration ||
          observedGeneration != _activeGeneration) {
        return Future<void>.value();
      }
      return _observe(
        cacheDurationSeconds: cacheDurationSeconds,
        isBuffering: isBuffering,
        sampledAt: sampledAt,
        generation: observedGeneration,
      );
    });
  }

  Future<void> _observe({
    required double? cacheDurationSeconds,
    required bool isBuffering,
    required DateTime? sampledAt,
    required int generation,
  }) async {
    if (!_enabled) {
      return;
    }
    final now = sampledAt ?? _clock();
    final cache = cacheDurationSeconds;
    if (isBuffering) {
      await _enterProtection(
        now,
        MpvLiveLatencyProtectionReason.buffering,
        bufferingCooldown,
        generation: generation,
      );
      return;
    }
    if (cache == null || !cache.isFinite || cache < 0) {
      await _enterProtection(
        now,
        MpvLiveLatencyProtectionReason.telemetryUnavailable,
        safetyCooldown,
        generation: generation,
      );
      return;
    }

    final previousSampledAt =
        _cacheSamples.isEmpty ? null : _cacheSamples.last.sampledAt;
    final hasSampleGap = previousSampledAt != null &&
        now.difference(previousSampledAt) > maximumStableSampleGap;
    if (hasSampleGap) {
      _clearCacheTrend();
      _stableObservationStartedAt = now;
      if (_state == MpvLiveLatencyChaseState.settling) {
        _validPlaybackStartedAt = now;
      }
    }
    _latestCacheSeconds = cache;
    _validPlaybackStartedAt ??= now;
    _stableObservationStartedAt ??= now;
    final cacheSlope = _recordCacheSample(cache, now);
    final predictedCache = cacheSlope == null
        ? cache
        : cache +
            cacheSlope *
                (predictionHorizon.inMicroseconds /
                    Duration.microsecondsPerSecond);
    if (cache <= _policy.hardFloorSeconds) {
      await _enterProtection(
        now,
        MpvLiveLatencyProtectionReason.hardFloorReached,
        safetyCooldown,
        generation: generation,
      );
      return;
    }
    if (predictedCache <= _policy.hardFloorSeconds) {
      await _enterProtection(
        now,
        MpvLiveLatencyProtectionReason.predictedCacheExhaustion,
        safetyCooldown,
        generation: generation,
      );
      return;
    }
    if (cacheSlope != null && cacheSlope < steepCacheFallPerSecond) {
      await _enterProtection(
        now,
        MpvLiveLatencyProtectionReason.cacheFallingFast,
        safetyCooldown,
        generation: generation,
      );
      return;
    }

    if (hasSampleGap && _state == MpvLiveLatencyChaseState.catchingUp) {
      _state = MpvLiveLatencyChaseState.monitoring;
      _clearCatchUpBudget();
      await _restoreNormalSpeed(
        now,
        bypassDwell: true,
        generation: generation,
      );
      return;
    }

    final cooldownUntil = _cooldownUntil;
    if (cooldownUntil != null && now.isBefore(cooldownUntil)) {
      _state = MpvLiveLatencyChaseState.cooldown;
      await _restoreNormalSpeed(
        now,
        bypassDwell: true,
        generation: generation,
      );
      return;
    }
    if (cooldownUntil != null) {
      _cooldownUntil = null;
      _state = MpvLiveLatencyChaseState.monitoring;
      _stableObservationStartedAt = now;
      _clearCacheTrend(keepLatest: true);
      return;
    }

    if (_state == MpvLiveLatencyChaseState.settling) {
      final validSince = _validPlaybackStartedAt!;
      if (now.difference(validSince) < settlingDuration) {
        await _restoreNormalSpeed(
          now,
          bypassDwell: true,
          generation: generation,
        );
        return;
      }
      _state = MpvLiveLatencyChaseState.monitoring;
      if (stableObservationDuration > Duration.zero) {
        final stableSince = _stableObservationStartedAt;
        if (stableSince == null ||
            now.difference(stableSince) < stableObservationDuration) {
          return;
        }
      }
    }

    if (cache <= _policy.stopThresholdSeconds) {
      _state = MpvLiveLatencyChaseState.monitoring;
      _clearCatchUpBudget();
      await _restoreNormalSpeed(
        now,
        bypassDwell: true,
        generation: generation,
      );
      return;
    }

    if (_state == MpvLiveLatencyChaseState.catchingUp) {
      if (_isCatchUpBudgetExhausted(now)) {
        await _enterProtection(
          now,
          MpvLiveLatencyProtectionReason.catchUpBudgetExhausted,
          budgetCooldown,
          generation: generation,
        );
        return;
      }
      final desiredSpeed = _catchUpSpeedFor(cache, cacheSlope: cacheSlope);
      if (desiredSpeed <= _baselineSpeed + 0.001) {
        _state = MpvLiveLatencyChaseState.monitoring;
        _clearCatchUpBudget();
        await _restoreNormalSpeed(
          now,
          bypassDwell: true,
          generation: generation,
        );
        return;
      }
      if (_canChangeSpeed(now, desiredSpeed)) {
        final applied = await _applySpeed(
          desiredSpeed,
          sampledAt: now,
          generation: generation,
        );
        if (!applied || !_isCurrentGeneration(generation) || !_enabled) {
          return;
        }
      }
      _tightenCatchUpDeadline(now, cache, _currentSpeed);
      if (_isCatchUpBudgetExhausted(now)) {
        await _enterProtection(
          now,
          MpvLiveLatencyProtectionReason.catchUpBudgetExhausted,
          budgetCooldown,
          generation: generation,
        );
      }
      return;
    }

    final stableSince = _stableObservationStartedAt;
    final stableLongEnough = stableSince != null &&
        now.difference(stableSince) >= stableObservationDuration;
    if (cache >= _policy.resumeThresholdSeconds && stableLongEnough) {
      final desiredSpeed = _catchUpSpeedFor(cache, cacheSlope: cacheSlope);
      if (desiredSpeed <= _baselineSpeed + 0.001 ||
          !_canChangeSpeed(now, desiredSpeed)) {
        _state = MpvLiveLatencyChaseState.monitoring;
        await _restoreNormalSpeed(
          now,
          bypassDwell: true,
          generation: generation,
        );
        return;
      }
      final applied = await _applySpeed(
        desiredSpeed,
        sampledAt: now,
        generation: generation,
      );
      if (!applied || !_isCurrentGeneration(generation) || !_enabled) {
        return;
      }
      _state = MpvLiveLatencyChaseState.catchingUp;
      _catchUpStartedAt = now;
      _catchUpDeadline = null;
      _tightenCatchUpDeadline(now, cache, _currentSpeed);
      return;
    }

    _state = MpvLiveLatencyChaseState.monitoring;
    await _restoreNormalSpeed(
      now,
      bypassDwell: true,
      generation: generation,
    );
  }

  /// Immediately restores the saved baseline and enters a safety cooldown.
  Future<void> protect({
    DateTime? sampledAt,
    MpvLiveLatencyProtectionReason reason =
        MpvLiveLatencyProtectionReason.buffering,
    int? generation,
  }) {
    final observedGeneration = generation ?? _requestedGeneration;
    return _enqueue(() {
      if (observedGeneration != _requestedGeneration ||
          observedGeneration != _activeGeneration ||
          !_enabled) {
        return Future<void>.value();
      }
      return _enterProtection(
        sampledAt ?? _clock(),
        reason,
        _cooldownForReason(reason),
        generation: observedGeneration,
      );
    });
  }

  Duration _cooldownForReason(MpvLiveLatencyProtectionReason reason) {
    return switch (reason) {
      MpvLiveLatencyProtectionReason.buffering ||
      MpvLiveLatencyProtectionReason.audioUnderrun =>
        bufferingCooldown,
      MpvLiveLatencyProtectionReason.catchUpBudgetExhausted => budgetCooldown,
      _ => safetyCooldown,
    };
  }

  /// Clears accumulated state while keeping the configured stream active.
  Future<void> reset({DateTime? sampledAt}) {
    final requestedGeneration = _beginGenerationRequest();
    return _enqueue(() async {
      if (!_isCurrentGeneration(requestedGeneration)) {
        return;
      }
      _activeGeneration = requestedGeneration;
      _cooldownUntil = null;
      _validPlaybackStartedAt = null;
      _stableObservationStartedAt = null;
      _clearCatchUpBudget();
      _clearCacheTrend();
      _lastProtectionReason = null;
      _lastSpeedChangeAt = null;
      _state = _enabled
          ? MpvLiveLatencyChaseState.settling
          : MpvLiveLatencyChaseState.disabled;
      await _restoreBaselineSpeed(
        sampledAt ?? _clock(),
        bypassDwell: true,
        trackDwell: false,
        generation: requestedGeneration,
      );
    });
  }

  /// Stops the loop and restores the saved baseline before player disposal.
  Future<void> stop({DateTime? stoppedAt}) {
    final requestedGeneration = _beginGenerationRequest();
    return _enqueue(() async {
      if (!_isCurrentGeneration(requestedGeneration)) {
        return;
      }
      _activeGeneration = requestedGeneration;
      _enabled = false;
      _state = MpvLiveLatencyChaseState.disabled;
      _cooldownUntil = null;
      _validPlaybackStartedAt = null;
      _stableObservationStartedAt = null;
      _clearCatchUpBudget();
      _clearCacheTrend();
      _lastProtectionReason = null;
      _lastSpeedChangeAt = null;
      _policy = const MpvLiveLatencyChasePolicy.disabled();
      final restored = await _restoreBaselineSpeed(
        stoppedAt ?? _clock(),
        bypassDwell: true,
        trackDwell: false,
        generation: requestedGeneration,
      );
      if (_isCurrentGeneration(requestedGeneration) &&
          restored &&
          !_baselineRestorePending) {
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

  int _beginGenerationRequest() {
    final generation = ++_requestedGeneration;
    // An in-flight writer may still complete after this request. Force the
    // new generation to restore the captured baseline before it does anything
    // else, without allowing the stale writer to commit service state.
    if (_hasBaselineSpeed) {
      _baselineRestorePending = true;
    }
    return generation;
  }

  bool _isCurrentGeneration(int generation) {
    return generation == _requestedGeneration;
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
    if (cacheSlope != null && cacheSlope < -0.02) {
      delta = math.max(minimumCatchUpDelta, delta - 0.01);
    }
    // Policy speed bands are absolute playback speeds. A safe custom baseline
    // is never multiplied, which would otherwise exceed the configured cap.
    return math.max(_baselineSpeed, normalSpeed + delta);
  }

  bool _canChangeSpeed(DateTime now, double desiredSpeed) {
    if ((desiredSpeed - _currentSpeed).abs() < 0.001) {
      return false;
    }
    if (desiredSpeed < _currentSpeed) {
      return true;
    }
    final changedAt = _lastSpeedChangeAt;
    return changedAt == null || now.difference(changedAt) >= minimumDwell;
  }

  Future<void> _enterProtection(
    DateTime now,
    MpvLiveLatencyProtectionReason reason,
    Duration duration, {
    required int generation,
  }) async {
    if (!_enabled || !_isCurrentGeneration(generation)) {
      return;
    }
    _state = MpvLiveLatencyChaseState.protecting;
    _lastProtectionReason = reason;
    final proposedUntil = now.add(duration);
    final currentUntil = _cooldownUntil;
    if (currentUntil == null || proposedUntil.isAfter(currentUntil)) {
      _cooldownUntil = proposedUntil;
    }
    _validPlaybackStartedAt = null;
    _stableObservationStartedAt = null;
    _clearCatchUpBudget();
    _clearCacheTrend();
    final restored = await _restoreNormalSpeed(
      now,
      bypassDwell: true,
      generation: generation,
    );
    if (_enabled && restored && _isCurrentGeneration(generation)) {
      _state = MpvLiveLatencyChaseState.cooldown;
    }
  }

  double? _recordCacheSample(double cacheSeconds, DateTime sampledAt) {
    if (_cacheSamples.isNotEmpty &&
        !sampledAt.isAfter(_cacheSamples.last.sampledAt)) {
      return _robustCacheSlope();
    }
    _cacheSamples.add(_CacheSample(cacheSeconds, sampledAt));
    if (_cacheSamples.length > 5) {
      _cacheSamples.removeAt(0);
    }
    return _robustCacheSlope();
  }

  double? _robustCacheSlope() {
    if (_cacheSamples.length < 3) {
      return null;
    }
    final slopes = <double>[];
    for (var index = 1; index < _cacheSamples.length; index += 1) {
      final previous = _cacheSamples[index - 1];
      final current = _cacheSamples[index];
      final elapsedMicros =
          current.sampledAt.difference(previous.sampledAt).inMicroseconds;
      if (elapsedMicros > 0) {
        slopes.add(
          (current.cacheSeconds - previous.cacheSeconds) /
              (elapsedMicros / Duration.microsecondsPerSecond),
        );
      }
    }
    if (slopes.isEmpty) {
      return null;
    }
    slopes.sort();
    final middle = slopes.length ~/ 2;
    if (slopes.length.isOdd) {
      return slopes[middle];
    }
    return (slopes[middle - 1] + slopes[middle]) / 2;
  }

  void _tightenCatchUpDeadline(
    DateTime now,
    double cacheSeconds,
    double desiredSpeed,
  ) {
    final speedDelta = desiredSpeed - _baselineSpeed;
    final safeExcess = cacheSeconds - _policy.stopThresholdSeconds;
    if (speedDelta <= 0 || safeExcess <= 0) {
      _catchUpDeadline = now;
      return;
    }
    final allowedSeconds = safeExcess / speedDelta * catchUpBudgetSafetyFactor;
    final dynamicDeadline = now.add(
      Duration(
        microseconds: (allowedSeconds * Duration.microsecondsPerSecond).floor(),
      ),
    );
    final startedAt = _catchUpStartedAt ?? now;
    final hardDeadline = startedAt.add(_policy.catchUpHardLimit);
    final candidate =
        dynamicDeadline.isBefore(hardDeadline) ? dynamicDeadline : hardDeadline;
    final existing = _catchUpDeadline;
    if (existing == null || candidate.isBefore(existing)) {
      _catchUpDeadline = candidate;
    }
  }

  bool _isCatchUpBudgetExhausted(DateTime now) {
    final deadline = _catchUpDeadline;
    return deadline != null && !now.isBefore(deadline);
  }

  void _clearCatchUpBudget() {
    _catchUpStartedAt = null;
    _catchUpDeadline = null;
  }

  void _clearCacheTrend({bool keepLatest = false}) {
    if (keepLatest && _latestCacheSeconds != null) {
      final latest = _cacheSamples.isEmpty ? null : _cacheSamples.last;
      _cacheSamples.clear();
      if (latest != null) {
        _cacheSamples.add(latest);
      }
      return;
    }
    _cacheSamples.clear();
    _latestCacheSeconds = null;
  }

  Future<bool> _restoreNormalSpeed(
    DateTime now, {
    bool bypassDwell = false,
    required int generation,
  }) {
    return _restoreBaselineSpeed(
      now,
      bypassDwell: bypassDwell,
      generation: generation,
    );
  }

  Future<bool> _restoreBaselineSpeed(
    DateTime now, {
    required bool bypassDwell,
    bool trackDwell = true,
    required int generation,
  }) async {
    if (!_isCurrentGeneration(generation)) {
      return false;
    }
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
      generation: generation,
    );
  }

  Future<double?> _captureBaselineSpeed(
    double? requestedSpeed, {
    required int generation,
  }) async {
    if (!_isCurrentGeneration(generation)) {
      return null;
    }
    double? speed = requestedSpeed;
    if (speed == null) {
      if (_readSpeed == null) {
        return null;
      }
      try {
        speed = await _readSpeed!.call();
      } catch (_) {
        return null;
      }
    }
    if (!_isCurrentGeneration(generation)) {
      return null;
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
    required int generation,
  }) async {
    if (!_isCurrentGeneration(generation)) {
      return false;
    }
    if (!force && (speed - _currentSpeed).abs() < 0.001) {
      return true;
    }
    try {
      if (!_isCurrentGeneration(generation)) {
        return false;
      }
      await _writeSpeed(speed);
      if (!_isCurrentGeneration(generation)) {
        return false;
      }
      _currentSpeed = speed;
      _baselineRestorePending = (speed - _baselineSpeed).abs() >= 0.001;
      if (trackDwell) {
        _lastSpeedChangeAt = sampledAt;
      }
      return true;
    } catch (error) {
      if (!_isCurrentGeneration(generation)) {
        return false;
      }
      _baselineRestorePending = true;
      _disable(error);
      if ((speed - _baselineSpeed).abs() >= 0.001) {
        try {
          if (!_isCurrentGeneration(generation)) {
            return false;
          }
          await _writeSpeed(_baselineSpeed);
          if (!_isCurrentGeneration(generation)) {
            return false;
          }
          _currentSpeed = _baselineSpeed;
          _baselineRestorePending = false;
        } catch (recoveryError) {
          if (_isCurrentGeneration(generation)) {
            _reportWriteError(recoveryError);
          }
        }
      }
      return false;
    }
  }

  void _disable([Object? error]) {
    _state = MpvLiveLatencyChaseState.disabled;
    _enabled = false;
    _clearCatchUpBudget();
    if (error != null) {
      _reportWriteError(error);
    }
  }

  void _reportWriteError(Object error) {
    try {
      _onWriteError?.call(error);
    } catch (_) {
      // Error reporting must not prevent restoration of the baseline speed.
    }
  }
}

class _CacheSample {
  const _CacheSample(this.cacheSeconds, this.sampledAt);

  final double cacheSeconds;
  final DateTime sampledAt;
}
