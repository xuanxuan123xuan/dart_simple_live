import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_live_link_health.dart';
import 'package:simple_live_app/services/live_link_health_collector.dart';
import 'package:simple_live_app/services/live_link_health_models.dart';
import 'package:simple_live_app/services/live_link_health_tracker.dart';

final _base = DateTime(2026, 8, 9, 15);

MultiRoomLiveLinkHealthCoordinator _coordinator() {
  return MultiRoomLiveLinkHealthCoordinator(
    collector: LiveLinkHealthShadowCollector(
      tracker: LiveLinkHealthTracker(
        warmupDuration: Duration.zero,
        capabilities: const LiveLinkHealthCapabilities(
          audioUnderrunEvents: true,
          automaticReconnectEvents: true,
        ),
      ),
    ),
  );
}

LiveLinkHealthSample _sample(
  MultiRoomLiveLinkHealthGeneration generation, {
  int second = 1,
}) {
  return LiveLinkHealthSample(
    generation: generation.generation,
    sampledAt: _base.add(Duration(seconds: second)),
    position: Duration(seconds: second),
    playing: true,
    buffering: false,
    playbackSpeed: 1,
    demuxerCacheSeconds: 2,
    receiveBytesPerSecond: 500000,
    estimatedMediaBitsPerSecond: 2000000,
  );
}

MultiRoomLiveLinkHealthGeneration _begin(
  MultiRoomLiveLinkHealthCoordinator coordinator, {
  required String target,
  required String source,
  DateTime? openedAt,
  LiveLinkEventType? userOperation,
}) {
  return coordinator.beginSource(
    target: target,
    openAttempt: coordinator.prepareSource(source: source),
    openedAt: openedAt,
    userOperation: userOperation,
  )!;
}

void main() {
  test('rejects a late sample after a multi-room source changes', () {
    final coordinator = _coordinator();
    final old = _begin(
      coordinator,
      target: 'douyin/old',
      source: 'https://cdn.example/old.flv',
      openedAt: _base,
    );
    final current = _begin(
      coordinator,
      target: 'douyin/new',
      source: 'https://cdn.example/new.flv',
      openedAt: _base,
    );

    expect(
      coordinator.recordEvent(
        LiveLinkEventType.cdnReconnect,
        reconnectReason: LiveReconnectReason.mediaError,
        reconnectHostChanged: true,
        reconnectRecoveryDuration: const Duration(seconds: 1),
        expectedGeneration: old,
      ),
      isFalse,
    );

    expect(
      coordinator.addSample(generation: old, sample: _sample(old)),
      isNull,
    );
    expect(
      coordinator.addSample(generation: current, sample: _sample(current)),
      contains('target=douyin/new'),
    );
  });

  test('records only a successful current-generation reopen as CDN reconnect',
      () {
    final coordinator = _coordinator();
    final generation = _begin(
      coordinator,
      target: 'kuaishou/1',
      source: 'https://cdn.example/live.flv',
      openedAt: _base,
    );
    expect(
      coordinator.recordEvent(
        LiveLinkEventType.cdnReconnect,
        at: _base.add(const Duration(milliseconds: 800)),
        reconnectReason: LiveReconnectReason.mediaError,
        reconnectHostChanged: true,
        reconnectRecoveryDuration: const Duration(milliseconds: 800),
        expectedGeneration: generation,
      ),
      isTrue,
    );
    coordinator.addSample(
      generation: generation,
      sample: _sample(generation),
    );

    final snapshot = coordinator.snapshot(
      at: _base.add(const Duration(seconds: 1)),
    );
    expect(snapshot?.metrics.automaticReconnectCount, 1);
    expect(
      snapshot?.metrics.automaticReconnectReasons,
      [LiveReconnectReason.mediaError],
    );
    expect(snapshot?.metrics.latestAutomaticReconnectHostChanged, isTrue);
    expect(
      snapshot?.metrics.latestAutomaticReconnectRecoveryDuration,
      const Duration(milliseconds: 800),
    );
  });

  test('failed or stale open attempts preserve the active health generation',
      () {
    final coordinator = _coordinator();
    final active = _begin(
      coordinator,
      target: 'douyin/active',
      source: 'https://edge-a.example/live.flv?token=old',
      openedAt: _base,
    );
    expect(active.source, 'https://edge-a.example');
    expect(active.source, isNot(contains('token')));
    coordinator.addSample(
      generation: active,
      sample: _sample(active),
    );

    final staleAttempt = coordinator.prepareSource(
      source: 'https://edge-b.example/live.flv?token=stale',
    );
    final currentAttempt = coordinator.prepareSource(
      source: 'https://edge-c.example/live.flv?token=current',
    );
    expect(
      coordinator.beginSource(
        target: 'douyin/stale',
        openAttempt: staleAttempt,
        openedAt: _base.add(const Duration(seconds: 2)),
      ),
      isNull,
    );
    expect(coordinator.current, same(active));
    coordinator.addSample(
      generation: active,
      sample: _sample(active, second: 2),
    );
    expect(
      coordinator
          .snapshot(at: _base.add(const Duration(seconds: 2)))
          ?.metrics
          .eligibleWindow,
      const Duration(seconds: 1),
    );

    expect(
      coordinator.beginSource(
        target: 'douyin/current',
        openAttempt: currentAttempt,
        openedAt: _base.add(const Duration(seconds: 3)),
      ),
      isNotNull,
    );
  });

  test('user line change is excluded from automatic reconnect count', () {
    final coordinator = _coordinator();
    final generation = _begin(
      coordinator,
      target: 'huya/1',
      source: 'https://cdn.example/line-2.flv',
      openedAt: _base,
      userOperation: LiveLinkEventType.lineChangedByUser,
    );
    coordinator.addSample(
      generation: generation,
      sample: _sample(generation),
    );

    expect(
      coordinator
          .snapshot(at: _base.add(const Duration(seconds: 1)))
          ?.metrics
          .automaticReconnectCount,
      0,
    );
  });

  test('buffering edges are de-duplicated and stop rejects later events', () {
    final coordinator = _coordinator();
    _begin(
      coordinator,
      target: 'bilibili/1',
      source: 'https://cdn.example/live.flv',
      openedAt: _base,
    );
    coordinator.recordBuffering(false, at: _base);
    coordinator.recordBuffering(true, at: _base);
    coordinator.recordBuffering(true, at: _base);
    coordinator.recordBuffering(
      false,
      at: _base.add(const Duration(seconds: 1)),
    );
    expect(coordinator.eventCount, 2); // Only the two buffering edges persist.

    coordinator.stop();
    expect(
      coordinator.recordEvent(LiveLinkEventType.audioUnderrun),
      isFalse,
    );
  });

  test('pause closes an active buffering edge before resume', () {
    final coordinator = _coordinator();
    _begin(
      coordinator,
      target: 'douyin/1',
      source: 'https://cdn.example/live.flv',
      openedAt: _base,
    );
    coordinator.recordBuffering(true, at: _base);
    coordinator.recordEvent(
      LiveLinkEventType.playbackPausedByUser,
      at: _base.add(const Duration(seconds: 1)),
    );
    coordinator.recordEvent(
      LiveLinkEventType.playbackResumedByUser,
      at: _base.add(const Duration(seconds: 2)),
    );
    coordinator.recordBuffering(
      true,
      at: _base.add(const Duration(seconds: 3)),
    );

    expect(coordinator.eventCount, 3);
  });

  test('multi-room health reuses the existing low-frequency sample round', () {
    final playerController = File(
      'lib/modules/multi_room/multi_room_player_controller.dart',
    ).readAsStringSync();
    final sampleStart = playerController.indexOf(
      'Future<MultiRoomPlaybackTelemetry> sampleTelemetry',
    );
    final sampleEnd = playerController.indexOf(
      'bool _isCurrentHealthGeneration',
      sampleStart,
    );
    final sampleMethod = playerController.substring(sampleStart, sampleEnd);

    expect(sampleMethod, contains('final values = await Future.wait'));
    expect(sampleMethod, contains('LiveLinkHealthSample('));
    expect(sampleMethod, contains('position: state.position'));
    expect(sampleMethod, contains('buffering: state.buffering'));
    expect(sampleMethod, contains('receiveBytesPerSecond:'));
    expect(sampleMethod, isNot(contains('sampleMpvLiveHealthThroughput(')));

    final openStart = playerController.indexOf('Future<void> _openCurrentUrl');
    final openEnd = playerController.indexOf(
      'Future<void> ensurePlaying',
      openStart,
    );
    final openMethod = playerController.substring(openStart, openEnd);
    final playerOpen = openMethod.indexOf('await player.open(');
    final beginSource = openMethod.indexOf('_liveLinkHealth.beginSource(');
    final reconnectEvent = openMethod.indexOf('LiveLinkEventType.cdnReconnect');
    expect(playerOpen, greaterThanOrEqualTo(0));
    expect(beginSource, greaterThan(playerOpen));
    expect(reconnectEvent, greaterThan(playerOpen));
    expect(openMethod, contains('expectedGeneration: healthGeneration'));

    final pageController = File(
      'lib/modules/multi_room/multi_room_controller.dart',
    ).readAsStringSync();
    expect(pageController, contains('const Duration(seconds: 5)'));
  });
}
