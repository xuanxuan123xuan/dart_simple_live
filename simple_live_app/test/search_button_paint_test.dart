import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:simple_live_app/app/app_glass_mode.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/glass_controller.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';

class _TestSettingsController extends AppSettingsController {
  @override
  // Keep the fixture independent from Hive-backed app startup.
  // ignore: must_call_super
  void onInit() {}
}

enum _Surface { legacy, circular, reference, background }

int _rgbDifference(Uint8List a, Uint8List b, double dpr, Rect region) {
  final width = (120 * dpr).round();
  var difference = 0;
  for (var y = (region.top * dpr).round();
      y < (region.bottom * dpr).round();
      y++) {
    for (var x = (region.left * dpr).round();
        x < (region.right * dpr).round();
        x++) {
      for (var channel = 0; channel < 3; channel++) {
        final i = (y * width + x) * 4 + channel;
        difference += (a[i] - b[i]).abs();
      }
    }
  }
  return difference;
}

void main() {
  // Platform overrides exercise Flutter branches in the test renderer, not
  // native compositors. Spread DPR coverage across a compact six-case matrix.
  for (final (platform, dpr) in [
    (TargetPlatform.windows, 1.0),
    (TargetPlatform.iOS, 2.0),
    (TargetPlatform.android, 3.0),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('search circle paint ${platform.name} dark=$dark DPR=$dpr',
          (tester) async {
        Get.testMode = true;
        Get.put<AppSettingsController>(_TestSettingsController())
            .glassMode
            .value = AppGlassMode.standard;
        final previousShadowsDisabled = painting.debugDisableShadows;
        final previousPlatform = debugDefaultTargetPlatformOverride;
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = Size(120 * dpr, 120 * dpr);
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          Get.reset();
        });
        painting.debugDisableShadows = false;
        debugDefaultTargetPlatformOverride = platform;
        try {
          await tester.runAsync(() async {
            final loader = FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
            await loader.load();
          });
          final key = GlobalKey();
          final theme = dark ? AppStyle.darkTheme : AppStyle.lightTheme;
          Future<Uint8List> capture(_Surface surface, double shift,
              {String? filename}) async {
            await tester.pumpWidget(MaterialApp(
              theme: theme,
              home: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox.square(
                    dimension: 120,
                    child: Stack(children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: dark
                                  ? const [Color(0xff333c51), Color(0xff080c15)]
                                  : const [
                                      Color(0xffeceef2),
                                      Color(0xffccd3df)
                                    ],
                              // Moving the gradient models content scrolling
                              // behind a stationary, live-backdrop control.
                              begin: Alignment(-1, -1 + shift / 60),
                              end: Alignment(1, 1 + shift / 60),
                            ),
                          ),
                        ),
                      ),
                      if (surface != _Surface.background)
                        Center(
                          child: SizedBox.square(
                            dimension: 56,
                            child: Builder(builder: (context) {
                              final icon = IconButton(
                                  onPressed: () {},
                                  icon: const Icon(Icons.search));
                              if (surface == _Surface.reference) {
                                // Independent circle primitive checks actual
                                // painted pixels, including the outer shadow.
                                return GlassContainer(
                                  useOwnLayer: true,
                                  quality: AppGlassController.qualityOf(context,
                                      role: GlassSurfaceRole.navigation),
                                  settings: LiquidGlassSettings(
                                    glassColor: Theme.of(context)
                                        .colorScheme
                                        .surface
                                        .withAlpha(
                                            AppGlassAppearancePolicy.resolve(
                                                    AppGlassMode.standard)
                                                .surfaceTintAlpha),
                                    lightIntensity: 0,
                                    glowIntensity: 0,
                                    fresnelStrength: 0,
                                    ambientRim: 0,
                                  ),
                                  shape: const LiquidOval(),
                                  platformViewBackdrop: true,
                                  clipBehavior: Clip.antiAlias,
                                  child: icon,
                                );
                              }
                              return GlassSurface(
                                role: GlassSurfaceRole.navigation,
                                radius: 28,
                                liveBackdrop: true,
                                showEdgeHighlight: false,
                                circular: surface == _Surface.circular,
                                child: icon,
                              );
                            }),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ));
            await tester.pumpAndSettle();
            final boundary = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            return (await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: dpr);
              try {
                if (const bool.fromEnvironment(
                    'SEARCH_BUTTON_WRITE_SCREENSHOTS')) {
                  final label = filename ??
                      '${surface.name}_${platform.name}_${dark ? 'dark' : 'light'}_${dpr}_shift_$shift';
                  final png =
                      await image.toByteData(format: ui.ImageByteFormat.png);
                  final file = File('build/search_button_paint/$label.png');
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(png!.buffer.asUint8List());
                }
                final bytes =
                    await image.toByteData(format: ui.ImageByteFormat.rawRgba);
                return Uint8List.fromList(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            }))!;
          }

          final export = platform == TargetPlatform.iOS && !dark;
          final before = await capture(_Surface.legacy, 0,
              filename: export ? 'before_light_2' : null);
          final after = await capture(_Surface.circular, 0,
              filename: export ? 'after_light_2' : null);
          final reference = await capture(_Surface.reference, 0,
              filename: export ? 'reference_light_2' : null);
          expect(listEquals(after, reference), isTrue,
              reason:
                  'The complete painted surface must match a true circular reference.');
          if (export) {
            expect(listEquals(after, before), isFalse,
                reason:
                    'The old superellipse must fail the circular pixel reference.');
            expect(
              _rgbDifference(
                  after, before, dpr, const Rect.fromLTRB(40, 84, 80, 90)),
              greaterThan(0),
              reason:
                  'The legacy bottom rim must differ from the circular reference.',
            );
          }
          if (!dark) {
            final background = await capture(_Surface.background, 0);
            // Sample below y=88, outside the control, to catch shadow clipping.
            expect(
              _rgbDifference(
                  after, background, dpr, const Rect.fromLTRB(44, 89, 76, 96)),
              greaterThan(0),
              reason: 'Keep the soft outer shadow.',
            );
          }
          final moved = await capture(_Surface.circular, 24);
          final movedReference = await capture(_Surface.reference, 24);
          expect(listEquals(moved, movedReference), isTrue);
          // Sample only inside the glass, left of the search glyph. Changing
          // background pixels outside the control cannot satisfy this check.
          expect(
            _rgbDifference(
                moved, after, dpr, const Rect.fromLTRB(40, 50, 46, 70)),
            greaterThan(0),
            reason: 'The glass interior must follow its moving live backdrop.',
          );
        } finally {
          // Flutter checks these globals before addTearDown callbacks run.
          painting.debugDisableShadows = previousShadowsDisabled;
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      });
    }
  }
}
