import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary playback does not use a periodic latency telemetry timer', () {
    final controller = File(
      'lib/modules/live_room/live_room_controller.dart',
    ).readAsStringSync();
    final start = controller.indexOf('void _startLiveLatencyTelemetry');
    final end = controller.indexOf(
      'Future<void> _sampleLiveLatencyTelemetry',
      start,
    );
    final telemetry = controller.substring(start, end);

    expect(controller, contains('Duration(seconds: 30)'));
    expect(telemetry, contains('_scheduleLiveLatencyTelemetrySample'));
    expect(telemetry, isNot(contains('Timer.periodic')));
    expect(controller, contains('setPlaybackDiagnosticsActive'));
  });

  test('playback diagnostics expose danmaku load counters', () {
    final player = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();

    expect(player, contains("'弹幕消息速率'"));
    expect(player, contains("'弹幕图片消息'"));
    expect(player, contains("'弹幕视图重建'"));
    expect(player, contains('_danmakuOverlayMessageCount += 1;'));
  });
}
