import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/live_link_health_collector.dart';
import 'package:simple_live_app/services/live_link_health_models.dart';
import 'package:simple_live_app/services/live_link_health_tracker.dart';

final _base = DateTime(2026, 8, 9, 12);

LiveLinkHealthSample _sample({
  required int generation,
  required int second,
  double? cache = 2,
  bool playing = true,
  bool buffering = false,
}) {
  return LiveLinkHealthSample(
    generation: generation,
    sampledAt: _base.add(Duration(seconds: second)),
    position: Duration(seconds: second),
    playing: playing,
    buffering: buffering,
    playbackSpeed: 1,
    demuxerCacheSeconds: cache,
  );
}

void main() {
  test('rejects stale asynchronous samples after generation changes', () {
    final collector = LiveLinkHealthShadowCollector(
      tracker: LiveLinkHealthTracker(warmupDuration: Duration.zero),
    );
    collector.startGeneration(generation: 1, target: 'kuaishou/old', at: _base);
    expect(collector.addSample(_sample(generation: 1, second: 0)), isNotNull);

    collector.startGeneration(generation: 2, target: 'kuaishou/new', at: _base);
    expect(collector.addSample(_sample(generation: 1, second: 1)), isNull);
    expect(collector.sampleCount, 0);

    final current = collector.addSample(_sample(generation: 2, second: 1));
    expect(current, contains('target=kuaishou/new'));
    expect(current, contains('generation=2'));
    expect(collector.sampleCount, 1);
  });

  test('emits at most one shadow summary every five seconds', () {
    final collector = LiveLinkHealthShadowCollector(
      tracker: LiveLinkHealthTracker(warmupDuration: Duration.zero),
    );
    collector.startGeneration(generation: 7, target: 'douyin/room', at: _base);

    final logs = <String>[];
    for (var second = 0; second <= 10; second += 1) {
      final log = collector.addSample(
        _sample(generation: 7, second: second),
      );
      if (log != null) logs.add(log);
    }

    expect(logs, hasLength(3));
    expect(logs.first, contains('[live-health]'));
    expect(logs.last, contains('score='));
    expect(logs.last, contains('cache='));
    expect(logs.last, contains('slope='));
    expect(logs.last, contains('buffering=false'));
    expect(logs.last, contains('progress='));
  });

  test('background and foreground events exclude ineligible samples', () {
    final collector = LiveLinkHealthShadowCollector(
      tracker: LiveLinkHealthTracker(warmupDuration: Duration.zero),
    );
    collector.startGeneration(generation: 3, target: 'bilibili/1', at: _base);
    collector.addSample(_sample(generation: 3, second: 0));

    expect(
      collector.addEvent(
        LiveLinkHealthEvent(
          generation: 3,
          occurredAt: _base.add(const Duration(seconds: 1)),
          type: LiveLinkEventType.appBackgrounded,
        ),
      ),
      isTrue,
    );
    collector.addSample(_sample(generation: 3, second: 2));
    expect(collector.sampleCount, 0);

    collector.addEvent(
      LiveLinkHealthEvent(
        generation: 3,
        occurredAt: _base.add(const Duration(seconds: 3)),
        type: LiveLinkEventType.appForegrounded,
      ),
    );
    collector.addSample(_sample(generation: 3, second: 3));
    expect(collector.sampleCount, 1);
  });

  test('insufficient data is explicitly formatted as unknown', () {
    final collector = LiveLinkHealthShadowCollector();
    collector.startGeneration(generation: 4, target: 'huya/1', at: _base);

    final log = collector.addSample(
      _sample(generation: 4, second: 0, cache: null),
    );

    expect(log, contains('score=unknown'));
    expect(log, contains('level=unknown'));
    expect(log, contains('cause=insufficientData'));
    expect(log, contains('cache=unknown'));
    expect(log, contains('progress=unknown'));
  });

  test('one lightweight native cache read feeds health and chase', () {
    final playerController = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();
    final sampleStart = playerController.indexOf(
      'Future<void> _sampleLivePlaybackLightweight()',
    );
    final sampleEnd = playerController.indexOf(
      'void _recordLiveLinkHealthSample',
      sampleStart,
    );
    final sampleMethod = playerController.substring(sampleStart, sampleEnd);

    expect(
      'sampleMpvDemuxerCacheDuration(player)'.allMatches(sampleMethod).length,
      1,
    );
    expect(sampleMethod, contains('demuxerCacheSeconds: cacheDurationSeconds'));
    expect(
        sampleMethod, contains('cacheDurationSeconds: cacheDurationSeconds'));
  });

  test('live playback source uses Uri canonical representation', () {
    const source = 'https://example.com/live%20room?token=a%2Fb';

    expect(
      canonicalizeLivePlaybackSource(source),
      Uri.tryParse(source)!.toString(),
    );
    expect(canonicalizeLivePlaybackSource(''), isEmpty);

    final playerController = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();
    expect(
      playerController,
      contains(
        '_livePlaybackSource = canonicalSource;',
      ),
    );
    expect(
      playerController,
      contains(
        'final currentSource = canonicalizeLivePlaybackSource(',
      ),
    );
  });

  test('playlist reset rechecks the playback request before opening', () {
    final liveRoomController = File(
      'lib/modules/live_room/live_room_controller.dart',
    ).readAsStringSync();
    const resetCall = 'await resetLiveLatencyChase();';
    const requestCheck =
        'if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)) {';
    final resetIndex = liveRoomController.indexOf(resetCall);
    final requestCheckIndex = liveRoomController.indexOf(
      requestCheck,
      resetIndex + resetCall.length,
    );
    final firstOpenIndex = liveRoomController.indexOf(
      'if (Utils.isOhos)',
      resetIndex + resetCall.length,
    );

    expect(resetIndex, greaterThanOrEqualTo(0));
    expect(requestCheckIndex, greaterThan(resetIndex));
    expect(requestCheckIndex, lessThan(firstOpenIndex));
  });
}
