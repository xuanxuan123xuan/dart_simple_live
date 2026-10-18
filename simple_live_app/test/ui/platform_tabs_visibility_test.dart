import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:simple_live_app/app/app_glass_mode.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/site_tabs_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/category/category_controller.dart';
import 'package:simple_live_app/modules/category/category_list_controller.dart';
import 'package:simple_live_app/modules/home/home_controller.dart';
import 'package:simple_live_app/modules/home/home_list_controller.dart';
import 'package:simple_live_app/modules/search/search_site_page.dart';
import 'package:simple_live_app/services/live_room_link_parser.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/widgets/glass/site_glass_tab_bar.dart';

class _TabsController extends SiteTabsController {
  final Set<String> initializedSites = {};

  @override
  void ensureSiteController(Site site) => initializedSites.add(site.id);
}

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

class _Settings extends AppSettingsController {
  @override
  // These tests exercise platform tabs without unrelated application services.
  // ignore: must_call_super
  void onInit() {
    initSiteSort();
    initHiddenSiteIds();
  }
}

void main() {
  late AppSettingsController settings;

  setUp(() {
    Get.testMode = true;
    Get.put<LocalStorageService>(_MemoryStorage());
    settings = Get.put<AppSettingsController>(_Settings());
    settings.glassMode.value = AppGlassMode.off;
  });

  tearDown(Get.reset);

  test('hidden platform still resolves direct links and single-site search',
      () async {
    settings.setSiteVisible('bilibili', false);
    expect(Sites.visibleSites.any((site) => site.id == 'bilibili'), isFalse);
    final target = await LiveRoomLinkParser().parse(
      'https://live.bilibili.com/12345',
    );
    expect(target?.site, same(Sites.allSites['bilibili']));
    expect(target?.roomId, '12345');
    final args = SearchSiteRouteArgs.from({'siteId': 'bilibili'});
    expect(args.site, same(Sites.allSites['bilibili']));
  });

  Widget harness(_TabsController controller) => MaterialApp(
        home: LiquidGlassScope(child: Obx(() {
          final tabs = controller.tabs;
          return Scaffold(
            appBar: AppBar(
              title: SiteGlassTabBar(
                controller: tabs.controller,
                sites: tabs.sites,
                iconOnly: true,
              ),
            ),
            body: TabBarView(
              controller: tabs.controller,
              children: [
                for (final site in tabs.sites)
                  Center(
                      key: ValueKey(site.id), child: Text('page:${site.id}')),
              ],
            ),
          );
        })),
      );

  testWidgets('reorder and hide keep selector, page and selected ID aligned',
      (tester) async {
    final controller = Get.put(_TabsController());
    final original = Sites.supportSites.map((site) => site.id).toList();
    await tester.pumpWidget(harness(controller));
    controller.tabController.animateTo(2);
    await tester.pumpAndSettle();
    expect(find.text('page:${original[2]}'), findsOneWidget);

    settings.setSiteSort(original.reversed.toList());
    await tester.pumpAndSettle();
    expect(
        controller.tabs.sites[controller.tabController.index].id, original[2]);
    expect(find.text('page:${original[2]}'), findsOneWidget);

    settings.setSiteVisible(original[2], false);
    await tester.pumpAndSettle();
    expect(controller.tabController.index, 0);
    expect(find.text('page:${original.last}'), findsOneWidget);
    final selector =
        tester.widget<SiteGlassTabBar>(find.byType(SiteGlassTabBar));
    final pages = tester.widget<TabBarView>(find.byType(TabBarView));
    expect(selector.sites!.map((site) => site.id),
        controller.tabs.sites.map((site) => site.id));
    expect(pages.children.length, 5);
    expect(controller.tabController.length, 5);

    settings.setSiteVisible(original[2], true);
    await tester.pumpAndSettle();
    expect(controller.tabs.sites.map((site) => site.id), original.reversed);
    expect(controller.initializedSites.length, 6);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rapid changes during swipe and one-platform layout are safe',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = Get.put(_TabsController());
    final original = Sites.supportSites.map((site) => site.id).toList();
    await tester.pumpWidget(harness(controller));
    controller.tabController.animateTo(4);
    await tester.pump(const Duration(milliseconds: 40));
    for (final id in original.skip(1)) {
      settings.setSiteVisible(id, false);
    }
    await tester.pumpAndSettle();
    expect(controller.tabController.length, 1);
    expect(find.text('page:${original.first}'), findsOneWidget);
    for (final id in original.skip(1)) {
      settings.setSiteVisible(id, true);
    }
    await tester.pumpAndSettle();
    expect(controller.tabController.length, 6);
    expect(tester.takeException(), isNull);
    // Close with an animation active to exercise ticker cleanup.
    controller.tabController.animateTo(5);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(const SizedBox());
    Get.delete<_TabsController>();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('lazy home and category retain per-platform list controllers',
      (tester) async {
    final ids = Sites.supportSites.map((site) => site.id).toList();
    // Both pages may be opened for the first time after settings have changed.
    settings.setSiteVisible(ids.last, false);
    final home = Get.put(HomeController());
    final category = Get.put(CategoryController());
    expect(home.tabController.length, 5);
    expect(category.tabController.length, 5);
    expect(Get.isRegistered<HomeListController>(tag: ids.last), isFalse);
    expect(Get.isRegistered<CategoryListController>(tag: ids.last), isFalse);
    final homeList = Get.find<HomeListController>(tag: ids.first);
    final categoryList = Get.find<CategoryListController>(tag: ids.first);
    home.tabController.index = 1;
    category.tabController.index = 2;
    settings.setSiteSort(ids.reversed.toList());
    settings.setSiteVisible(ids.last, true);
    await tester.pump();
    expect(home.tabs.sites[home.tabController.index].id, ids[1]);
    expect(category.tabs.sites[category.tabController.index].id, ids[2]);
    expect(Get.find<HomeListController>(tag: ids.first), same(homeList));
    expect(
        Get.find<CategoryListController>(tag: ids.first), same(categoryList));
    expect(Get.isRegistered<HomeListController>(tag: ids.last), isTrue);
    expect(Get.isRegistered<CategoryListController>(tag: ids.last), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'glass selector supports mouse selection after visibility changes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    settings.glassMode.value = AppGlassMode.auto;
    final controller = Get.put(_TabsController());
    final sites = Sites.supportSites;
    await tester.pumpWidget(harness(controller));
    expect(find.byKey(const ValueKey('site-glass-tab-bar')), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(sites[1].name),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('page:${sites[1].id}'), findsOneWidget);
    for (final site in sites.where((site) => site.id != sites[1].id)) {
      settings.setSiteVisible(site.id, false);
    }
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(sites[1].name), findsOneWidget);
    expect(controller.tabController.length, 1);
    settings.setSiteVisible(sites[2].id, true);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(TabBarView), const Offset(-900, 0));
    await tester.pumpAndSettle();
    expect(find.text('page:${sites[2].id}'), findsOneWidget);
    expect(controller.tabController.index, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
