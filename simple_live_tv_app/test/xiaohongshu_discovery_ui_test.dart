import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/category/category_controller.dart';
import 'package:simple_live_tv_app/modules/category/category_page.dart';
import 'package:simple_live_tv_app/modules/hot_live/hot_live_controller.dart';
import 'package:simple_live_tv_app/modules/hot_live/hot_live_page.dart';
import 'package:simple_live_tv_app/widgets/highlight_widget.dart';
import 'package:simple_live_tv_app/widgets/tv_xiaohongshu_link_notice.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _FixtureCategoryController extends CategoryController {
  // Synthetic fixtures skip automatic network loading.
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _FixtureHotLiveController extends HotliveController {
  // Synthetic fixtures skip automatic network loading.
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  setUpAll(_loadChineseFont);
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  Widget tvHarness(Widget child) => ScreenUtilInit(
        designSize: const Size(1920, 1080),
        builder: (context, child) => GetMaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Microsoft YaHei'),
          home: child,
        ),
        child: child,
      );

  testWidgets('error fallback exposes remote focusable retry and link entry',
      (tester) async {
    var retryCount = 0;
    await tester.pumpWidget(
      tvHarness(
        TvXiaohongshuLinkNotice(
          errorMessage: '发现请求失败',
          onRetry: () => retryCount++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发现请求失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('打开直播间'), findsOneWidget);
    expect(find.byType(HighlightWidget), findsNWidgets(2));

    final buttons = tester
        .widgetList<HighlightWidget>(find.byType(HighlightWidget))
        .toList();
    expect(buttons.first.focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(buttons.last.focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(buttons.first.focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(retryCount, 1);
  });

  testWidgets('TV hot page renders Xiaohongshu room cards', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    final controller = _FixtureHotLiveController()
      ..siteId.value = Constant.kXiaohongshu
      ..site = Sites.allSites[Constant.kXiaohongshu]!
      ..list.addAll([
        for (var index = 1; index <= 5; index++)
          LiveRoomItemExt(
            roomId: 'room-$index',
            title: index == 1 ? '正在直播的房间' : '直播房间 $index',
            cover: '',
            userName: '主播 $index',
          ),
      ]);
    Get.put<HotliveController>(controller);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('screenshot-root'),
        child: tvHarness(const HotLivePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('正在直播的房间'), findsOneWidget);
    expect(find.byType(TvXiaohongshuLinkNotice), findsNothing);
    expect(tester.takeException(), isNull);
    await _captureScreenshot(tester, 'xiaohongshu_hot_live_tv');
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('TV category page renders Xiaohongshu category cards',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    final site = Sites.allSites[Constant.kXiaohongshu]!;
    final controller = _FixtureCategoryController()
      ..site = site
      ..siteId.value = Constant.kXiaohongshu
      ..list.assignAll([
        AppLiveCategory.fromLiveCategory(_categories().single, site),
      ]);
    Get.put<CategoryController>(controller);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('screenshot-root'),
        child: tvHarness(const CategoryPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('游戏'), findsOneWidget);
    expect(find.text('生活分享'), findsOneWidget);
    expect(find.text('科技财经'), findsOneWidget);
    expect(find.byType(TvXiaohongshuLinkNotice), findsNothing);
    expect(tester.takeException(), isNull);
    await _captureScreenshot(tester, 'xiaohongshu_category_tv');
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  test('TV discovery ignores old requests after switching sites', () async {
    final old = _ControlledSite();
    final next = _ControlledSite();
    _replaceSite(Constant.kBiliBili, old);
    _replaceSite(Constant.kXiaohongshu, next);
    final hot = HotliveController();
    final categories = CategoryController();
    addTearDown(hot.onClose);
    addTearDown(categories.onClose);
    final oldHot = hot.refreshData();
    final oldCategories = categories.refreshData();
    final newHot = hot.setSite(Constant.kXiaohongshu);
    final newCategories = categories.setSite(Constant.kXiaohongshu);
    next.rooms
        .complete(LiveCategoryResult(items: [_room('new')], hasMore: false));
    next.categories.complete(_categories());
    await Future.wait([newHot, newCategories]);
    old.rooms
        .complete(LiveCategoryResult(items: [_room('old')], hasMore: true));
    old.categories
        .complete([LiveCategory(id: 'old', name: 'old', children: [])]);
    await Future.wait([oldHot, oldCategories]);
    expect(hot.list.single.roomId, 'new');
    expect(hot.canLoadMore.value, isFalse);
    expect(categories.list.single.name, '小红书直播');
    expect(categories.list.single.site.id, Constant.kXiaohongshu);
    await hot.loadData();
    expect(next.roomCalls, 1);
  });

  test('TV category switch failure retains selected site and page error',
      () async {
    final original = Sites.allSites[Constant.kXiaohongshu]!;
    final failingSite = Site(
      id: Constant.kXiaohongshu,
      name: original.name,
      logo: original.logo,
      index: original.index,
      liveSite: _FailingCategorySite(),
    );
    Sites.allSites[Constant.kXiaohongshu] = failingSite;
    addTearDown(() {
      Sites.allSites[Constant.kXiaohongshu] = original;
      failingSite.appFocusNode.dispose();
    });
    final controller = CategoryController();
    addTearDown(controller.onClose);

    await controller.setSite(Constant.kXiaohongshu);

    expect(controller.site, same(failingSite));
    expect(controller.siteId.value, Constant.kXiaohongshu);
    expect(controller.pageError.value, isTrue);
    expect(controller.errorMsg.value.trim(), 'discovery failed');
    expect(controller.currentPage, 1);
    await controller.loadData();
    expect(controller.siteId.value, Constant.kXiaohongshu);
    expect(controller.pageError.value, isTrue);
    expect((failingSite.liveSite as _FailingCategorySite).calls, 2);
  });
}

class _FailingCategorySite extends LiveSite {
  int calls = 0;
  @override
  Future<List<LiveCategory>> getCategores() async {
    calls++;
    throw Exception('discovery failed');
  }
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

void _replaceSite(String id, LiveSite provider) {
  final original = Sites.allSites[id]!;
  final replacement = Site(
      id: id,
      name: original.name,
      logo: original.logo,
      index: original.index,
      liveSite: provider);
  Sites.allSites[id] = replacement;
  addTearDown(() {
    Sites.allSites[id] = original;
    replacement.appFocusNode.dispose();
  });
}

LiveRoomItem _room(String id) => LiveRoomItem(
      roomId: id,
      title: id,
      cover: '',
      userName: id,
    );

class _ControlledSite extends LiveSite {
  final rooms = Completer<LiveCategoryResult>();
  final categories = Completer<List<LiveCategory>>();
  int roomCalls = 0;
  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) {
    roomCalls++;
    return rooms.future;
  }

  @override
  Future<List<LiveCategory>> getCategores() => categories.future;
}
