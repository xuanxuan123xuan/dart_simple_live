class PlaybackStallTracker {
  PlaybackStallTracker({
    this.stallTimeout = const Duration(seconds: 15),
    this.bufferingStallTimeout = const Duration(seconds: 30),
    this.recoveryCooldown = const Duration(seconds: 5),
    this.stableResetDuration = const Duration(seconds: 30),
    this.maximumRecoveryAttempts = 3,
  });

  final Duration stallTimeout;
  final Duration bufferingStallTimeout;
  final Duration recoveryCooldown;
  final Duration stableResetDuration;
  final int maximumRecoveryAttempts;

  String? _source;
  int? _generation;
  Duration? _lastPosition;
  DateTime? _lastProgressAt;
  DateTime? _stableProgressSince;
  DateTime? _lastRecoveryAt;
  int _recoveryAttempts = 0;

  int get recoveryAttempts => _recoveryAttempts;

  bool observe({
    required DateTime now,
    required int generation,
    required String source,
    required Duration position,
    required bool playing,
    required bool buffering,
    required bool completed,
  }) {
    if (!playing || completed || source.isEmpty) {
      _lastPosition = null;
      _lastProgressAt = null;
      _stableProgressSince = null;
      return false;
    }
    if (_source != source) {
      _source = source;
      _generation = generation;
      _lastPosition = position;
      _lastProgressAt = now;
      _stableProgressSince = null;
      _lastRecoveryAt = null;
      _recoveryAttempts = 0;
      return false;
    }
    if (_generation != generation) {
      _generation = generation;
      _lastPosition = position;
      _lastProgressAt = now;
      _stableProgressSince = null;
      return false;
    }
    if (_lastPosition == null || position != _lastPosition) {
      _lastPosition = position;
      _lastProgressAt = now;
      if (_recoveryAttempts > 0) {
        _stableProgressSince ??= now;
        if (now.difference(_stableProgressSince!) >= stableResetDuration) {
          _recoveryAttempts = 0;
          _lastRecoveryAt = null;
          _stableProgressSince = null;
        }
      }
      return false;
    }

    _stableProgressSince = null;
    final lastProgressAt = _lastProgressAt ?? now;
    final timeout = buffering ? bufferingStallTimeout : stallTimeout;
    if (now.difference(lastProgressAt) < timeout ||
        _recoveryAttempts >= maximumRecoveryAttempts ||
        (_lastRecoveryAt != null &&
            now.difference(_lastRecoveryAt!) < recoveryCooldown)) {
      return false;
    }
    _recoveryAttempts += 1;
    _lastRecoveryAt = now;
    _lastProgressAt = now;
    return true;
  }

  void reset() {
    _source = null;
    _generation = null;
    _lastPosition = null;
    _lastProgressAt = null;
    _stableProgressSince = null;
    _lastRecoveryAt = null;
    _recoveryAttempts = 0;
  }
}
