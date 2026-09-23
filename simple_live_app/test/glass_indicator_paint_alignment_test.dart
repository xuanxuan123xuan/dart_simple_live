import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:liquid_glass_widgets/widgets/shared/glass_effect.dart';
import 'package:liquid_glass_widgets/src/renderer/liquid_glass.dart';
import 'package:liquid_glass_widgets/src/renderer/liquid_glass_blend_group.dart';
import 'package:liquid_glass_widgets/src/renderer/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_widgets/src/renderer/rendering/liquid_glass_render_object.dart';

void main() {
  for (final premium in [false, true]) {
  for (final translation in [0.0, 100.0, 220.0]) {
    for (final scale in [1.0, 1.08]) {
      testWidgets('glass premium=$premium pixels follow translation $translation and scale $scale',
          (tester) async {
        final captureKey = GlobalKey();
        final glassKey = GlobalKey();
        await tester.runAsync(GlassEffect.preWarm);
        final renderLink = GeometryRenderLink();
        final groupLink = GlassGroupLink();
        ui.FragmentShader? renderShader;
        ui.FragmentShader? geometryShader;
        ui.Image? capture;
        if (premium) {
          await tester.runAsync(() async {
            const prefix = 'packages/liquid_glass_widgets/shaders/';
            renderShader = (await ui.FragmentProgram.fromAsset(
                    '${prefix}liquid_glass_final_render.frag'))
                .fragmentShader();
            geometryShader = (await ui.FragmentProgram.fromAsset(
                    '${prefix}liquid_glass_geometry_blended.frag'))
                .fragmentShader();
            final recorder = ui.PictureRecorder();
            Canvas(recorder).drawColor(const Color(0xFF4488FF), BlendMode.src);
            final picture = recorder.endRecording();
            capture = picture.toImageSync(800, 600);
            picture.dispose();
          });
        }
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          renderLink.dispose();
          groupLink.dispose();
          renderShader?.dispose();
          geometryShader?.dispose();
          capture?.dispose();
        });
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: captureKey,
                child: SizedBox(
                  width: 400,
                  height: 160,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 24,
                        top: 48,
                        width: 80,
                        height: 48,
                        child: Transform.translate(
                          offset: Offset(translation, 0),
                          child: Transform.scale(
                            scale: scale,
                            child: premium
                                ? RepaintBoundary(
                                    key: glassKey,
                                    child: _CaptureLayer(
                                      link: renderLink,
                                      shader: renderShader!,
                                      capture: capture!,
                                      child: _CaptureGeometry(
                                        link: renderLink,
                                        group: groupLink,
                                        shader: geometryShader!,
                                        child: _CaptureShape(group: groupLink),
                                      ),
                                    ),
                                  )
                                : GlassEffect(
                              key: glassKey,
                              shape: const LiquidRoundedRectangle(
                                borderRadius: 20,
                              ),
                              settings: const LiquidGlassSettings(
                                glassColor: Color(0xFF4488FF),
                                blur: 0,
                              ),
                              quality: GlassQuality.standard,
                              interactionIntensity: 1,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final boundary = captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final glass = glassKey.currentContext!.findRenderObject()! as RenderBox;
        final expected = MatrixUtils.transformRect(
          glass.getTransformTo(boundary),
          Offset.zero & glass.size,
        );
        final bounds = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            if (const bool.fromEnvironment('GLASS_WRITE_SCREENSHOTS')) {
              final png = await image.toByteData(format: ui.ImageByteFormat.png);
              final file = File(
                'build/glass_alignment/premium_${premium}_translation_${translation}_scale_$scale.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(png!.buffer.asUint8List());
            }
            final data = await image.toByteData();
            var left = image.width;
            var top = image.height;
            var right = -1;
            var bottom = -1;
            for (var y = 0; y < image.height; y++) {
              for (var x = 0; x < image.width; x++) {
                if (data!.getUint8((y * image.width + x) * 4 + 3) < 16) {
                  continue;
                }
                if (x < left) left = x;
                if (x > right) right = x;
                if (y < top) top = y;
                if (y > bottom) bottom = y;
              }
            }
            expect(right, greaterThanOrEqualTo(left),
                reason: 'The real indicator shader must paint visible pixels.');
            return Rect.fromLTRB(left / 2, top / 2, (right + 1) / 2,
                (bottom + 1) / 2);
          } finally {
            image.dispose();
          }
        });
        expect(bounds!.center.dx, closeTo(expected.center.dx, 0.5));
        expect(bounds.center.dy, closeTo(expected.center.dy, 0.5));
        expect(bounds.width, closeTo(expected.width, 2));
        expect(bounds.height, closeTo(expected.height, 2));
      });
    }
  }
  }
}

// Mount the production capture renderer directly: widget tests use Skia, so
// LiquidGlass.withOwnLayer would otherwise skip the iOS rendering path.
const _captureSettings = LiquidGlassSettings(
  glassColor: Color(0x664488FF),
  thickness: 34,
  blur: 0,
);

class _CaptureLayer extends SingleChildRenderObjectWidget {
  const _CaptureLayer({
    required this.link,
    required this.shader,
    required this.capture,
    required super.child,
  });

  final GeometryRenderLink link;
  final ui.FragmentShader shader;
  final ui.Image capture;

  @override
  RenderLiquidGlassLayer createRenderObject(BuildContext context) =>
      RenderLiquidGlassLayer(
        renderShader: shader,
        devicePixelRatio: 1,
        settings: _captureSettings,
        shadows: const [],
        link: link,
        captureImage: capture,
      );
}

class _CaptureGeometry extends SingleChildRenderObjectWidget {
  const _CaptureGeometry({
    required this.link,
    required this.group,
    required this.shader,
    required super.child,
  });

  final GeometryRenderLink link;
  final GlassGroupLink group;
  final ui.FragmentShader shader;

  @override
  RenderLiquidGlassBlendGroup createRenderObject(BuildContext context) =>
      RenderLiquidGlassBlendGroup(
        renderLink: link,
        devicePixelRatio: 1,
        geometryShader: shader,
        settings: _captureSettings,
        link: group,
        blend: 0,
      );
}

class _CaptureShape extends SingleChildRenderObjectWidget {
  const _CaptureShape({required this.group})
      : super(child: const SizedBox.expand());

  final GlassGroupLink group;

  @override
  RenderLiquidGlass createRenderObject(BuildContext context) => RenderLiquidGlass(
        shape: const LiquidRoundedRectangle(borderRadius: 20),
        glassContainsChild: false,
        blendGroupLink: group,
      );
}
