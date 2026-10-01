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

  test('Windows fullscreen uses the app-owned method channel', () {
    final controller = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/windows_fullscreen_service.dart',
    ).readAsStringSync();
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final windowsBranchStart = controller.indexOf(
      'Future<bool> _setWindowsFullScreenState(bool value)',
    );
    final windowsBranch = controller.substring(windowsBranchStart);
    final nativeWindowsBranch = windowsBranch.substring(
      windowsBranch.indexOf('try {'),
      windowsBranch.indexOf('Future<void> _waitForWindowMaximizedState'),
    );

    expect(controller, contains('WindowsFullscreenService.setFullScreen'));
    expect(
      nativeWindowsBranch,
      isNot(contains('windowManager.setFullScreen(value)')),
    );
    expect(service, contains("simple_live/windows_fullscreen"));
    expect(runner, contains('windows_fullscreen_channel_'));
    expect(runner, contains('windows_fullscreen_.Enter(GetHandle())'));
    expect(runner, contains('windows_fullscreen_.Exit(GetHandle())'));
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

    expect(desktopEnter, contains('_setWindowsFullScreenState(true)'));
    expect(desktopEnter, isNot(contains('_waitForWindowsFullScreenState(true)')));
    expect(desktopEnter, contains('fullScreenState.value = true'));
    expect(
      desktopEnter.indexOf('_setWindowsFullScreenState(true)'),
      lessThan(desktopEnter.indexOf('fullScreenState.value = true')),
    );
  });
}
