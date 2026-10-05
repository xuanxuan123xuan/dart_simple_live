import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_glass_mode.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/home/home_page.dart';

class _TestSettingsController extends AppSettingsController {
  @override
  // Keep the layout fixture independent from Hive-backed app startup.
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

  Future<void> pumpTopBar(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 200));
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: Sites.supportSites.length,
          child: Builder(
            builder: (context) {
              return Scaffold(
                appBar: HomeTopBar(
                  controller: DefaultTabController.of(context),
                  iconOnly: true,
                  onSearch: () {},
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('compact top bar keeps an 8px selector-search gap',
      (tester) async {
    for (final width in [320.0, 360.0, 390.0]) {
      await pumpTopBar(tester, width);

      final selectorRect = tester.getRect(
        find.byKey(const ValueKey<String>('site-tab-bar-fallback')),
      );
      final searchRect = tester.getRect(
        find.byKey(const ValueKey<String>('home-top-search-action')),
      );

      expect(
        searchRect.left - selectorRect.right,
        greaterThanOrEqualTo(8),
        reason: 'top bar width: $width',
      );
    }
  });

  testWidgets('wide-enough compact top bar keeps 56px controls',
      (tester) async {
    await pumpTopBar(tester, 390);

    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('site-tab-bar-fallback')),
      ),
      const Size(280, 56),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('home-top-search-action')),
      ),
      const Size.square(56),
    );
    expect(
      {
        for (final site in Sites.supportSites)
          tester.getSize(find.bySemanticsLabel(site.name)).width,
      },
      {56.0},
    );
  });
}
