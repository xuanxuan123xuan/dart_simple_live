import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:simple_live_app/app/app_glass_mode.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';

class _TestSettingsController extends AppSettingsController {
  @override
  // Keep these tests independent from Hive-backed app startup.
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  late AppSettingsController settings;

  setUp(() {
    Get.testMode = true;
    settings = Get.put<AppSettingsController>(_TestSettingsController());
  });

  tearDown(Get.reset);

  Future<LiquidGlassSettings> pumpSettings(
    WidgetTester tester, {
    required bool showEdgeHighlight,
  }) async {
    settings.glassMode.value = AppGlassMode.standard;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppStyle.lightTheme,
        home: GlassSurface(
          showEdgeHighlight: showEdgeHighlight,
          child: const SizedBox.square(dimension: 56),
        ),
      ),
    );
    await tester.pump();

    return tester.widget<GlassContainer>(find.byType(GlassContainer)).settings!;
  }

  testWidgets('glass surface keeps the default edge highlight settings',
      (tester) async {
    final glassSettings = await pumpSettings(
      tester,
      showEdgeHighlight: true,
    );

    expect(glassSettings.lightIntensity, 0.5);
    expect(glassSettings.glowIntensity, 0.75);
    expect(glassSettings.fresnelStrength, 1.0);
    expect(glassSettings.ambientRim, 0);
  });

  testWidgets('glass surface can disable edge highlights', (tester) async {
    final glassSettings = await pumpSettings(
      tester,
      showEdgeHighlight: false,
    );

    expect(glassSettings.lightIntensity, 0);
    expect(glassSettings.glowIntensity, 0);
    expect(glassSettings.fresnelStrength, 0);
    expect(glassSettings.ambientRim, 0);
  });

  testWidgets('fallback border remains available when glass is off',
      (tester) async {
    settings.glassMode.value = AppGlassMode.off;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppStyle.lightTheme,
        home: const GlassSurface(
          fallbackBorder: true,
          child: SizedBox.square(dimension: 56),
        ),
      ),
    );
    await tester.pump();

    final material = tester.widget<Material>(find.byType(Material).first);
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.side.style, BorderStyle.solid);
  });
}
