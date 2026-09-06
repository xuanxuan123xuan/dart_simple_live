import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/mpv_ohos_controller.dart';

void main() {
  test('mpv cache seconds parser accepts only safe non-negative values', () {
    expect(parseMpvOhosDurationSeconds('1.234'),
        const Duration(milliseconds: 1234));
    expect(parseMpvOhosDurationSeconds('0'), Duration.zero);
    for (final invalid in <String>['', 'nan', 'NaN', 'Infinity', '-0.1']) {
      expect(parseMpvOhosDurationSeconds(invalid), isNull, reason: invalid);
    }
    expect(parseMpvOhosDurationSeconds('1e30'), isNull);
  });

  test('cache freshness belongs only to native cache events', () {
    final controller = File(
      'lib/modules/live_room/player/mpv_ohos_controller.dart',
    ).readAsStringSync();
    final player = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();

    expect(controller, contains("case 'demuxer-cache-duration':"));
    expect(controller, isNot(contains("case 'demuxer-cache-time':")));
    expect(controller, contains('onCacheDuration?.call(sampledAt'));
    expect(controller, contains('onCacheDuration?.call(null, null)'));
    expect(player, contains('const Duration(seconds: 3)'));
    expect(
      player,
      isNot(contains('_latestLivePlaybackCacheSampledAt = sampledAt;\n'
          '          _latestLivePlaybackCacheDurationSeconds = ohosCacheSeconds')),
    );
  });
}
