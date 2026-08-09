import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/live_link_health_evaluator.dart';
import 'package:simple_live_app/services/live_link_health_models.dart';
import 'package:simple_live_app/services/live_link_health_tracker.dart';

final _base = DateTime.utc(2026, 8, 9, 12);

LiveLinkHealthSample _sample({
  required int second,
  int generation = 1,
  int? positionMs,
  double speed = 1,
  double? cache,
  double? throughputRatio,
  bool playing = true,
  bool buffering = false,
  bool streamActive = true,
  bool? endpointReachable,
  int? frameDrops,
}) {
  return LiveLinkHealthSample(
    generation: generation,
    sampledAt: _base.add(Duration(seconds: second)),
    position: Duration(milliseconds: positionMs ?? second * 1000),
    playing: playing,
    buffering: buffering,
    playbackSpeed: speed,
    streamActive: streamActive,
    demuxerCacheSeconds: cache,
    receiveBytesPerSecond:
        throughputRatio == null ? null : throughputRatio * 1000,
    estimatedMediaBitsPerSecond:
        throughputRatio == null ? null : 8000,
    playbackEndpointReachable: endpointReachable,
    frameDropCount: frameDrops,
  );
}

LiveLinkHealthEvent _event(
  LiveLinkEventType type, {
  required int millisecond,
  int generation = 1,
  LiveReconnectReason? reconnectReason,
}) {
  return LiveLinkHealthEvent(
    generation: generation,
    occurredAt: _base.add(Duration(milliseconds: millisecond)),
    type: type,
    reconnectReason: reconnectReason,
  );
}

LiveLinkHealthSnapshot _snapshotWithScore(int score) {
  const penalties = LiveLinkHealthPenalties(
    intake: 0,
    buffer: 0,
    continuity: 0,
    recovery: 0,
  );
  const metrics = LiveLinkHealthMetrics(
    eligibleWindow: Duration(seconds: 60),
    availableDomainCount: 4,
    cacheSeconds: 3,
    cacheSlopeSecondsPerSecond: 0,
    throughputRatio: 1.5,
    noDataDuration: Duration.zero,
    audioUnderrunCount: 0,
    bufferingCount: 0,
    bufferingDuration: Duration.zero,
    bufferingRatio: 0,
    longestBuffering: Duration.zero,
    automaticReconnectCount: 0,
    automaticReconnectReasons: <LiveReconnectReason>[],
    normalizedProgressRatio: 1,
    longestProgressStall: Duration.zero,
    playbackEndpointReachable: true,
    penalties: penalties,
  );
  return LiveLinkHealthSnapshot(
    score: score,
    level: LiveLinkHealthEvaluator.levelFor(score),
    causes: const [LiveLinkHealthCause.healthy],
    window: const Duration(seconds: 60),
    hasEnoughData: true,
    metrics: metrics,
    suggestions: const [],
  );
}

class _FakeEvaluator extends LiveLinkHealthEvaluator {
  _FakeEvaluator(this.current);

  LiveLinkHealthSnapshot current;

  @override
  LiveLinkHealthSnapshot evaluate(LiveLinkHealthEvaluationInput input) =>
      current;
}

void main() {
  const evaluator = LiveLinkHealthEvaluator();

  test('10 second cache slope uses linear regression', () {
    final samples = [
      for (var second = 0; second <= 10; second += 1)
        _sample(second: second, cache: 5 - second * 0.1),
    ];

    final slope = LiveLinkHealthEvaluator.cacheRegressionSlope(samples);

    expect(slope, closeTo(-0.1, 0.000001));
  });

  test('progress is normalized by catch-up playback speed', () {
    final samples = [
      for (var second = 0; second <= 10; second += 1)
        _sample(
          second: second,
          positionMs: second * 1080,
          speed: 1.08,
          cache: 3,
        ),
    ];

    final snapshot = evaluator.evaluate(
      LiveLinkHealthEvaluationInput(
        now: _base.add(const Duration(seconds: 10)),
        samples: samples,
        events: const [],
      ),
    );

    expect(snapshot.metrics.normalizedProgressRatio, closeTo(1, 0.000001));
  });

  test('unsupported metrics do not become zero or a fake perfect score', () {
    final samples = [
      for (var second = 0; second <= 10; second += 1)
        _sample(second: second),
    ];

    final snapshot = evaluator.evaluate(
      LiveLinkHealthEvaluationInput(
        now: _base.add(const Duration(seconds: 10)),
        samples: samples,
        events: const [],
      ),
    );

    expect(snapshot.hasEnoughData, isFalse);
    expect(snapshot.score, isNull);
    expect(snapshot.level, LiveLinkHealthLevel.unknown);
    expect(snapshot.metrics.throughputRatio, isNull);
    expect(snapshot.metrics.noDataDuration, isNull);
    expect(snapshot.metrics.audioUnderrunCount, isNull);
    expect(snapshot.metrics.automaticReconnectCount, isNull);
  });

  test('each fault domain takes its maximum penalty without double counting',
      () {
    final samples = [
      for (var second = 0; second < 20; second += 1)
        _sample(
          second: second,
          cache: 0.2 - second * 0.01,
          throughputRatio: second == 0 ? 0.1 : 0,
          buffering: true,
          positionMs: 0,
        ),
    ];
    final events = [
      _event(LiveLinkEventType.bufferingStarted, millisecond: 1000),
      _event(LiveLinkEventType.bufferingStarted, millisecond: 3000),
      _event(LiveLinkEventType.bufferingStarted, millisecond: 5000),
      _event(LiveLinkEventType.audioUnderrun, millisecond: 6000),
      _event(LiveLinkEventType.audioUnderrun, millisecond: 7000),
      _event(
        LiveLinkEventType.cdnReconnect,
        millisecond: 8000,
        reconnectReason: LiveReconnectReason.mediaError,
      ),
      _event(
        LiveLinkEventType.cdnReconnect,
        millisecond: 9000,
        reconnectReason: LiveReconnectReason.playbackUrlRefresh,
      ),
    ];

    final snapshot = evaluator.evaluate(
      LiveLinkHealthEvaluationInput(
        now: _base.add(const Duration(seconds: 19)),
        samples: samples,
        events: events,
        capabilities: const LiveLinkHealthCapabilities(
          audioUnderrunEvents: true,
          automaticReconnectEvents: true,
        ),
      ),
    );

    expect(snapshot.metrics.penalties.intake, 35);
    expect(snapshot.metrics.penalties.buffer, 25);
    expect(snapshot.metrics.penalties.continuity, 30);
    expect(snapshot.metrics.penalties.recovery, 10);
    expect(snapshot.metrics.penalties.total, 100);
    expect(snapshot.score, 0);
  });

  test('level boundaries match the documented score bands', () {
    expect(LiveLinkHealthEvaluator.levelFor(90), LiveLinkHealthLevel.excellent);
    expect(LiveLinkHealthEvaluator.levelFor(89), LiveLinkHealthLevel.good);
    expect(LiveLinkHealthEvaluator.levelFor(75), LiveLinkHealthLevel.good);
    expect(LiveLinkHealthEvaluator.levelFor(74), LiveLinkHealthLevel.fair);
    expect(LiveLinkHealthEvaluator.levelFor(55), LiveLinkHealthLevel.fair);
    expect(LiveLinkHealthEvaluator.levelFor(54), LiveLinkHealthLevel.poor);
    expect(LiveLinkHealthEvaluator.levelFor(30), LiveLinkHealthLevel.poor);
    expect(LiveLinkHealthEvaluator.levelFor(29), LiveLinkHealthLevel.critical);
  });

  test('healthier level requires ten stable seconds while degradation is fast',
      () {
    final hysteresis = LiveLinkHealthLevelHysteresis();
    expect(
      hysteresis.apply(LiveLinkHealthLevel.poor, _base),
      LiveLinkHealthLevel.poor,
    );
    expect(
      hysteresis.apply(
        LiveLinkHealthLevel.excellent,
        _base.add(const Duration(seconds: 1)),
      ),
      LiveLinkHealthLevel.poor,
    );
    expect(
      hysteresis.apply(
        LiveLinkHealthLevel.excellent,
        _base.add(const Duration(seconds: 10)),
      ),
      LiveLinkHealthLevel.poor,
    );
    expect(
      hysteresis.apply(
        LiveLinkHealthLevel.excellent,
        _base.add(const Duration(seconds: 11)),
      ),
      LiveLinkHealthLevel.excellent,
    );
    expect(
      hysteresis.apply(
        LiveLinkHealthLevel.critical,
        _base.add(const Duration(seconds: 12)),
      ),
      LiveLinkHealthLevel.critical,
    );
  });

  test('tracker keeps score inside the displayed level during recovery', () {
    final fakeEvaluator = _FakeEvaluator(_snapshotWithScore(45));
    final tracker = LiveLinkHealthTracker(
      warmupDuration: Duration.zero,
      evaluator: fakeEvaluator,
    );
    tracker.startGeneration(1, at: _base);
    expect(tracker.snapshot(at: _base).level, LiveLinkHealthLevel.poor);

    fakeEvaluator.current = _snapshotWithScore(100);
    final waiting = tracker.snapshot(
      at: _base.add(const Duration(seconds: 1)),
    );

    expect(waiting.level, LiveLinkHealthLevel.poor);
    expect(waiting.score, inInclusiveRange(30, 54));
    expect(
      LiveLinkHealthEvaluator.levelFor(waiting.score!),
      waiting.level,
    );
  });

  test('pause background and inactive stream samples are excluded', () {
    final tracker = LiveLinkHealthTracker(warmupDuration: Duration.zero);
    tracker.startGeneration(1, at: _base);
    tracker.addEvent(_event(
      LiveLinkEventType.playbackPausedByUser,
      millisecond: 0,
    ));
    tracker.addSample(_sample(second: 1, cache: 0.1));
    tracker.addEvent(_event(
      LiveLinkEventType.playbackResumedByUser,
      millisecond: 2000,
    ));
    tracker.addEvent(_event(
      LiveLinkEventType.appBackgrounded,
      millisecond: 3000,
    ));
    tracker.addSample(_sample(second: 4, cache: 0.1));
    tracker.addEvent(_event(
      LiveLinkEventType.appForegrounded,
      millisecond: 5000,
    ));
    tracker.addSample(_sample(second: 6, cache: 3, streamActive: false));
    tracker.addSample(_sample(second: 7, cache: 3));

    expect(tracker.sampleCount, 1);
  });

  test('startup and user line-change warmup samples are excluded', () {
    final tracker = LiveLinkHealthTracker();
    tracker.startGeneration(1, at: _base);
    tracker.addSample(_sample(second: 0, cache: 0.1, buffering: true));
    tracker.addSample(_sample(second: 7, cache: 0.1, buffering: true));
    tracker.addSample(_sample(second: 8, cache: 3));
    tracker.addEvent(_event(
      LiveLinkEventType.lineChangedByUser,
      millisecond: 9000,
    ));
    tracker.addSample(_sample(second: 10, cache: 0.1, buffering: true));
    tracker.addSample(_sample(second: 17, cache: 3));

    expect(tracker.sampleCount, 1);
  });

  test('duplicate buffering booleans count one buffering segment', () {
    final tracker = LiveLinkHealthTracker(warmupDuration: Duration.zero);
    tracker.startGeneration(1, at: _base);
    tracker.addEvent(_event(
      LiveLinkEventType.bufferingStarted,
      millisecond: 0,
    ));
    tracker.addEvent(_event(
      LiveLinkEventType.bufferingStarted,
      millisecond: 100,
    ));
    tracker.addEvent(_event(
      LiveLinkEventType.bufferingEnded,
      millisecond: 1000,
    ));
    tracker.addEvent(_event(
      LiveLinkEventType.bufferingEnded,
      millisecond: 1100,
    ));

    final snapshot = tracker.snapshot(at: _base.add(const Duration(seconds: 1)));
    expect(snapshot.metrics.bufferingCount, 1);
    expect(tracker.eventCount, 2);
  });

  test('audio underruns are deduplicated inside 500ms', () {
    final tracker = LiveLinkHealthTracker(
      warmupDuration: Duration.zero,
      capabilities: const LiveLinkHealthCapabilities(
        audioUnderrunEvents: true,
      ),
    );
    tracker.startGeneration(1, at: _base);
    tracker.addEvent(_event(
      LiveLinkEventType.audioUnderrun,
      millisecond: 0,
    ));
    tracker.addEvent(_event(
      LiveLinkEventType.audioUnderrun,
      millisecond: 200,
    ));
    tracker.addEvent(_event(
      LiveLinkEventType.audioUnderrun,
      millisecond: 500,
    ));

    final snapshot = tracker.snapshot(at: _base.add(const Duration(seconds: 1)));
    expect(snapshot.metrics.audioUnderrunCount, 2);
  });

  test('automatic reconnect survives stream-open warmup', () {
    final tracker = LiveLinkHealthTracker(
      capabilities: const LiveLinkHealthCapabilities(
        automaticReconnectEvents: true,
      ),
    );
    tracker.startGeneration(1, at: _base);
    tracker.addEvent(_event(
      LiveLinkEventType.cdnReconnect,
      millisecond: 1000,
      reconnectReason: LiveReconnectReason.mediaError,
    ));
    tracker.addEvent(_event(
      LiveLinkEventType.streamOpened,
      millisecond: 1100,
    ));
    tracker.addSample(_sample(second: 2, cache: 0.1));

    final snapshot = tracker.snapshot(at: _base.add(const Duration(seconds: 2)));
    expect(snapshot.metrics.automaticReconnectCount, 1);
    expect(tracker.eventCount, 1);
    expect(tracker.sampleCount, 0);
  });

  test('automatic reconnect is excluded while paused or backgrounded', () {
    final tracker = LiveLinkHealthTracker(
      capabilities: const LiveLinkHealthCapabilities(
        automaticReconnectEvents: true,
      ),
    );
    tracker.startGeneration(1, at: _base);
    tracker.addEvent(_event(
      LiveLinkEventType.playbackPausedByUser,
      millisecond: 100,
    ));
    tracker.addEvent(_event(
      LiveLinkEventType.cdnReconnect,
      millisecond: 200,
      reconnectReason: LiveReconnectReason.mediaError,
    ));
    tracker.addEvent(_event(
      LiveLinkEventType.playbackResumedByUser,
      millisecond: 300,
    ));
    tracker.addEvent(_event(
      LiveLinkEventType.appBackgrounded,
      millisecond: 400,
    ));
    tracker.addEvent(_event(
      LiveLinkEventType.cdnReconnect,
      millisecond: 500,
      reconnectReason: LiveReconnectReason.playbackUrlRefresh,
    ));

    expect(tracker.eventCount, 0);
    expect(
      tracker.snapshot(at: _base.add(const Duration(seconds: 1)))
          .metrics
          .automaticReconnectCount,
      0,
    );
  });

  test('generation change clears samples events and hysteresis state', () {
    final tracker = LiveLinkHealthTracker(warmupDuration: Duration.zero);
    tracker.startGeneration(1, at: _base);
    tracker.addSample(_sample(second: 0, cache: 3));
    tracker.addEvent(_event(
      LiveLinkEventType.bufferingStarted,
      millisecond: 0,
    ));

    tracker.addSample(_sample(second: 1, generation: 2, cache: 4));

    expect(tracker.generation, 2);
    expect(tracker.sampleCount, 1);
    expect(tracker.eventCount, 0);
  });

  test('catch-up speed and falling cache select catch-up as primary cause', () {
    final samples = [
      for (var second = 0; second <= 10; second += 1)
        _sample(
          second: second,
          speed: 1.08,
          positionMs: second * 1080,
          cache: 1.5 - second * 0.1,
          endpointReachable: true,
        ),
    ];
    final snapshot = evaluator.evaluate(
      LiveLinkHealthEvaluationInput(
        now: _base.add(const Duration(seconds: 10)),
        samples: samples,
        events: const [],
      ),
    );

    expect(snapshot.primaryCause, LiveLinkHealthCause.catchupCacheDrain);
  });

  test('low cache risk is not reported healthy before buffering starts', () {
    final samples = [
      for (var second = 0; second <= 10; second += 1)
        _sample(second: second, cache: 0.6),
    ];
    final snapshot = evaluator.evaluate(
      LiveLinkHealthEvaluationInput(
        now: _base.add(const Duration(seconds: 10)),
        samples: samples,
        events: const [],
      ),
    );

    expect(snapshot.metrics.penalties.buffer, greaterThan(0));
    expect(snapshot.primaryCause, LiveLinkHealthCause.playbackInstability);
    expect(snapshot.primaryCause, isNot(LiveLinkHealthCause.healthy));
  });

  test('low throughput with falling cache selects intake insufficiency', () {
    final samples = [
      for (var second = 0; second <= 10; second += 1)
        _sample(
          second: second,
          cache: 4 - second * 0.1,
          throughputRatio: 0.6,
        ),
    ];
    final snapshot = evaluator.evaluate(
      LiveLinkHealthEvaluationInput(
        now: _base.add(const Duration(seconds: 10)),
        samples: samples,
        events: const [],
      ),
    );

    expect(snapshot.primaryCause, LiveLinkHealthCause.intakeInsufficient);
  });

  test('good intake rising cache and stalled position select decoder stall', () {
    final samples = [
      for (var second = 0; second <= 10; second += 1)
        _sample(
          second: second,
          positionMs: 0,
          cache: 2 + second * 0.1,
          throughputRatio: 1.5,
        ),
    ];
    final snapshot = evaluator.evaluate(
      LiveLinkHealthEvaluationInput(
        now: _base.add(const Duration(seconds: 10)),
        samples: samples,
        events: const [],
      ),
    );

    expect(snapshot.primaryCause, LiveLinkHealthCause.decoderOrRenderStall);
  });
}
