import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/utils.dart';

/// 横屏手机上底部弹窗的水平安全区处理。
///
/// 弹窗受 maxWidth 约束时两侧本来就有大片留白，不该再让开导航条 inset——
/// 否则内容被无谓地又缩一截，文字离弹窗边缘明显不贴。
void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets('narrow sheet on a landscape phone ignores the side nav inset',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    // 873x393 横屏手机，导航条在右侧占 48dp。
    tester.view.physicalSize = const Size(873, 393);
    tester.view.padding = const FakeViewPadding(right: 48);
    addTearDown(() {
      tester.view.resetPadding();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    unawaitedSheet(
      Utils.showBottomSheet(
        title: 'Sheet title',
        showHeader: false,
        child: const ListTile(
          title: Text('Item', key: ValueKey<String>('sheet-title')),
          trailing: Icon(
            Icons.chevron_right,
            key: ValueKey<String>('sheet-trailing'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 弹窗 maxWidth 600，横屏 873 → 两侧各留白 136.5dp，远超 48dp 导航条，
    // 所以内容盒就是弹窗本身：136.5 → 736.5。
    // trailing 保持 ListTile 默认 24dp gutter → 712.5。
    final trailing = find.byKey(const ValueKey<String>('sheet-trailing'));
    expect(tester.getTopRight(trailing).dx, closeTo(712.5, 0.01));
    final title = find.byKey(const ValueKey<String>('sheet-title'));
    expect(tester.getTopLeft(title).dx, closeTo(152.5, 0.01));

    Get.back<void>();
    await tester.pumpAndSettle();
  });

  testWidgets('a full-width sheet still clears the side nav inset',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    // 窄屏：弹窗铺满屏宽，必须让开导航条。
    tester.view.physicalSize = const Size(500, 900);
    tester.view.padding = const FakeViewPadding(right: 48);
    addTearDown(() {
      tester.view.resetPadding();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    unawaitedSheet(
      Utils.showBottomSheet(
        title: 'Sheet title',
        showHeader: false,
        child: const ListTile(
          trailing: Icon(
            Icons.chevron_right,
            key: ValueKey<String>('sheet-trailing'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 内容盒 0 → 452（让开 48dp），trailing 再留 24dp gutter → 428。
    final trailing = find.byKey(const ValueKey<String>('sheet-trailing'));
    expect(tester.getTopRight(trailing).dx, closeTo(428, 0.01));

    Get.back<void>();
    await tester.pumpAndSettle();
  });
}

void unawaitedSheet(Future<dynamic> future) {
  future.ignore();
}
