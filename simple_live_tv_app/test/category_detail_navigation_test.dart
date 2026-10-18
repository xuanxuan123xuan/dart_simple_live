import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/category/category_controller.dart';
import 'package:simple_live_tv_app/modules/category/detail/category_detail_controller.dart';
import 'package:simple_live_tv_app/modules/category/detail/category_detail_page.dart';

void main() {
  group('CategoryDetailController', () {
    test('preserves recursively nested categories in the TV model', () {
      final liveSite = _FakeLiveSite();
      final site = _fakeSite(liveSite);
      final root = LiveCategory(
        id: 'root',
        name: '游戏',
        children: [
          LiveSubCategory(
            id: 'second',
            name: '射击游戏',
            parentId: 'root',
            children: [
              LiveSubCategory(
                id: 'third',
                name: '战术竞技',
                parentId: 'second',
                children: [
                  LiveSubCategory(
                    id: 'fourth',
                    name: '大逃杀',
                    parentId: 'third',
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final tvRoot = AppLiveCategory.fromLiveCategory(root, site);

      expect(tvRoot.childrenExt.single.id, 'second');
      expect(tvRoot.childrenExt.single.children.single.id, 'third');
      expect(
        (tvRoot.childrenExt.single.children.single as LiveSubCategoryExt)
            .children
            .single
            .id,
        'fourth',
      );
    });

    test('follows hasMore and stops requesting pages when it is false',
        () async {
      final liveSite = _FakeLiveSite()
        ..results['leaf:1'] = LiveCategoryResult(
          hasMore: true,
          items: [_room('one')],
        )
        ..results['leaf:2'] = LiveCategoryResult(
          hasMore: false,
          items: [_room('two')],
        );
      final site = _fakeSite(liveSite);
      final controller = CategoryDetailController(
        site: site,
        subCategory: _tvCategory(site, id: 'leaf', name: '综合'),
      );
      addTearDown(controller.onClose);

      await controller.loadData();
      expect(controller.list.map((item) => item.roomId), ['one']);
      expect(controller.canLoadMore.value, isTrue);
      expect(controller.currentPage, 2);

      await controller.loadData();
      expect(controller.list.map((item) => item.roomId), ['one', 'two']);
      expect(controller.canLoadMore.value, isFalse);
      expect(liveSite.requests, ['leaf:1', 'leaf:2']);

      await controller.loadData();
      expect(liveSite.requests, ['leaf:1', 'leaf:2']);
    });

    test('ignores a room response after moving to another category', () async {
      final pendingParentRooms = Completer<LiveCategoryResult>();
      final liveSite = _FakeLiveSite()
        ..pending['parent:1'] = pendingParentRooms
        ..results['child:1'] = LiveCategoryResult(
          hasMore: false,
          items: [_room('child-room')],
        );
      final site = _fakeSite(liveSite);
      final root = _tvCategory(
        site,
        id: 'parent',
        name: '游戏',
        children: [
          LiveSubCategory(
            id: 'child',
            name: '射击',
            parentId: 'parent',
          ),
        ],
      );
      final controller =
          CategoryDetailController(site: site, subCategory: root);
      addTearDown(controller.onClose);

      final staleRequest = controller.openAllRooms();
      controller.handleBack();
      final childRequest = controller.openSubCategory(
        controller.currentChildren.single,
      );
      await childRequest;

      pendingParentRooms.complete(
        LiveCategoryResult(hasMore: true, items: [_room('stale-parent-room')]),
      );
      await staleRequest;

      expect(controller.currentSubCategory.id, 'child');
      expect(controller.list.map((item) => item.roomId), ['child-room']);
      expect(controller.canLoadMore.value, isFalse);
    });

    test('caches plain children and preserves externally owned focus nodes',
        () {
      final site = _fakeSite(_FakeLiveSite());
      final root = LiveSubCategoryExt(
        id: 'parent',
        name: '游戏',
        parentId: '',
        site: site,
        children: [
          LiveSubCategory(id: 'child', name: '射击', parentId: 'parent'),
        ],
      );
      final controller =
          CategoryDetailController(site: site, subCategory: root);

      expect(identical(controller.currentChildren, controller.currentChildren),
          isTrue);
      expect(
        identical(controller.currentChildren.single.focusNode,
            controller.currentChildren.single.focusNode),
        isTrue,
      );
      controller.onClose();
      // The root is also used by the parent category page.
      expect(() => root.focusNode.addListener(() {}), returnsNormally);
      root.focusNode.dispose();
    });

    test('ignores a room response after the controller closes', () async {
      final pendingRooms = Completer<LiveCategoryResult>();
      final liveSite = _FakeLiveSite()..pending['leaf:1'] = pendingRooms;
      final site = _fakeSite(liveSite);
      final controller = CategoryDetailController(
        site: site,
        subCategory: _tvCategory(site, id: 'leaf', name: '综合'),
      );

      final request = controller.loadData();
      controller.onClose();
      pendingRooms.complete(
        LiveCategoryResult(hasMore: true, items: [_room('stale-room')]),
      );
      await request;

      expect(controller.list, isEmpty);
      expect(controller.canLoadMore.value, isFalse);
    });
  });

  testWidgets(
      'remote select enters children and back restores focus and scroll', (
    tester,
  ) async {
    final liveSite = _FakeLiveSite()
      ..defaultResult = LiveCategoryResult(
        hasMore: false,
        items: [_room('room')],
      );
    final site = _fakeSite(liveSite);
    final root = _tvCategory(
      site,
      id: 'parent',
      name: '游戏',
      children: List.generate(
        80,
        (index) => LiveSubCategory(
          id: 'child-$index',
          name: '分区$index',
          parentId: 'parent',
          children: index == 32
              ? [
                  LiveSubCategory(
                    id: 'grandchild',
                    name: '三级分区',
                    parentId: 'child-32',
                  ),
                ]
              : const [],
        ),
      ),
    );
    final controller = CategoryDetailController(site: site, subCategory: root);
    Get.put<CategoryDetailController>(controller);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1920, 1080),
        builder: (context, child) => const GetMaterialApp(
          home: CategoryDetailPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.currentLevel.allFocusNode.hasFocus, isTrue);

    controller.scrollController.jumpTo(300);
    await tester.pump();
    final savedOffset = controller.scrollController.offset;
    final selectedChild = controller.currentChildren[32];
    selectedChild.focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(controller.currentSubCategory.id, 'child-32');
    expect(find.text('全部'), findsOneWidget);
    expect(controller.currentLevel.allFocusNode.hasFocus, isTrue);

    final childLevel = controller.currentLevel;
    final pendingAllRooms = Completer<LiveCategoryResult>();
    liveSite.pending['child-32:1'] = pendingAllRooms;
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(controller.isRoomView, isTrue);
    expect(find.text('分区32 · 全部'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    pendingAllRooms.complete(LiveCategoryResult(hasMore: false, items: []));
    await tester.pumpAndSettle();
    expect(controller.isCategorySelection, isTrue);
    expect(childLevel.allFocusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.currentSubCategory.id, 'parent');
    expect(selectedChild.focusNode.hasFocus, isTrue);
    expect(controller.scrollController.offset, closeTo(savedOffset, 1));

    // A rapid enter/back invalidates the queued focus restore for the removed
    // level before its owned focus node is disposed.
    unawaited(controller.openSubCategory(selectedChild));
    controller.handleBack();
    await tester.pumpAndSettle();
    expect(selectedChild.focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);

    Get.delete<CategoryDetailController>();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FakeLiveSite extends LiveSite {
  final Map<String, LiveCategoryResult> results = {};
  final Map<String, Completer<LiveCategoryResult>> pending = {};
  final List<String> requests = [];
  LiveCategoryResult defaultResult =
      LiveCategoryResult(hasMore: false, items: const []);

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) {
    final key = '${category.id}:$page';
    requests.add(key);
    return pending[key]?.future ?? Future.value(results[key] ?? defaultResult);
  }
}

Site _fakeSite(_FakeLiveSite liveSite) => Site(
      id: 'fake',
      name: '测试站点',
      logo: '',
      liveSite: liveSite,
      index: 0,
    );

LiveSubCategoryExt _tvCategory(
  Site site, {
  required String id,
  required String name,
  List<LiveSubCategory> children = const [],
}) =>
    LiveSubCategoryExt.fromLiveSubCategory(
      LiveSubCategory(
        id: id,
        name: name,
        parentId: 'parent',
        children: children,
      ),
      site,
    );

LiveRoomItem _room(String roomId) => LiveRoomItem(
      roomId: roomId,
      title: roomId,
      cover: '',
      userName: '主播',
    );
