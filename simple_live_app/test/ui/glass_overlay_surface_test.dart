import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';

void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(Get.reset);

  testWidgets('overlay glass keeps a translucent light readability layer',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppStyle.lightTheme,
        home: const GlassOverlaySurface(child: Text('content')),
      ),
    );

    final layer = tester.widget<Material>(
      find.byKey(GlassOverlaySurface.readabilityLayerKey),
    );
    expect(layer.color, isNotNull);
    expect((layer.color!.a * 255).round(), inInclusiveRange(180, 190));
  });

  testWidgets('overlay glass keeps a translucent dark readability layer',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppStyle.darkTheme,
        home: const GlassOverlaySurface(child: Text('content')),
      ),
    );

    final layer = tester.widget<Material>(
      find.byKey(GlassOverlaySurface.readabilityLayerKey),
    );
    expect(layer.color, isNotNull);
    expect((layer.color!.a * 255).round(), inInclusiveRange(194, 202));
  });

  testWidgets('safe dialogs use the readable overlay surface', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppStyle.lightTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Utils.showDialogSafe<void>(
              context: context,
              builder: (_) => const AlertDialog(content: Text('dialog body')),
            ),
            child: const Text('open dialog'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();

    expect(find.byType(GlassOverlaySurface), findsOneWidget);
    expect(
      find.byKey(GlassOverlaySurface.readabilityLayerKey),
      findsOneWidget,
    );
  });

  testWidgets('bottom drawers use the readable overlay surface',
      (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppStyle.lightTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Utils.showBottomSheet(
              title: 'drawer',
              child: const Text('drawer body'),
            ),
            child: const Text('open drawer'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open drawer'));
    await tester.pumpAndSettle();

    expect(find.byType(GlassOverlaySurface), findsOneWidget);
    expect(
      find.byKey(GlassOverlaySurface.readabilityLayerKey),
      findsOneWidget,
    );
  });
}
