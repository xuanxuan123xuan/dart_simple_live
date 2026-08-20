import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows fullscreen has a single native window-state owner', () {
    final controller = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();
    final runner = File(
      'windows/runner/flutter_window.cpp',
    ).readAsStringSync();

    expect(controller, isNot(contains('simple_live/windows_chrome')));
    expect(runner, isNot(contains('ApplyFullscreenChrome')));
    expect(runner, isNot(contains('RestoreWindowChrome')));
  });

  test('desktop layout changes only after native fullscreen settles', () {
    final source = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();
    final enterStart = source.indexOf('Future<void> enterFullScreen()');
    final enterEnd = source.indexOf(
      'Future<void> restoreFullScreenSystemUi()',
      enterStart,
    );
    final enterFullScreen = source.substring(enterStart, enterEnd);
    final desktopStart = enterFullScreen.indexOf(
      "Log.d('Desktop fullscreen: enter start')",
    );
    final desktopEnter = enterFullScreen.substring(desktopStart);

    expect(desktopEnter, contains('setFullScreen(true)'));
    expect(desktopEnter, contains('_waitForWindowsFullScreenState(true)'));
    expect(desktopEnter, contains('fullScreenState.value = true'));
    expect(
      desktopEnter.indexOf('setFullScreen(true)'),
      lessThan(desktopEnter.indexOf('fullScreenState.value = true')),
    );
    expect(
      desktopEnter.indexOf('_waitForWindowsFullScreenState(true)'),
      lessThan(desktopEnter.indexOf('fullScreenState.value = true')),
    );
  });
}
