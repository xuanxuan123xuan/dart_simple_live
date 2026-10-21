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

class _TestSettingsController extends AppSettingsController {
  @override
  // Keep the widget fixture independent from Hive-backed app startup.
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  late AppSettingsController settings;

  setUp(() {
    Get.testMode = true;
    settings = Get.put<AppSettingsController>(_TestSettingsController());
    settings.siteSort.assignAll([
      Constant.kBiliBili,
      Constant.kDouyu,
      Constant.kHuya,
      Constant.kDouyin,
      Constant.kKuaishou,
      Constant.kXiaohongshu,
    ]);
    settings.glassMode.value = AppGlassMode.off;
  });

  tearDown(Get.reset);

  Future<TabController> pumpBar(
    WidgetTester tester, {
    required double width,
    required bool iconOnly,
    bool glass = false,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 200));
    TabController? controller;
    final tabBar = DefaultTabController(
      length: Sites.supportSites.length,
      child: Builder(
        builder: (context) {
          controller = DefaultTabController.of(context);
          return SiteGlassTabBar(
            controller: controller!,
            iconOnly: iconOnly,
          );
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: glass ? LiquidGlassScope(child: tabBar) : tabBar,
      ),
    );
    await tester.pumpAndSettle();
    return controller!;
  }

  testWidgets('compact icon mode keeps equal slots and semantic names',
      (tester) async {
    await pumpBar(tester, width: 390, iconOnly: true);

    expect(
      tester.getSize(find.byKey(const ValueKey('site-tab-bar-fallback'))).width,
      56.0 * Sites.supportSites.length,
    );
    final slotWidths = {
      for (final site in Sites.supportSites)
        tester.getSize(find.bySemanticsLabel(site.name)).width,
    };
    expect(slotWidths, {56.0});
    for (final site in Sites.supportSites) {
      expect(find.text(site.name), findsNothing);
      expect(find.bySemanticsLabel(site.name), findsOneWidget);
    }
  });

  testWidgets('wide mode keeps platform names in the same bar', (tester) async {
    await pumpBar(tester, width: 1200, iconOnly: false);

    expect(
      tester.getSize(find.byKey(const ValueKey('site-tab-bar-fallback'))).width,
      112.0 * Sites.supportSites.length,
    );
    for (final site in Sites.supportSites) {
      expect(find.text(site.name), findsOneWidget);
    }
  });

  testWidgets('glass mode keeps compact tabs icon-only', (tester) async {
    settings.glassMode.value = AppGlassMode.auto;
    await pumpBar(tester, width: 390, iconOnly: true, glass: true);

    expect(find.byKey(const ValueKey('site-glass-tab-bar')), findsOneWidget);
    final glassBar = find.byKey(const ValueKey('site-glass-tab-bar'));
    expect(tester.getSize(glassBar).width, 56.0 * Sites.supportSites.length);
    expect(tester.getRect(glassBar).center.dx, closeTo(195, 0.5));
    final slotWidths = {
      for (final site in Sites.supportSites)
        tester.getSize(find.bySemanticsLabel(site.name)).width,
    };
    expect(slotWidths, hasLength(1));
    for (final site in Sites.supportSites) {
      expect(find.text(site.name), findsNothing);
      expect(find.bySemanticsLabel(site.name), findsOneWidget);
    }
  });

  testWidgets('glass mode keeps the wide bar centered and bounded',
      (tester) async {
    settings.glassMode.value = AppGlassMode.auto;
    await pumpBar(tester, width: 1200, iconOnly: false, glass: true);

    final glassBar = find.byKey(const ValueKey('site-glass-tab-bar'));
    expect(tester.getSize(glassBar).width, 112.0 * Sites.supportSites.length);
    expect(tester.getRect(glassBar).center.dx, closeTo(600, 0.5));
  });

  testWidgets('auto glass selector follows every tapped tab slot',
      (tester) async {
    settings.glassMode.value = AppGlassMode.auto;
    final controller = await pumpBar(
      tester,
      width: 600,
      iconOnly: false,
      glass: true,
    );

    for (var i = 0; i < Sites.supportSites.length; i++) {
      final barRect = tester.getRect(
        find.byKey(const ValueKey('site-glass-tab-bar')),
      );
      await tester.tapAt(
        Offset(
          barRect.left + barRect.width * (i + 0.5) / Sites.supportSites.length,
          barRect.center.dy,
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.index, i);
      final indicator = tester.widget<TabIndicator>(find.byType(TabIndicator));
      expect(indicator.indicatorPosition, isNull);
    }
  });

  testWidgets('fallback indicator follows a fractional swipe position',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    settings.glassMode.value = AppGlassMode.off;

    TabController? controller;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: Sites.supportSites.length,
          child: Builder(
            builder: (context) {
              controller = DefaultTabController.of(context);
              return Center(
                child: SizedBox(
                  width: 560,
                  height: 60,
                  child: SiteGlassTabBar(controller: controller!),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final indicator = find.byKey(
      const ValueKey('site-tab-bar-fallback-indicator'),
    );
    expect(indicator, findsOneWidget);
    final initialLeft = tester.getRect(indicator).left;
    expect(controller!.index, 0);

    controller!.offset = 0.25;
    await tester.pump();

    final draggedLeft = tester.getRect(indicator).left;
    // Selection index does not change on a mid-drag frame; the indicator moves.
    expect(controller!.index, 0);
    // A quarter drag moves a quarter of one slot, also when six tabs
    // share a constrained bar.
    final width = tester
        .getSize(find.byKey(const ValueKey('site-tab-bar-fallback')))
        .width;
    expect(draggedLeft,
        closeTo(initialLeft + width / Sites.supportSites.length * 0.25, 0.5));
  });

  testWidgets('auto glass indicator follows a fractional swipe position',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    settings.glassMode.value = AppGlassMode.auto;

    TabController? controller;
    await tester.pumpWidget(
      MaterialApp(
        home: LiquidGlassScope(
          child: DefaultTabController(
            length: Sites.supportSites.length,
            child: Builder(
              builder: (context) {
                controller = DefaultTabController.of(context);
                return Center(
                  child: SizedBox(
                    width: 560,
                    height: 60,
                    child: SiteGlassTabBar(controller: controller!),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    controller!.offset = 0.25;
    await tester.pump();

    expect(controller!.index, 0);
    expect(
      tester.widget<TabIndicator>(find.byType(TabIndicator)).indicatorPosition,
      closeTo(0.25, 0.001),
    );
  });

  testWidgets(
      'auto glass selector follows a held mouse drag and resumes page tracking',
      (tester) async {
    settings.glassMode.value = AppGlassMode.auto;
    final controller = await pumpBar(
      tester,
      width: 600,
      iconOnly: false,
      glass: true,
    );
    final barRect = tester.getRect(find.byType(TabIndicator));
    Offset tabCenter(int index) => Offset(
          barRect.left + barRect.width * (index + 0.5) / controller.length,
          barRect.center.dy,
        );
    final mouse = await tester.startGesture(
      tabCenter(0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 200));
    await mouse.moveTo(tabCenter(1));
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.moveTo(tabCenter(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(controller.index, 0, reason: 'Selection commits only on release.');
    final expectedAlignment = -1 + 4 / (controller.length - 1);
    final paintedIndicator = tester.widget<AnimatedGlassIndicator>(
      find.byType(AnimatedGlassIndicator).last,
    );
    expect(
      paintedIndicator.alignment.resolve(TextDirection.ltr).x,
      closeTo(expectedAlignment, 0.02),
      reason: 'The visible pill must follow the mouse while the page is idle.',
    );

    await mouse.up();
    await tester.pumpAndSettle();
    expect(controller.index, 2);
    expect(
      tester.widget<TabIndicator>(find.byType(TabIndicator)).indicatorPosition,
      isNull,
    );

    controller.offset = -0.25;
    await tester.pump();
    final resumedIndicator = tester.widget<AnimatedGlassIndicator>(
      find.byType(AnimatedGlassIndicator).last,
    );
    expect(
      resumedIndicator.alignment.resolve(TextDirection.ltr).x,
      closeTo(-1 + 2 * 1.75 / (controller.length - 1), 0.001),
      reason: 'After release, page swipes must own the indicator again.',
    );
  });

  testWidgets('auto glass indicator keeps the spring for selector taps',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    settings.glassMode.value = AppGlassMode.auto;

    TabController? controller;
    await tester.pumpWidget(
      MaterialApp(
        home: LiquidGlassScope(
          child: DefaultTabController(
            length: Sites.supportSites.length,
            child: Builder(
              builder: (context) {
                controller = DefaultTabController.of(context);
                return Center(
                  child: SizedBox(
                    width: 560,
                    height: 60,
                    child: SiteGlassTabBar(controller: controller!),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    controller!.animateTo(1, duration: const Duration(milliseconds: 300));
    await tester.pump();

    expect(controller!.indexIsChanging, isTrue);
    expect(
      tester.widget<TabIndicator>(find.byType(TabIndicator)).indicatorPosition,
      isNull,
    );

    await tester.pumpAndSettle();

    expect(controller!.index, 1);
    expect(
      tester.widget<TabIndicator>(find.byType(TabIndicator)).indicatorPosition,
      isNull,
    );
  });
}
