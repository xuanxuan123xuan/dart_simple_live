import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/live_link_health_collector.dart';
import 'package:simple_live_app/services/live_link_health_models.dart';
import 'package:simple_live_app/services/live_link_health_tracker.dart';

final _base = DateTime.utc(2026, 8, 9, 16);

void main() {
  test('structured reconnect reason reaches the current health snapshot', () {
    final collector = LiveLinkHealthShadowCollector(
      tracker: LiveLinkHealthTracker(
        warmupDuration: Duration.zero,
        capabilities: const LiveLinkHealthCapabilities(
          automaticReconnectEvents: true,
        ),
      ),
    );
    collector.startGeneration(generation: 4, target: 'huya/room', at: _base);

    expect(
      collector.addEvent(
        LiveLinkHealthEvent(
          generation: 4,
          occurredAt: _base,
          type: LiveLinkEventType.cdnReconnect,
          reconnectReason: LiveReconnectReason.mediaError,
        ),
      ),
      isTrue,
    );

    final metrics = collector.snapshot(at: _base)!.metrics;
    expect(metrics.automaticReconnectCount, 1);
    expect(
      metrics.automaticReconnectReasons,
      [LiveReconnectReason.mediaError],
    );
  });

  test('old generation reconnect cannot pollute the new room session', () {
    final collector = LiveLinkHealthShadowCollector(
      tracker: LiveLinkHealthTracker(
        warmupDuration: Duration.zero,
        capabilities: const LiveLinkHealthCapabilities(
          automaticReconnectEvents: true,
        ),
      ),
    );
    collector.startGeneration(generation: 1, target: 'old/room', at: _base);
    collector.startGeneration(generation: 2, target: 'new/room', at: _base);

    expect(
      collector.addEvent(
        LiveLinkHealthEvent(
          generation: 1,
          occurredAt: _base,
          type: LiveLinkEventType.cdnReconnect,
          reconnectReason: LiveReconnectReason.playbackUrlRefresh,
        ),
      ),
      isFalse,
    );
    expect(collector.eventCount, 0);
    expect(
      collector.snapshot(at: _base)!.metrics.automaticReconnectReasons,
      isEmpty,
    );
  });

  test('room recovery paths emit distinct structured reasons after reopen', () {
    final source = File(
      'lib/modules/live_room/live_room_controller.dart',
    ).readAsStringSync();

    expect(source, contains('LiveReconnectReason.sustainedBuffering'));
    expect(source, contains('LiveReconnectReason.mediaEnd'));
    expect(source, contains('LiveReconnectReason.mediaError'));
    expect(source, contains('LiveReconnectReason.automaticLineFailover'));
    expect(source, contains('LiveReconnectReason.playbackUrlRefresh'));
    expect(source, contains('LiveLinkEventType.lineChangedByUser'));
    expect(source, contains('LiveLinkEventType.qualityChangedByUser'));
    expect(
      source,
      contains('if (!_isCurrentPlaybackRequest(requestRevision, loadGeneration)'),
    );
  });

  test('user line event is gated by a successful current reopen', () {
    final source = File(
      'lib/modules/live_room/live_room_controller.dart',
    ).readAsStringSync();
    final changeLineStart = source.indexOf('Future<void> changePlayLine(');
    final changeLineEnd = source.indexOf(
      'void _scheduleAutoSelectFastestLine',
      changeLineStart,
    );
    final method = source.substring(changeLineStart, changeLineEnd);

    expect(source, contains('Future<bool> setPlayer({'));
    expect(method, contains('final reopened = await setPlayer('));
    expect(method, contains('if (!reopened || !_isCurrentLoad(loadGeneration))'));
    expect(
      method.indexOf('if (!reopened'),
      lessThan(method.indexOf('LiveLinkEventType.lineChangedByUser')),
    );
  });
}
