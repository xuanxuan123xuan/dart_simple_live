import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_controller.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_page.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_player_controller.dart';

class _Settings extends AppSettingsController {
  @override
  // The UI fixture uses default values without local storage.
  // ignore: must_call_super
  void onInit() {}
}

class _Session extends MultiRoomPlayerController {
  _Session(super.item) {
    loading.value = false;
    liveState.value = LiveStatusState.live;
  }

  int pauseActions = 0;

  @override
  Future<void> togglePause() async {
    pauseActions++;
    userPaused.value = !userPaused.value;
  }
}

class _Rooms extends MultiRoomController {
  _Rooms(List<MultiRoomItem> items) : super(items) {
    rooms.assignAll(items);
    mainRoomKey.value = items.first.key;
    for (final item in items) {
      sessions[item.key] = _Session(item);
    }
  }

  @override
  // No native players, timers, or lifecycle observers are needed to render.
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> closePlaybackSession() async {
    for (final node in focusNodes.values) {
      node.dispose();
    }
    focusNodes.clear();
  }
}

void main() {
  testWidgets('four-room layouts fit TV and OK activates the focused control',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Get.testMode = true;
    final settings = Get.put<AppSettingsController>(_Settings());
    final site = Site(
      id: 'douyu',
      name: '斗鱼',
      logo: '',
      index: 0,
      liveSite: DouyuSite(),
    );
    final controller = Get.put<MultiRoomController>(_Rooms([
      for (var index = 0; index < 4; index++)
        MultiRoomItem(
            site: site, roomId: '$index', userName: '主播$index', face: ''),
    ]));
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(1920, 1080),
      builder: (_, child) => GetMaterialApp(home: child),
      child: const MultiRoomPage(),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    controller.focusNodeFor(controller.rooms.first).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byTooltip('暂停'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect((controller.sessions.values.first as _Session).pauseActions, 1);
    expect(find.byTooltip('继续'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byTooltip('继续'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
        controller.focusNodeFor(controller.rooms[1]).hasPrimaryFocus, isTrue);
    settings.multiRoomLayout.value = 'mainSub';
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('多屏同播（4/4）'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    Get.reset();
  });
}
