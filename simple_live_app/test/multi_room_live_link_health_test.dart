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

void main() {
  test('rejects a late sample after a multi-room source changes', () {
    final coordinator = _coordinator();
    final old = coordinator.beginSource(
      target: 'douyin/old',
      source: 'https://cdn.example/old.flv',
      openedAt: _base,
    );
    final current = coordinator.beginSource(
      target: 'douyin/new',
      source: 'https://cdn.example/new.flv',
      openedAt: _base,
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

  test('records only reliable automatic reopen as CDN reconnect', () {
    final coordinator = _coordinator();
    final generation = coordinator.beginSource(
      target: 'kuaishou/1',
      source: 'https://cdn.example/live.flv',
      openedAt: _base,
      automaticReconnectReason: LiveReconnectReason.mediaError,
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
  });

  test('user line change is excluded from automatic reconnect count', () {
    final coordinator = _coordinator();
    final generation = coordinator.beginSource(
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
    coordinator.beginSource(
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
    coordinator.beginSource(
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

    final pageController = File(
      'lib/modules/multi_room/multi_room_controller.dart',
    ).readAsStringSync();
    expect(pageController, contains('const Duration(seconds: 5)'));
  });
}
