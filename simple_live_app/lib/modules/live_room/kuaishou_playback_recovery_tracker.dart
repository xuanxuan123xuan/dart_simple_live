/// Tracks buffering incidents that justify a Kuaishou playback URL recovery.
///
/// The controller owns the timer used for continuous buffering. This class
/// keeps the timing policy pure and makes a recovery single-flight.
class KuaishouPlaybackRecoveryTracker {
  KuaishouPlaybackRecoveryTracker({
    this.warmupDuration = const Duration(seconds: 8),
    this.continuousBufferingThreshold = const Duration(seconds: 5),
    this.independentBufferingWindow = const Duration(seconds: 30),
    this.cooldown = const Duration(seconds: 30),
  });

  final Duration warmupDuration;
  final Duration continuousBufferingThreshold;
  final Duration independentBufferingWindow;
  final Duration cooldown;

  bool _buffering = false;
  bool _recoveryInFlight = false;
  DateTime? _warmupUntil;
  DateTime? _cooldownUntil;
  DateTime? _firstIndependentBufferingAt;
  DateTime? _bufferingStartedAt;

  bool get isBuffering => _buffering;
  bool get recoveryInFlight => _recoveryInFlight;

  /// Delay until a continuous buffer is eligible to recover. The controller
  /// uses this for its one-shot timer so warmup or cooldown cannot consume the
  /// only callback while buffering remains true.
  Duration continuousRecoveryDelay(DateTime now) {
    final startedAt = _bufferingStartedAt ?? now;
    var eligibleAt = startedAt.add(continuousBufferingThreshold);
    final warmupUntil = _warmupUntil;
    if (warmupUntil != null && warmupUntil.isAfter(eligibleAt)) {
      eligibleAt = warmupUntil;
    }
    final cooldownUntil = _cooldownUntil;
    if (cooldownUntil != null && cooldownUntil.isAfter(eligibleAt)) {
      eligibleAt = cooldownUntil;
    }
    return eligibleAt.isAfter(now) ? eligibleAt.difference(now) : Duration.zero;
  }

  void beginWarmup(DateTime now) {
    _buffering = false;
    _firstIndependentBufferingAt = null;
    _bufferingStartedAt = null;
    _warmupUntil = now.add(warmupDuration);
  }

  void reset() {
    _buffering = false;
    _recoveryInFlight = false;
    _warmupUntil = null;
    _cooldownUntil = null;
    _firstIndependentBufferingAt = null;
    _bufferingStartedAt = null;
  }

  /// Records a buffering transition. A true result means the second
  /// independent buffering start within the configured window should recover.
  bool updateBuffering({required bool buffering, required DateTime now}) {
    if (!buffering) {
      _buffering = false;
      _bufferingStartedAt = null;
      return false;
    }
    if (_buffering) {
      return false;
    }
    _buffering = true;
    _bufferingStartedAt = now;
    final warmupUntil = _warmupUntil;
    if (warmupUntil != null && now.isBefore(warmupUntil)) {
      return false;
    }
    if (!_canRecover(now)) {
      return false;
    }

    final first = _firstIndependentBufferingAt;
    if (first != null && now.difference(first) <= independentBufferingWindow) {
      return _startRecovery(now);
    }
    _firstIndependentBufferingAt = now;
    return false;
  }

  /// Called by the controller's cancellable continuous-buffering timer.
  bool triggerContinuousBufferingRecovery(DateTime now) {
    final startedAt = _bufferingStartedAt;
    if (!_buffering ||
        startedAt == null ||
        now.difference(startedAt) < continuousBufferingThreshold ||
        !_canRecover(now)) {
      return false;
    }
    return _startRecovery(now);
  }

  void finishRecovery() {
    _recoveryInFlight = false;
  }

  /// Re-arm the buffering edge after the controller has reopened the player.
  /// A reopen does not guarantee that media_kit emits a false edge first.
  void markPlaybackReopened() {
    _buffering = false;
    _bufferingStartedAt = null;
  }

  bool _canRecover(DateTime now) {
    final warmupUntil = _warmupUntil;
    if (warmupUntil != null && now.isBefore(warmupUntil)) {
      return false;
    }
    final cooldownUntil = _cooldownUntil;
    return !_recoveryInFlight &&
        (cooldownUntil == null || !now.isBefore(cooldownUntil));
  }

  bool _startRecovery(DateTime now) {
    _recoveryInFlight = true;
    _cooldownUntil = now.add(cooldown);
    _firstIndependentBufferingAt = null;
    return true;
  }
}
