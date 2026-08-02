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

  testWidgets('tapping the route barrier dismisses the right-side panel',
      (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('Open panel'));
    await tester.pumpAndSettle();

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
