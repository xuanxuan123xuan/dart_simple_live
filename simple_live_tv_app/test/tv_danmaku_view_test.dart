import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/widgets/tv_danmaku_view.dart';

import 'support/multi_room_ui_fixture.dart';

class _Settings extends AppSettingsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  testWidgets(
      'cached single-room canvas applies preferences without reconnecting',
      (tester) async {
    Get.testMode = true;
    final settings = Get.put<AppSettingsController>(_Settings());
    DanmakuController? controller;
    var creations = 0;
    final view = TvDanmakuView(
      screenKey: GlobalKey(),
      createdController: (value) {
        controller = value;
        creations++;
      },
    );
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(1920, 1080),
      builder: (_, child) => GetMaterialApp(home: Scaffold(body: child)),
      child: view,
    ));
    final canvas = tester.element(find.byType(DanmakuScreen));
    final originalController = controller;
    expect(controller!.option.maxLines, 0);

    settings.danmuDisplayMode.value = 'lines';
    await tester.pump();
    expect(controller!.option.maxLines, 3);
    settings.danmuMaxLines.value = 6;
    settings.danmuSize.value = 64;
    settings.danmuOpacity.value = 0.5;
    settings.danmuSpeed.value = 6;
    await tester.pump();
    expect(controller!.option.maxLines, 6);
    expect(controller!.option.fontSize, 64.w);
    expect(controller!.option.opacity, 0.5);
    expect(controller!.option.duration, 6);

    settings.danmuDisplayMode.value = 'area';
    settings.danmuArea.value = 0.5;
    await tester.pump();
    expect(controller!.option.maxLines, 0);
    expect(controller!.option.area, 0.5);
    expect(
        identical(tester.element(find.byType(DanmakuScreen)), canvas), isTrue);
    expect(identical(controller, originalController), isTrue);
    expect(creations, 1);

    await tester.pumpWidget(const SizedBox());
    Get.reset();
    await tester.pump();
  });

  testWidgets('all multi-room canvases follow mode and count changes in place',
      (tester) async {
    final fixture = MultiRoomUiFixture(count: 4);
    addTearDown(() => fixture.dispose(tester));
    fixture.settings.danmuDisplayMode.value = 'lines';
    fixture.settings.danmuMaxLines.value = 6;
    await fixture.pump(tester);
    final elements = find.byType(DanmakuScreen).evaluate().toList();
    final controllers = [
      for (var i = 0; i < 4; i++) fixture.session(i).danmakuController!,
    ];
    expect(elements, hasLength(4));
    for (final controller in controllers) {
      expect(controller.option.maxLines, 6);
    }

    fixture.settings.danmuMaxLines.value = 1;
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      expect(controllers[i].option.maxLines, 1);
      expect(identical(fixture.session(i).danmakuController, controllers[i]),
          isTrue);
    }
    expect(find.byType(DanmakuScreen).evaluate().toList(), elements);

    fixture.settings.danmuDisplayMode.value = 'area';
    fixture.settings.danmuArea.value = 0.75;
    await tester.pump();
    for (final controller in controllers) {
      expect(controller.option.maxLines, 0);
      expect(controller.option.area, 0.75);
    }
  });
}
