import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:simple_live_app/app/app_glass_mode.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/category/category_controller.dart';
import 'package:simple_live_app/modules/category/category_list_controller.dart';
import 'package:simple_live_app/modules/category/category_page.dart';
import 'package:simple_live_app/modules/home/home_controller.dart';
import 'package:simple_live_app/modules/home/home_list_controller.dart';
import 'package:simple_live_app/modules/home/home_page.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/widgets/glass/site_glass_tab_bar.dart';
import 'package:simple_live_core/simple_live_core.dart';

const _pageBackground = Color(0xff24364a);
const _rootBackground = Color(0xff785634);

class _MemoryStorage extends LocalStorageService {
  final Map<dynamic, dynamic> values = {};

  @override
  T getValue<T>(dynamic key, T defaultValue) =>
      values[key] as T? ?? defaultValue;

  @override
  Future<void> setValue<T>(dynamic key, T value) async {
    values[key] = value;
  }
}

class _TestSettingsController extends AppSettingsController {
  @override
  // These page tests need only site visibility and the glass fallback mode.
  // ignore: must_call_super
  void onInit() {
    initSiteSort();
    initHiddenSiteIds();
  }
}

class _TestHomeController extends HomeController {
  @override
  // Page-list controllers are registered explicitly with offline fixtures.
  // ignore: must_call_super
  void onInit() {}
}

class _OfflineHomeListController extends HomeListController {
  _OfflineHomeListController(super.site);

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async => [];
}

class _TestCategoryController extends CategoryController {
  @override
  // Page-list controllers are registered explicitly with offline fixtures.
  // ignore: must_call_super
  void onInit() {}
}

class _OfflineCategoryListController extends CategoryListController {
  _OfflineCategoryListController(super.site);

  @override
  Future<List<AppLiveCategory>> getData(int page, int pageSize) async => [];
}

void main() {
  late AppSettingsController settings;

  setUp(() {
    Get.testMode = true;
    Get.put<LocalStorageService>(_MemoryStorage());
    settings = Get.put<AppSettingsController>(_TestSettingsController());
    settings.glassMode.value = AppGlassMode.off;
  });

  tearDown(Get.reset);

  Widget rootHarness(Widget page) => GetMaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: _pageBackground),
        home: LiquidGlassScope(
          child: GlassBackgroundSource(
            key: const ValueKey<String>('root-page-glass-source'),
            child: ColoredBox(
              color: _rootBackground,
              child: page,
            ),
          ),
        ),
      );

  Future<void> expectIsolatedPageCapture(
    WidgetTester tester, {
    required bool hasSearchAction,
    required bool glassEnabled,
  }) async {
    final sourceFinder = find.byWidgetPredicate((widget) {
      if (widget is! GlassBackgroundSource || widget.key != null) return false;
      final child = widget.child;
      return child is ColoredBox && child.child is TabBarView;
    });
    expect(sourceFinder, findsOneWidget);

    final source = tester.widget<GlassBackgroundSource>(sourceFinder);
    expect(source.enabled, isTrue);
    expect(source.child, isA<ColoredBox>());

    final background = source.child as ColoredBox;
    expect(background.color, _pageBackground);
    expect(background.child, isA<TabBarView>());

    final scopeKey = LiquidGlassScope.of(tester.element(sourceFinder));
    expect(scopeKey, isNotNull);
    final sampledBoundaryFinder = find.byKey(scopeKey!);
    expect(sampledBoundaryFinder, findsOneWidget);
    final rootSourceFinder =
        find.byKey(const ValueKey<String>('root-page-glass-source'));
    expect(rootSourceFinder, findsOneWidget);
    final rootScopeKey = LiquidGlassScope.of(tester.element(rootSourceFinder));
    expect(rootScopeKey, isNotNull);
    expect(scopeKey, isNot(same(rootScopeKey)));
    final rootBoundaryFinder = find.byKey(rootScopeKey!);
    expect(rootBoundaryFinder, findsOneWidget);
    expect(
      find.descendant(
        of: rootBoundaryFinder,
        matching: find.byType(AppBar),
      ),
      findsOneWidget,
    );

    final sampledBoundary =
        tester.widget<RepaintBoundary>(sampledBoundaryFinder);
    expect(sampledBoundary.child, same(source.child));
    expect(
      find.descendant(
        of: sampledBoundaryFinder,
        matching: find.byType(AppBar),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: sampledBoundaryFinder,
        matching: find.byType(SiteGlassTabBar),
      ),
      findsNothing,
    );
    if (glassEnabled) {
      final glassBarFinder = find.byKey(
        const ValueKey<String>('site-glass-tab-bar'),
      );
      expect(glassBarFinder, findsOneWidget);
      final glassBar = tester.widget<GlassTabBar>(glassBarFinder);
      expect(glassBar.backgroundKey, same(scopeKey));
      expect(glassBar.backgroundKey, isNot(same(rootScopeKey)));
    } else {
      expect(
        find.byKey(const ValueKey<String>('site-tab-bar-fallback')),
        findsOneWidget,
      );
    }
    if (hasSearchAction) {
      final searchActionFinder =
          find.byKey(const ValueKey<String>('home-top-search-action'));
      expect(searchActionFinder, findsOneWidget);
      expect(
        find.descendant(
          of: sampledBoundaryFinder,
          matching: searchActionFinder,
        ),
        findsNothing,
      );
    }
  }

  testWidgets('home samples its opaque body without sampling its top bar',
      (tester) async {
    final controller = Get.put<HomeController>(_TestHomeController());
    for (final site in controller.tabs.sites) {
      Get.put<HomeListController>(
        _OfflineHomeListController(site),
        tag: site.id,
      );
    }

    settings.glassMode.value = AppGlassMode.standard;
    await tester.pumpWidget(rootHarness(const HomePage()));
    await tester.pump(const Duration(milliseconds: 500));

    await expectIsolatedPageCapture(
      tester,
      hasSearchAction: true,
      glassEnabled: true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('category samples its opaque body without sampling its top bar',
      (tester) async {
    final controller = Get.put<CategoryController>(_TestCategoryController());
    for (final site in controller.tabs.sites) {
      Get.put<CategoryListController>(
        _OfflineCategoryListController(site),
        tag: site.id,
      );
    }

    settings.glassMode.value = AppGlassMode.standard;
    await tester.pumpWidget(rootHarness(const CategoryPage()));
    await tester.pump(const Duration(milliseconds: 500));

    await expectIsolatedPageCapture(
      tester,
      hasSearchAction: false,
      glassEnabled: true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('home keeps the site selector fallback when glass is off',
      (tester) async {
    final controller = Get.put<HomeController>(_TestHomeController());
    for (final site in controller.tabs.sites) {
      Get.put<HomeListController>(
        _OfflineHomeListController(site),
        tag: site.id,
      );
    }

    await tester.pumpWidget(rootHarness(const HomePage()));
    await tester.pump(const Duration(milliseconds: 500));

    await expectIsolatedPageCapture(
      tester,
      hasSearchAction: true,
      glassEnabled: false,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('category keeps the site selector fallback when glass is off',
      (tester) async {
    final controller = Get.put<CategoryController>(_TestCategoryController());
    for (final site in controller.tabs.sites) {
      Get.put<CategoryListController>(
        _OfflineCategoryListController(site),
        tag: site.id,
      );
    }

    await tester.pumpWidget(rootHarness(const CategoryPage()));
    await tester.pump(const Duration(milliseconds: 500));

    await expectIsolatedPageCapture(
      tester,
      hasSearchAction: false,
      glassEnabled: false,
    );
    expect(tester.takeException(), isNull);
  });
}
