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

  testWidgets('right-side panel keeps its width with an Android right safe inset',
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
