import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/category/detail/category_detail_controller.dart';
import 'package:simple_live_app/modules/category/detail/category_detail_page.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_page.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _TestCategoryDetailController extends CategoryDetailController {
  _TestCategoryDetailController(LiveSubCategory category)
      : super(site: Sites.allSites[Constant.kDouyin]!, subCategory: category);

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async => [];
}

class _TestIndexedController extends IndexedController {
  @override
  // Supply inert pages without starting services or reading saved settings.
  // ignore: must_call_super
  void onInit() {
    items.assignAll(Constant.allHomePages.values);
    pages.assignAll([
      for (final item in items) Center(child: Text('root-${item.index}')),
    ]);
    index.value = items.indexWhere((item) => item.index == 2);
  }
}

void main() {
  final leaf = LiveSubCategory(id: 'leaf', name: '叶子分区', parentId: 'child');
  final child = LiveSubCategory(
    id: 'child',
    name: '子分区',
    parentId: 'parent',
    children: [leaf],
  );
  final parent = LiveSubCategory(
    id: 'parent',
    name: '父分区',
    parentId: '',
    children: [child],
  );
  const sizes = [
    Size(390, 844),
    Size(768, 1024),
    Size(1024, 768),
    Size(500, 768),
    Size(1440, 900),
  ];
  final navigation = find.byKey(const ValueKey('root-bottom-navigation'));

  setUp(() {
    Get.testMode = true;
  });
  tearDown(Get.reset);

  void expectDetailWithoutNavigation(WidgetTester tester) {
    expect(find.byType(CategoryDetailPage), findsOneWidget);
    expect(navigation, findsNothing);
    final scaffold = tester.widget<Scaffold>(find.descendant(
      of: find.byType(CategoryDetailPage),
      matching: find.byType(Scaffold),
    ));
    expect(scaffold.bottomNavigationBar, isNull);
    expect(tester.takeException(), isNull);
  }

  for (final category in [parent, leaf]) {
    testWidgets('${category.name} hides navigation across window sizes',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Get.put<CategoryDetailController>(_TestCategoryDetailController(category));
      await tester.binding.setSurfaceSize(sizes.first);
      await tester.pumpWidget(const GetMaterialApp(home: CategoryDetailPage()));
      await tester.pumpAndSettle();

      for (final size in sizes) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpAndSettle();
        expectDetailWithoutNavigation(tester);
      }
    });
  }

  Future<_TestIndexedController> pumpRoot(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(768, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final indexed = _TestIndexedController();
    Get.put<IndexedController>(indexed);
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: RoutePath.kIndex,
      getPages: [
        GetPage(
          name: RoutePath.kIndex,
          page: () => const IndexedPage(glassEnabled: false),
        ),
        GetPage(
          name: RoutePath.kCategoryDetail,
          page: () => CategoryDetailPage(
            controllerTag: Get.arguments['controllerTag'] as String,
          ),
          binding: BindingsBuilder(() {
            Get.put<CategoryDetailController>(
              _TestCategoryDetailController(
                Get.arguments['category'] as LiveSubCategory,
              ),
              tag: Get.arguments['controllerTag'] as String,
            );
          }),
        ),
      ],
    ));
    await tester.pumpAndSettle();
    expect(navigation, findsOneWidget);
    return indexed;
  }

  for (final openAll in [true, false]) {
    final entry = openAll ? 'all rooms' : 'nested categories';
    testWidgets('$entry hides navigation until returning to root',
        (tester) async {
      final indexed = await pumpRoot(tester);
      final selectedIndex = indexed.index.value;
      AppNavigator.toCategoryDetail(
        site: Sites.allSites[Constant.kDouyin]!,
        category: parent,
      );
      await tester.pumpAndSettle();
      expectDetailWithoutNavigation(tester);

      await tester.tap(find.text(openAll ? '全部' : child.name));
      await tester.pumpAndSettle();
      expectDetailWithoutNavigation(tester);
      if (openAll) {
        expect(find.byType(PageGridView), findsOneWidget);
      } else {
        expect(find.text(leaf.name), findsOneWidget);
        await tester.tap(find.text(leaf.name));
        await tester.pumpAndSettle();
        expectDetailWithoutNavigation(tester);
        expect(find.byType(PageGridView), findsOneWidget);
      }

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(CategoryDetailPage), findsNothing);
      expect(navigation, findsOneWidget);
      expect(indexed.index.value, selectedIndex);
      expect(find.text('root-2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
