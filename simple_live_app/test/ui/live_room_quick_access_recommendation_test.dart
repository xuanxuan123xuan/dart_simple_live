import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/widgets/live_room_quick_access_panel.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  tearDown(Get.reset);

  for (final size in [const Size(390, 700), const Size(1280, 720)]) {
    testWidgets('recommendation reacts to resolution at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _PanelController();
      final opened = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LiveRoomQuickAccessPanel(
          controller: controller,
          onOpenItem: opened.add,
          onClose: () {},
        )),
      ));
      expect(controller.prepareCalls, 1);
      expect(find.text('正在识别直播间分区'), findsOneWidget);
      var tile = tester.widget<ListTile>(find.widgetWithText(ListTile, '同类推荐'));
      expect(tile.enabled, isFalse);
      controller.ready.value = true;
      controller.subtitle.value = '抖音直播 / 绝地求生';
      await tester.pump();
      tile = tester.widget<ListTile>(find.widgetWithText(ListTile, '同类推荐'));
      expect(tile.enabled, isTrue);
      await tester.tap(find.text('同类推荐'));
      expect(opened, ['recommendation']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unavailable remains disabled and a reopened panel retries',
      (tester) async {
    final controller = _PanelController();
    Future<void> show() => tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: LiveRoomQuickAccessPanel(
            controller: controller,
            onOpenItem: (_) => fail('Unavailable recommendation must not open'),
            onClose: () {},
          )),
        ));
    await show();
    controller.subtitle.value = '无法匹配当前分区，暂不提供同类推荐';
    await tester.pump();
    expect(find.text('无法匹配当前分区，暂不提供同类推荐'), findsOneWidget);
    await tester.tap(find.text('同类推荐'));
    expect(controller.prepareCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await show();
    expect(controller.prepareCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening quick access without recommendations does no lookup',
      (tester) async {
    final controller = _PanelController()..keys = [];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LiveRoomQuickAccessPanel(
      controller: controller,
      onOpenItem: (_) {},
      onClose: () {},
    ))));
    expect(controller.prepareCalls, 0);
    expect(find.text('没有已启用的快捷入口'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _PanelController extends Fake implements LiveRoomController {
  final ready = false.obs;
  final subtitle = '正在识别直播间分区'.obs;
  int prepareCalls = 0;
  List<String> keys = ['recommendation'];
  @override
  final Rx<LiveRoomDetail?> detail = Rx<LiveRoomDetail?>(null);
  @override
  final Rx<Site> rxSite =
      Site(id: 'douyin', name: '抖音直播', logo: '', liveSite: LiveSite()).obs;
  @override
  final Rx<String> rxRoomId = 'room'.obs;
  @override
  List<String> get enabledQuickAccessKeys => keys;
  @override
  bool get hasCategoryRecommendation => ready.value;
  @override
  String quickAccessTitle(String key) => '同类推荐';
  @override
  String quickAccessSubtitle(String key) => subtitle.value;
  @override
  bool shouldPrepareCategoryRecommendation() => false;
  @override
  Future<LiveSubCategory?> prepareCategoryRecommendation() async {
    prepareCalls++;
    return null;
  }
}
