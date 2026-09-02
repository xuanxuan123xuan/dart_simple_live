import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_page.dart';

class _TestIndexedController extends IndexedController {
  // The production hook reads Hive and schedules route work; this isolated
  // layout fixture intentionally supplies inert pages instead.
  @override
  // ignore: must_call_super
  void onInit() {
    items.assignAll(Constant.allHomePages.values);
    pages.assignAll(
      List<Widget>.generate(
        items.length,
        (index) => Center(child: Text('page-$index')),
      ),
    );
  }
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<IndexedController>(_TestIndexedController());
  });

  tearDown(Get.reset);

  Future<void> pumpAtWidth(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 700));
    await tester.pumpWidget(
      const GetMaterialApp(
        home: IndexedPage(glassEnabled: false),
      ),
    );
    await tester.pump();
  }

  testWidgets('uses an inset bottom navigation on compact windows',
      (tester) async {
    await pumpAtWidth(tester, 390);

    expect(
        find.byKey(const ValueKey('root-bottom-navigation')), findsOneWidget);
    expect(find.byKey(const ValueKey('root-top-navigation')), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('root-bottom-navigation')))
          .width,
      366,
    );
    for (final item in Constant.allHomePages.values) {
      expect(find.text(item.title), findsOneWidget);
    }
  });

  testWidgets('keeps the bottom navigation centered and capped on wide windows',
      (tester) async {
    await pumpAtWidth(tester, 1200);

    expect(
      find.byKey(const ValueKey('root-bottom-navigation')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('root-top-navigation')), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('root-bottom-navigation')))
          .width,
      600,
    );
    final background = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('root-page-background')),
    );
    expect(background.color, Colors.white);
    expect(tester.getTopLeft(find.byType(IndexedStack)).dy, 0);
  });
}
