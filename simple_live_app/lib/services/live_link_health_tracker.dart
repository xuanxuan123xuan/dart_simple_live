import 'live_link_health_evaluator.dart';
import 'live_link_health_models.dart';

typedef LiveLinkHealthClock = DateTime Function();

class LiveLinkHealthTracker {
  LiveLinkHealthTracker({
    LiveLinkHealthClock? clock,
    this.warmupDuration = const Duration(seconds: 8),
    this.capabilities = const LiveLinkHealthCapabilities(),
    LiveLinkHealthEvaluator evaluator = const LiveLinkHealthEvaluator(),
  })  : _clock = clock ?? DateTime.now,
        _evaluator = evaluator;

  static const sampleInterval = Duration(seconds: 1);
  static const _audioUnderrunDeduplication = Duration(milliseconds: 500);

  final LiveLinkHealthClock _clock;
  final Duration warmupDuration;
  final LiveLinkHealthCapabilities capabilities;
  final LiveLinkHealthEvaluator _evaluator;
  final LiveLinkHealthLevelHysteresis _levelHysteresis =
      LiveLinkHealthLevelHysteresis();

  final List<LiveLinkHealthSample> _samples = [];
  final List<LiveLinkHealthEvent> _events = [];
  int? _generation;
  DateTime? _excludedUntil;
  DateTime? _lastAudioUnderrunAt;
  bool _pausedByUser = false;
  bool _backgrounded = false;
  bool _bufferingEventActive = false;

  int? get generation => _generation;
  int get sampleCount => _samples.length;
  int get eventCount => _events.length;

  void startGeneration(int generation, {DateTime? at}) {
    _generation = generation;
    _samples.clear();
    _events.clear();
    _pausedByUser = false;
    _backgrounded = false;
    _bufferingEventActive = false;
    _lastAudioUnderrunAt = null;
    _excludedUntil = (at ?? _clock()).add(warmupDuration);
    _levelHysteresis.reset();
  }

  void addSample(LiveLinkHealthSample sample) {
    _ensureGeneration(sample.generation, sample.sampledAt);
    if (!_isEligible(sample.sampledAt) || !sample.streamActive) {
      return;
    }
    _samples.add(sample);
    _trim(sample.sampledAt);
  }

  void addEvent(LiveLinkHealthEvent event) {
    _ensureGeneration(event.generation, event.occurredAt);
    switch (event.type) {
      case LiveLinkEventType.playbackPausedByUser:
        _pausedByUser = true;
        _samples.clear();
        return;
      case LiveLinkEventType.playbackResumedByUser:
        _pausedByUser = false;
        _excludeForWarmup(event.occurredAt);
        return;
      case LiveLinkEventType.appBackgrounded:
        _backgrounded = true;
        _samples.clear();
        return;
      case LiveLinkEventType.appForegrounded:
        _backgrounded = false;
        _excludeForWarmup(event.occurredAt);
        return;
      case LiveLinkEventType.streamOpened:
        _samples.clear();
        _excludeForWarmup(event.occurredAt);
        _bufferingEventActive = false;
        return;
      case LiveLinkEventType.lineChangedByUser:
      case LiveLinkEventType.qualityChangedByUser:
        _samples.clear();
        _events.clear();
        _lastAudioUnderrunAt = null;
        _levelHysteresis.reset();
        _excludeForWarmup(event.occurredAt);
        _bufferingEventActive = false;
        return;
      case LiveLinkEventType.bufferingStarted:
        if (_bufferingEventActive) return;
        _bufferingEventActive = true;
        if (_isEligible(event.occurredAt)) {
          _events.add(event);
        }
        break;
      case LiveLinkEventType.bufferingEnded:
        if (!_bufferingEventActive) return;
        _bufferingEventActive = false;
        if (_isEligible(event.occurredAt)) {
          _events.add(event);
        }
        break;
      case LiveLinkEventType.audioUnderrun:
        if (!_isEligible(event.occurredAt)) return;
        final previous = _lastAudioUnderrunAt;
        if (previous != null &&
            event.occurredAt.difference(previous) <
                _audioUnderrunDeduplication) {
          return;
        }
        _lastAudioUnderrunAt = event.occurredAt;
        _events.add(event);
        break;
      case LiveLinkEventType.cdnReconnect:
        if (_isEligible(event.occurredAt)) {
          _events.add(event);
        }
        break;
    }
    _trim(event.occurredAt);
  }

  LiveLinkHealthSnapshot snapshot({DateTime? at}) {
    final now = at ?? _clock();
    _trim(now);
    final raw = _evaluator.evaluate(
      LiveLinkHealthEvaluationInput(
        now: now,
        samples: List.unmodifiable(_samples),
        events: List.unmodifiable(_events),
        capabilities: capabilities,
      ),
    );
    final displayedLevel = _levelHysteresis.apply(raw.level, now);
    if (displayedLevel == raw.level) {
      return raw;
    }
    return LiveLinkHealthSnapshot(
      score: raw.score == null
          ? null
          : LiveLinkHealthEvaluator.scoreForDisplayedLevel(
              raw.score!,
              displayedLevel,
            ),
      level: displayedLevel,
      causes: raw.causes,
      window: raw.window,
      hasEnoughData: raw.hasEnoughData,
      metrics: raw.metrics,
      suggestions: raw.suggestions,
    );
  }

  void _ensureGeneration(int generation, DateTime at) {
    if (_generation != generation) {
      startGeneration(generation, at: at);
    }
  }

  bool _isEligible(DateTime at) {
    final excludedUntil = _excludedUntil;
    return !_pausedByUser &&
        !_backgrounded &&
        (excludedUntil == null || !at.isBefore(excludedUntil));
  }

  void _excludeForWarmup(DateTime at) {
    final until = at.add(warmupDuration);
    if (_excludedUntil == null || until.isAfter(_excludedUntil!)) {
      _excludedUntil = until;
    }
  }

  void _trim(DateTime now) {
    final cutoff = now.subtract(LiveLinkHealthEvaluator.longWindow);
    _samples.removeWhere((sample) => sample.sampledAt.isBefore(cutoff));
    _events.removeWhere((event) => event.occurredAt.isBefore(cutoff));
  }
}
