import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
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
    ]);
    settings.glassMode.value = AppGlassMode.off;
  });

  tearDown(Get.reset);

  Future<void> pumpBar(
    WidgetTester tester, {
    required double width,
    required bool iconOnly,
    bool glass = false,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 200));
    final tabBar = DefaultTabController(
      length: Sites.supportSites.length,
      child: Builder(
        builder: (context) => SiteGlassTabBar(
          controller: DefaultTabController.of(context),
          iconOnly: iconOnly,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: glass ? LiquidGlassScope(child: tabBar) : tabBar,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('compact icon mode keeps equal slots and semantic names',
      (tester) async {
    await pumpBar(tester, width: 390, iconOnly: true);

    expect(
      tester.getSize(find.byKey(const ValueKey('site-tab-bar-fallback'))).width,
      280,
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
      560,
    );
    for (final site in Sites.supportSites) {
      expect(find.text(site.name), findsOneWidget);
    }
  });

  testWidgets('glass mode keeps compact tabs icon-only', (tester) async {
    settings.glassMode.value = AppGlassMode.standard;
    await pumpBar(tester, width: 390, iconOnly: true, glass: true);

    expect(find.byKey(const ValueKey('site-glass-tab-bar')), findsOneWidget);
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
    // tabWidth is 112 (560 / 5 sites), so a quarter slot is +28 px.
    expect(draggedLeft, closeTo(initialLeft + 28, 0.5));
  });
}
