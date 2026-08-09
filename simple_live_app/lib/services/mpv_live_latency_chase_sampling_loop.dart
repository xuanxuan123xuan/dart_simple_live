import 'dart:async';

typedef MpvLiveLatencySample = Future<void> Function();
typedef MpvLiveLatencySampleInterval = Duration? Function();
typedef MpvLiveLatencyScheduledCancel = void Function();
typedef MpvLiveLatencySchedule = MpvLiveLatencyScheduledCancel Function(
  Duration delay,
  void Function() callback,
);

/// A non-overlapping, dynamically scheduled sampling loop.
///
/// A one-shot schedule is installed only after the previous asynchronous
/// sample completes. This makes a slow native property read skip cadence
/// slots instead of accumulating overlapping reads.
class MpvLiveLatencyChaseSamplingLoop {
  MpvLiveLatencyChaseSamplingLoop({
    required MpvLiveLatencySample sample,
    required MpvLiveLatencySampleInterval nextInterval,
    MpvLiveLatencySchedule schedule = _scheduleTimer,
    void Function(Object error)? onError,
  })  : _sample = sample,
        _nextInterval = nextInterval,
        _schedule = schedule,
        _onError = onError;

  final MpvLiveLatencySample _sample;
  final MpvLiveLatencySampleInterval _nextInterval;
  final MpvLiveLatencySchedule _schedule;
  final void Function(Object error)? _onError;

  MpvLiveLatencyScheduledCancel? _cancelScheduled;
  int _generation = 0;
  bool _active = false;
  bool _sampleInFlight = false;
  int? _pendingRestartGeneration;
  bool _pendingRestartImmediately = true;

  bool get isActive => _active;
  bool get isSampleInFlight => _sampleInFlight;

  /// Chooses the next wake-up without creating a second timer. A chase-only
  /// tick may happen before [healthDueAt], while the health deadline always
  /// remains an upper bound even when chasing is disabled.
  static Duration? nextDelay({
    required Duration? chaseInterval,
    required DateTime? healthDueAt,
    DateTime? now,
  }) {
    if (healthDueAt == null) return chaseInterval;
    final untilHealth = healthDueAt.difference(now ?? DateTime.now());
    final healthDelay = untilHealth.isNegative ? Duration.zero : untilHealth;
    if (chaseInterval == null || healthDelay < chaseInterval) {
      return healthDelay;
    }
    return chaseInterval;
  }

  void start({bool immediately = true}) {
    stop();
    _active = true;
    final generation = ++_generation;
    if (_sampleInFlight) {
      _pendingRestartGeneration = generation;
      _pendingRestartImmediately = immediately;
      return;
    }
    if (immediately) {
      unawaited(_runSample(generation));
    } else {
      _scheduleNext(generation);
    }
  }

  void stop() {
    _active = false;
    _generation += 1;
    _cancelScheduled?.call();
    _cancelScheduled = null;
    _pendingRestartGeneration = null;
  }

  Future<void> _runSample(int generation) async {
    if (!_active || generation != _generation || _sampleInFlight) {
      return;
    }
    _cancelScheduled = null;
    _sampleInFlight = true;
    try {
      await _sample();
    } catch (error) {
      try {
        _onError?.call(error);
      } catch (_) {
        // Diagnostics must not break scheduling cleanup.
      }
    } finally {
      _sampleInFlight = false;
      final pendingGeneration = _pendingRestartGeneration;
      if (_active && pendingGeneration == _generation) {
        final immediately = _pendingRestartImmediately;
        _pendingRestartGeneration = null;
        if (immediately) {
          unawaited(_runSample(pendingGeneration!));
        } else {
          _scheduleNext(pendingGeneration!);
        }
      } else if (_active && generation == _generation) {
        _scheduleNext(generation);
      }
    }
  }

  void _scheduleNext(int generation) {
    if (!_active || generation != _generation) {
      return;
    }
    final interval = _nextInterval();
    if (interval == null) {
      stop();
      return;
    }
    _cancelScheduled?.call();
    _cancelScheduled = _schedule(
      interval,
      () => unawaited(_runSample(generation)),
    );
  }

  static MpvLiveLatencyScheduledCancel _scheduleTimer(
    Duration delay,
    void Function() callback,
  ) {
    final timer = Timer(delay, callback);
    return timer.cancel;
  }
}
