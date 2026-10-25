import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/category/category_list_controller.dart';
import 'package:simple_live_app/modules/category/category_list_view.dart';
import 'package:simple_live_app/widgets/xiaohongshu_link_only_notice.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _FixtureCategoryController extends CategoryListController {
  _FixtureCategoryController(super.site);

  @override
  Future<List<AppLiveCategory>> getData(int page, int pageSize) async => list;

  @override
  Future<void> refreshData() async {}
}

void main() {
  setUpAll(_loadChineseFont);
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  testWidgets('search notice describes link entry without link-only wording',
      (tester) async {
    var retryCount = 0;
    var openSearchCount = 0;

    await tester.pumpWidget(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Microsoft YaHei'),
        home: Scaffold(
          body: XiaohongshuLinkOnlyNotice(
            errorMessage: '发现请求失败',
            onRetry: () => retryCount++,
            onOpenSearch: () => openSearchCount++,
          ),
        ),
      ),
    );

    expect(find.text('发现请求失败'), findsOneWidget);
    expect(find.text('小红书直播搜索暂不可用'), findsOneWidget);
    expect(find.textContaining('搜索框粘贴'), findsOneWidget);
    expect(find.textContaining('只能通过'), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.tap(find.text('粘贴链接进入'));
    expect(retryCount, 1);
    expect(openSearchCount, 1);
  });

  _registerCategoryViewportTest(
    const Size(390, 844),
    'xiaohongshu_categories_phone',
  );
  _registerCategoryViewportTest(
    const Size(1440, 900),
    'xiaohongshu_categories_desktop',
  );

  testWidgets('category discovery error offers retry and search fallback',
      (tester) async {
    final controller = _FixtureCategoryController(
      Sites.allSites[Constant.kXiaohongshu]!,
    )
      ..pageError.value = true
      ..errorMsg.value = '发现请求失败';
    Get.put<CategoryListController>(controller, tag: Constant.kXiaohongshu);

    await tester.pumpWidget(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Microsoft YaHei'),
        home: const Scaffold(
          body: CategoryListView(Constant.kXiaohongshu),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('发现请求失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('粘贴链接进入'), findsOneWidget);
  });
}

void _registerCategoryViewportTest(Size size, String screenshotName) {
  testWidgets('Xiaohongshu category cards render at $screenshotName viewport',
      (tester) async {
    final site = Sites.allSites[Constant.kXiaohongshu]!;
    final controller = _FixtureCategoryController(site)
      ..list.assignAll([
        AppLiveCategory(
            id: 'xiaohongshu',
            name: '小红书直播',
            children: _categories().single.children),
      ]);
    Get.put<CategoryListController>(controller, tag: Constant.kXiaohongshu);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('screenshot-root'),
        child: GetMaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Microsoft YaHei'),
          home: const Scaffold(
            body: CategoryListView(Constant.kXiaohongshu),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('才艺颜值'), findsOneWidget);
    expect(find.text('运动户外'), findsOneWidget);
    expect(find.byType(XiaohongshuLinkOnlyNotice), findsNothing);
    expect(tester.takeException(), isNull);
    await _captureScreenshot(tester, screenshotName);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _captureScreenshot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('screenshot-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/screenshots')
        ..createSync(recursive: true);
      File('${directory.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _loadChineseFont() async {
  final icons = File(
      r'C:\src\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(
              Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
  final fontFile = File(r'C:\Windows\Fonts\simhei.ttf');
  if (!fontFile.existsSync()) return;
  final bytes = fontFile.readAsBytesSync();
  final loader = FontLoader('Microsoft YaHei')
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

// Synthetic discovery response, matching the provider category hierarchy.
List<LiveCategory> _categories() => [
      LiveCategory(
        id: 'xiaohongshu',
        name: '小红书直播',
        children: [
          for (final (id, name) in const [
            ('0', '全部'),
            ('1', '游戏'),
            ('2', '才艺颜值'),
            ('3', '生活分享'),
            ('4', '兴趣手工'),
            ('5', '科技财经'),
            ('6', '运动户外'),
          ])
            LiveSubCategory(id: id, name: name, parentId: 'xiaohongshu'),
        ],
      )
    ];
