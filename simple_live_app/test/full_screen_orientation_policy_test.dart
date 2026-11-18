import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('force-landscape defaults to following the video orientation', () {
    final settings = File(
      'lib/app/controller/app_settings_controller.dart',
    ).readAsStringSync();
    final controls = File(
      'lib/modules/live_room/player/player_controls.dart',
    ).readAsStringSync();

    expect(settings, contains('fullScreenForceLandscape = false.obs'));
    expect(
      settings,
      matches(RegExp(r'kFullScreenForceLandscape,\s*false,')),
    );
    expect(controls, contains('默认跟随视频方向'));
  });

  test('every live source resets the previous orientation hint', () {
    final controller = File(
      'lib/modules/live_room/live_room_controller.dart',
    ).readAsStringSync();
    final initStart = controller.indexOf('Future<void> initPlaylist');
    final initEnd = controller.indexOf(
      'void _startLiveLatencyTelemetry',
      initStart,
    );
    final initPlaylist = controller.substring(initStart, initEnd);

    expect(initPlaylist, contains('isVertical.value = false;'));
    expect(
      initPlaylist.indexOf('isVertical.value = false;'),
      lessThan(initPlaylist.indexOf('if (Utils.isOhos)')),
    );
  });

  test('OHOS fullscreen exit releases rather than forces orientation', () {
    final player = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();
    final exitStart = player.indexOf('Future<void> exitFull()');
    final ohosExitEnd = player.indexOf(
      'if (Platform.isAndroid || Platform.isIOS)',
      exitStart,
    );
    final ohosExit = player.substring(exitStart, ohosExitEnd);

    expect(
      ohosExit,
      contains(
        'SystemChrome.setPreferredOrientations(DeviceOrientation.values)',
      ),
    );
    expect(ohosExit, isNot(contains('DeviceOrientation.portraitUp')));
    expect(ohosExit, isNot(contains('_waitForOhosViewport(portrait: true)')));
  });
}
