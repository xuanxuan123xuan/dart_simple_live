import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/modules/live_room/player/tv_player_control_bar.dart';

void main() {
  testWidgets(
      'OK activates once and arrows select controls instead of channels',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pauses = 0;
    var mutes = 0;
    var channels = 0;
    var refreshes = 0;
    var parentActivations = 0;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(1920, 1080),
      builder: (_, child) => GetMaterialApp(home: Scaffold(body: child)),
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter) {
            parentActivations++;
          }
          return KeyEventResult.ignored;
        },
        child: TvPlayerControlBar(
          paused: false,
          muted: false,
          volume: 35,
          onTogglePause: () => pauses++,
          onToggleMute: () => mutes++,
          onVolumeDown: () {},
          onVolumeUp: () {},
          onPrevious: () => channels++,
          onNext: () => channels++,
          onRefresh: () => refreshes++,
          onSettings: () {},
          onActivity: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(pauses, 1);
    expect(parentActivations, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(mutes, 1);
    expect(channels, 0);
    await tester.tap(find.text('刷新'));
    expect(refreshes, 1);
    expect(find.text('音量：35'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    Get.reset();
  });
}
