import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:liquid_glass_widgets/src/widgets/surfaces/tab_bar_bottom_internal.dart';
import 'package:simple_live_app/app/app_glass_mode.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/widgets/glass/site_glass_tab_bar.dart';

class _Settings extends AppSettingsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  setUp(() {
    Get.testMode = true;
    final settings = Get.put<AppSettingsController>(_Settings());
    settings.siteSort.assignAll([
      Constant.kBiliBili,
      Constant.kDouyu,
      Constant.kHuya,
      Constant.kDouyin,
      Constant.kKuaishou,
      Constant.kXiaohongshu,
    ]);
    settings.glassMode.value = AppGlassMode.standard;
  });
  tearDown(Get.reset);

  Future<TabController> pumpSelector(
    WidgetTester tester, {
    bool iconOnly = false,
    int count = 4,
  }) async {
    TabController? controller;
    await tester.pumpWidget(MaterialApp(
      home: LiquidGlassScope(
        child: DefaultTabController(
          length: count,
          child: Builder(builder: (context) {
            controller = DefaultTabController.of(context);
            return Scaffold(
              body: Column(children: [
                SiteGlassTabBar(
                  controller: controller!,
                  sites: Sites.supportSites.take(count).toList(),
                  iconOnly: iconOnly,
                ),
                Expanded(
                  child: TabBarView(
                    controller: controller,
                    children: [
                      for (var i = 0; i < count; i++)
                        ColoredBox(color: Colors.primaries[i]),
                    ],
                  ),
                ),
              ]),
            );
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return controller!;
  }

  double alignment(WidgetTester tester, {Finder? within}) {
    final indicators = within == null
        ? find.byType(AnimatedGlassIndicator)
        : find.descendant(
            of: within, matching: find.byType(AnimatedGlassIndicator));
    return tester
        .widget<AnimatedGlassIndicator>(indicators.last)
        .alignment
        .resolve(TextDirection.ltr)
        .x;
  }

  testWidgets(
      'page animation completion preserves the bottom-style spring tail',
      (tester) async {
    TabController? controller;
    final referenceIndex = ValueNotifier(0);
    addTearDown(referenceIndex.dispose);
    const referenceKey = ValueKey('reference-bottom-spring');
    await tester.pumpWidget(MaterialApp(
      home: LiquidGlassScope(
        child: DefaultTabController(
          length: 4,
          child: Builder(builder: (context) {
            controller = DefaultTabController.of(context);
            return Column(children: [
              SiteGlassTabBar(
                controller: controller!,
                sites: Sites.supportSites.take(4).toList(),
              ),
              ValueListenableBuilder<int>(
                valueListenable: referenceIndex,
                builder: (context, index, _) => GlassTabBar.inline(
                  key: referenceKey,
                  tabs: const [
                    GlassTab(icon: Icon(Icons.home)),
                    GlassTab(icon: Icon(Icons.category)),
                    GlassTab(icon: Icon(Icons.star)),
                    GlassTab(icon: Icon(Icons.person)),
                  ],
                  selectedIndex: index,
                  onTabSelected: (_) {},
                  quality: GlassQuality.standard,
                  barHeight: 64,
                ),
              ),
            ]);
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final selector = find.byType(SiteGlassTabBar);
    final reference = find.byKey(referenceKey);

    for (final target in [3, 1, 2]) {
      controller!.animateTo(target, duration: const Duration(milliseconds: 40));
      referenceIndex.value = target;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 41));
      expect(controller!.indexIsChanging, isFalse);
      final targetAlignment = -1 + 2 * target / 3;
      expect(alignment(tester, within: selector),
          closeTo(alignment(tester, within: reference), 0.0001));
      expect((alignment(tester, within: selector) - targetAlignment).abs(),
          greaterThan(0.01),
          reason: 'The page has finished, but the spring must still move.');
      await tester.pump(const Duration(milliseconds: 16));
      expect(alignment(tester, within: selector),
          closeTo(alignment(tester, within: reference), 0.0001));
    }
    await tester.pumpAndSettle();
    expect(alignment(tester, within: selector), closeTo(1 / 3, 0.001));
  });

  for (final iconOnly in [false, true]) {
    for (final complete in [false, true]) {
      testWidgets(
          'page swipe iconOnly=$iconOnly complete=$complete hands off without a stale target',
          (tester) async {
        final controller = await pumpSelector(tester, iconOnly: iconOnly);
        final gesture = await tester
            .startGesture(tester.getCenter(find.byType(TabBarView)));
        await gesture.moveBy(const Offset(-250, 0));
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.offset.abs(), greaterThan(0.01));
        final position = controller.animation!.value;
        expect(alignment(tester), closeTo(-1 + 2 * position / 3, 0.001));

        if (complete) {
          await gesture.moveBy(const Offset(-450, 0));
        } else {
          await gesture.moveBy(const Offset(245, 0));
        }
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.up();
        await tester.pumpAndSettle();
        final expected = complete ? 1 : 0;
        expect(controller.index, expected);
        expect(
            tester
                .widget<TabIndicator>(find.byType(TabIndicator))
                .indicatorPosition,
            isNull);
        final target = -1 + 2 * expected / 3;
        expect(alignment(tester), closeTo(target, 0.001));
        final state =
            tester.state<TabIndicatorState>(find.byType(TabIndicator));
        expect(state.tabXAlign, closeTo(target, 0.001));
        // A new tap after handoff must begin at the last page's position.
        controller.animateTo(2);
        await tester.pump();
        expect(alignment(tester), closeTo(target, 0.001));
        await tester.pumpAndSettle();
        expect(alignment(tester), closeTo(1 / 3, 0.001));
      });
    }
  }

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('${kind.name} drag and cancellation keep the selector usable',
        (tester) async {
      final controller = await pumpSelector(tester, iconOnly: true);
      final rect = tester.getRect(find.byType(TabIndicator));
      Offset center(int index) =>
          Offset(rect.left + rect.width * (index + 0.5) / 4, rect.center.dy);
      final gesture = await tester.startGesture(center(0), kind: kind);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveTo(center(1));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(center(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(controller.index, 0);
      expect(alignment(tester), closeTo(1 / 3, 0.03));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.index, 2);

      final canceled = await tester.startGesture(center(1), kind: kind);
      await tester.pump(const Duration(milliseconds: 200));
      await canceled.moveBy(const Offset(1, 0));
      await canceled.cancel();
      await tester.pumpAndSettle();
      expect(controller.index, 2);
      await tester.tapAt(center(1), kind: kind);
      await tester.pumpAndSettle();
      expect(controller.index, 1);
    });
  }

  for (final count in [1, 6]) {
    testWidgets(
        'narrow icon selector with $count platforms stays within layout',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller =
          await pumpSelector(tester, count: count, iconOnly: true);
      expect(tester.getSize(find.byType(TabIndicator)).height, 56);
      expect(tester.getSize(find.byType(TabIndicator)).width,
          lessThanOrEqualTo(320));
      final rect = tester.getRect(find.byType(TabIndicator));
      await tester
          .tapAt(Offset(rect.right - rect.width / count / 2, rect.center.dy));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(controller.index, count - 1);
      expect(alignment(tester), closeTo(count == 1 ? 0 : 1, 0.001));
    });
  }
}
