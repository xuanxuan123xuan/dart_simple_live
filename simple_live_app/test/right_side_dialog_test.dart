import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/utils.dart';

void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(() {
    Utils.hideRightDialog();
    Utils.debugResetRightDialog();
    Get.reset();
  });

  testWidgets('right-side panel survives its originating tap and stays open',
      (tester) async {
    await tester.pumpWidget(_testApp());

    await tester.tap(find.text('Open panel'));
    await tester.pumpAndSettle();
    expect(find.text('Panel body'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Panel body'), findsOneWidget);

    Utils.hideRightDialog();
    await tester.pumpAndSettle();
  });

  testWidgets('a child-owned header can replace the route header',
      (tester) async {
    await tester.pumpWidget(_testApp());

    Utils.showRightDialog(
      title: 'Hidden route title',
      showHeader: false,
      child: const Center(child: Text('Child-owned header')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hidden route title'), findsNothing);
    expect(find.text('Child-owned header'), findsOneWidget);
  });

  testWidgets(
      'right-side panel keeps its width with an Android right safe inset',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 400);
    tester.view.padding = const FakeViewPadding(right: 48);
    addTearDown(() {
      tester.view.resetPadding();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('Open panel'));
    await tester.pumpAndSettle();

    final panel = find.byKey(
      const ValueKey<String>('right-side-dialog-panel'),
    );
    expect(tester.getSize(panel).width, 320);
    expect(tester.getTopRight(panel), const Offset(800, 0));
  });

  group('rightDialogPanelWidth', () {
    double widthFor(double requested, Size screen) =>
        Utils.rightDialogPanelWidth(
          requestedWidth: requested,
          screenSize: screen,
        );

    test('横屏手机收敛到 2/5 屏宽', () {
      // 典型 1080p 手机横屏（873x393）：420 会占到 48% 屏幕。
      expect(widthFor(420, const Size(873, 393)), closeTo(349.2, 0.01));
      expect(widthFor(400, const Size(873, 393)), closeTo(349.2, 0.01));
    });

    test('窄横屏不低于可读下限', () {
      // 2/5 只有 256dp，列表项文字会挤，兜到 280dp。
      expect(widthFor(420, const Size(640, 360)), 280);
    });

    test('2/5 不会超过调用方要求的宽度', () {
      // 设置面板只要 320dp，屏幕再宽也不该被撑大。
      expect(widthFor(320, const Size(1000, 450)), 320);
    });

    test('平板与桌面保持调用方宽度', () {
      expect(widthFor(420, const Size(1280, 800)), 420);
      expect(widthFor(420, const Size(1920, 1080)), 420);
    });

    test('竖屏只做兜底约束', () {
      expect(widthFor(320, const Size(400, 800)), 320);
      // 窄机型上不超过 90% 屏宽。
      expect(widthFor(420, const Size(393, 873)), closeTo(353.7, 0.01));
    });
  });

  testWidgets('landscape phone panel takes about 2/5 of the screen',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(873, 393);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_testApp());
    Utils.showRightDialog(
      title: '快捷入口',
      width: 420,
      child: const Center(child: Text('Panel body')),
    );
    await tester.pumpAndSettle();

    final panel = find.byKey(
      const ValueKey<String>('right-side-dialog-panel'),
    );
    expect(tester.getSize(panel).width, closeTo(349.2, 0.01));
    expect(tester.getTopRight(panel).dx, closeTo(873, 0.01));
  });

  testWidgets('panel content is inset by the safe area exactly once',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 400);
    tester.view.padding = const FakeViewPadding(right: 48);
    addTearDown(() {
      tester.view.resetPadding();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_testApp());
    Utils.showRightDialog(
      title: 'Panel title',
      showHeader: false,
      child: const ListTile(
        title: Text('Item', key: ValueKey<String>('panel-title')),
        trailing: Icon(
          Icons.chevron_right,
          key: ValueKey<String>('panel-trailing'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ListTile 内部还有一层 SafeArea(minimum: contentPadding)，会再读一次
    // MediaQuery.padding。路由补 inset 后必须把水平 padding 摘掉，否则 48dp
    // 导航条会被算两次，文字离右缘多出一大段死区。
    //
    // 面板 480→800，让开 48dp 安全区后内容盒 480→752；
    // trailing 相对内容盒右缘保持 ListTile 默认的 24dp gutter → 728。
    final trailing = find.byKey(const ValueKey<String>('panel-trailing'));
    expect(tester.getTopRight(trailing).dx, closeTo(728, 0.01));
    // 左缘在屏幕内部，不该被右侧 inset 影响：仍是 16dp gutter。
    final title = find.byKey(const ValueKey<String>('panel-title'));
    expect(tester.getTopLeft(title).dx, closeTo(496, 0.01));
  });

  testWidgets('tapping the route barrier dismisses the right-side panel',
      (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('Open panel'));
    await tester.pumpAndSettle();

    // barrier 打开后 1000ms 内禁用（拦截触摸穿透），pump 越过窗口再点遮罩。
    await tester.pump(const Duration(milliseconds: 1050));
    await tester.pump();
    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();

    expect(find.text('Panel body'), findsNothing);
    expect(find.text('Open panel'), findsOneWidget);
  });

  testWidgets('explicit cleanup removes the panel before another page is used',
      (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('Open panel'));
    await tester.pumpAndSettle();
    expect(find.text('Panel body'), findsOneWidget);

    Utils.hideRightDialog();
    await tester.pumpAndSettle();
    expect(find.text('Panel body'), findsNothing);

    await tester.tap(find.text('Open normal dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Normal dialog body'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Normal dialog body'), findsOneWidget);

    Get.back<void>();
    await tester.pumpAndSettle();
  });

  testWidgets('a covered panel does not reappear after returning from a page',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_testApp(navigatorKey: navigatorKey));
    await tester.tap(find.text('Open panel'));
    await tester.pumpAndSettle();
    expect(find.text('Panel body'), findsOneWidget);

    // 页面导航在弹窗打开后（pumpAndSettle 已完成入场动画）应关闭弹窗。
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Next page')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Next page'), findsOneWidget);

    navigatorKey.currentState!.pop<void>();
    await tester.pumpAndSettle();
    expect(find.text('Open panel'), findsOneWidget);
    expect(find.text('Panel body'), findsNothing);
  });

  testWidgets('a transient popup route does not dismiss the right-side panel',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_testApp(navigatorKey: navigatorKey));
    await tester.tap(find.text('Open panel'));
    await tester.pumpAndSettle();
    expect(find.text('Panel body'), findsOneWidget);

    // 模拟 SmartDialog toast / Get.bottomSheet 等浮层 route
    navigatorKey.currentState!.push<void>(_FakeTransientPopupRoute());
    await tester.pumpAndSettle();
    expect(find.text('Panel body'), findsOneWidget);
  });
}

/// 模拟 SmartDialog toast / bottom sheet 等非页面浮层。
class _FakeTransientPopupRoute extends PopupRoute<void> {
  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 50);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return const Align(
      alignment: Alignment.bottomCenter,
      child: Text('toast'),
    );
  }
}

Widget _testApp({GlobalKey<NavigatorState>? navigatorKey}) {
  return GetMaterialApp(
    navigatorKey: navigatorKey,
    home: Scaffold(
      body: Builder(
        builder: (context) => Column(
          children: [
            TextButton(
              onPressed: () {
                Utils.showRightDialog(
                  title: 'Panel title',
                  child: const Center(child: Text('Panel body')),
                );
              },
              child: const Text('Open panel'),
            ),
            TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(
                    content: Text('Normal dialog body'),
                  ),
                );
              },
              child: const Text('Open normal dialog'),
            ),
          ],
        ),
      ),
    ),
  );
}
