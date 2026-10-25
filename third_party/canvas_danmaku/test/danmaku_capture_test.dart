import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:canvas_danmaku/special_danmaku_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('identical PNGs retain independent moving instance identities',
      () async {
    final frames = <DanmakuCaptureFrame>[];
    var rasterCount = 0;
    final controller = DanmakuCaptureController(onFrame: frames.add)
      ..enabled = true;
    DanmakuCaptureSource source(String id, double x) => DanmakuCaptureSource(
        visualKey: 'same-text',
        instanceId: id,
        x: x,
        y: 0,
        width: 20,
        height: 10,
        renderPng: () async {
          rasterCount++;
          return Uint8List.fromList([1, 2, 3]);
        });
    controller.capture(
        rendererTickMilliseconds: 0,
        viewportSize: const Size(100, 60),
        sources: [source('one', 80), source('two', 40)]);
    controller.capture(
        rendererTickMilliseconds: 16,
        viewportSize: const Size(100, 60),
        sources: [source('two', 38), source('one', 78)]);
    await controller.flush();
    expect(rasterCount, 1);
    expect(
        frames.first.placements.map((p) => p.spriteId).toSet(), hasLength(1));
    expect(frames.first.placements.map((p) => p.instanceId), ['one', 'two']);
    expect(frames.last.placements.map((p) => p.instanceId), ['two', 'one']);
    controller.dispose();
  });

  test('capture is opt-in and reuses a sprite across placement frames',
      () async {
    final frames = <DanmakuCaptureFrame>[];
    var playbackPosition = const Duration(seconds: 5);
    final controller = DanmakuCaptureController(
      onFrame: frames.add,
      mediaPosition: () => playbackPosition,
    );
    var rasterCount = 0;
    final source = DanmakuCaptureSource(
      visualKey: 'same-rendered-text',
      x: 10,
      y: 20,
      width: 48,
      height: 28,
      renderPng: () async {
        rasterCount++;
        return Uint8List.fromList([1, 2, 3]);
      },
    );

    expect(
      controller.capture(
        rendererTickMilliseconds: 0,
        viewportSize: const Size(100, 60),
        sources: [source],
      ),
      isFalse,
    );
    expect(frames, isEmpty);

    controller.enabled = true;
    expect(
      controller.capture(
        rendererTickMilliseconds: 0,
        viewportSize: const Size(100, 60),
        sources: [source],
      ),
      isTrue,
    );
    playbackPosition = const Duration(seconds: 6);
    expect(
      controller.capture(
        rendererTickMilliseconds: 15,
        viewportSize: const Size(100, 60),
        sources: [source],
      ),
      isFalse,
      reason: 'the default cadence is at most one snapshot per 16ms',
    );
    expect(
      controller.capture(
        rendererTickMilliseconds: 16,
        viewportSize: const Size(100, 60),
        sources: [source],
      ),
      isTrue,
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(frames, hasLength(2));
    expect(frames.first.sprites, hasLength(1));
    expect(frames.last.sprites, isEmpty);
    expect(frames.first.mediaPosition, const Duration(seconds: 5));
    expect(frames.last.mediaPosition, const Duration(seconds: 6));
    expect(
      frames.last.placements.single.spriteId,
      frames.first.placements.single.spriteId,
    );
    expect(rasterCount, 1);

    controller.enabled = false;
    await controller.reset();
    controller.enabled = true;
    expect(
      controller.capture(
        rendererTickMilliseconds: 0,
        viewportSize: const Size(100, 60),
        sources: [source],
      ),
      isTrue,
    );
    await controller.flush();
    expect(frames, hasLength(3));
    expect(frames.last.sprites, hasLength(1));
    expect(rasterCount, 1, reason: 'reset reuses cached PNG bytes');
    controller.dispose();
  });

  test('slow frame delivery is bounded and reports overflow', () async {
    final release = Completer<void>();
    final errors = <Object>[];
    var delivered = 0;
    final controller = DanmakuCaptureController(
      maxQueuedFrames: 1,
      onFrame: (_) async {
        await release.future;
        delivered++;
      },
      onError: (error, _) => errors.add(error),
    )..enabled = true;
    final source = DanmakuCaptureSource(
      visualKey: 'bounded',
      x: 0,
      y: 0,
      width: 1,
      height: 1,
      renderPng: () async => Uint8List(0),
    );

    expect(
      controller.capture(
        rendererTickMilliseconds: 0,
        viewportSize: const Size(10, 10),
        sources: [source],
      ),
      isTrue,
    );
    expect(
      controller.capture(
        rendererTickMilliseconds: 16,
        viewportSize: const Size(10, 10),
        sources: [source],
      ),
      isFalse,
    );
    expect(controller.enabled, isFalse);
    expect(errors, hasLength(1));

    release.complete();
    await controller.flush();
    expect(delivered, 1);
    controller.dispose();
  });

  test('special placement preserves its animation state for replay', () {
    final transform = Matrix4.identity()..rotateZ(0.4);
    final item = SpecialDanmakuContentItem(
      'special',
      duration: 1000,
      color: Colors.white,
      fontSize: 20,
      alphaTween: Tween<double>(begin: 0.2, end: 0.8),
      translateXTween: Tween<double>(begin: 0.1, end: 0.5),
      translateYTween: ConstantTween<double>(0.25),
      translationDuration: 1000,
      matrix: transform,
    );

    final placement = SpecialDanmakuPainter.placementFor(
      item,
      const Size(1000, 400),
      500,
    );

    expect(placement, isNotNull);
    expect(placement!.offset.dx, closeTo(300, 0.001));
    expect(placement.offset.dy, closeTo(100, 0.001));
    expect(placement.opacity, closeTo(0.5, 0.001));
    expect(placement.transform, transform.storage);
  });

  testWidgets('enabling capture snapshots already-visible danmaku', (
    tester,
  ) async {
    DanmakuController? danmakuController;
    final captured = Completer<DanmakuCaptureFrame>();
    DanmakuCaptureFrame? frameValue;
    final captureController = DanmakuCaptureController(
      onFrame: (frame) {
        frameValue = frame;
        if (!captured.isCompleted) captured.complete(frame);
      },
    );
    addTearDown(captureController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 100,
          child: DanmakuScreen(
            createdController: (controller) => danmakuController = controller,
            option: DanmakuOption(),
            captureController: captureController,
          ),
        ),
      ),
    );
    await tester.pump();
    danmakuController!.addDanmaku(
      DanmakuContentItem('already visible', type: DanmakuItemType.top),
    );
    await tester.pump();
    expect(captured.isCompleted, isFalse);

    captureController.enabled = true;
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(captured.isCompleted, isTrue);
    final frame = frameValue;

    expect(frame, isNotNull);
    expect(frame!.placements, hasLength(1));
    expect(frame.sprites, hasLength(1));
    expect(frame.sprites.single.pngBytes, isNotEmpty);
    expect(frame.viewportSize, const Size(800, 600));
    danmakuController!.clear();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('replay applies opacity to the whole overlapping stack', () async {
    final spriteRecorder = ui.PictureRecorder();
    final spriteCanvas = Canvas(spriteRecorder);
    spriteCanvas.drawColor(Colors.red, BlendMode.src);
    final spritePicture = spriteRecorder.endRecording();
    final sprite = await spritePicture.toImage(2, 2);
    spritePicture.dispose();

    final frame = DanmakuCaptureFrame(
      rendererTickMilliseconds: 16,
      capturedAt: DateTime.utc(2026),
      viewportSize: const Size(2, 2),
      opacity: 0.5,
      placements: const [
        DanmakuCapturePlacement(
          spriteId: 'red',
          x: 0,
          y: 0,
          width: 2,
          height: 2,
          opacity: 1,
        ),
        DanmakuCapturePlacement(
          spriteId: 'red',
          x: 0,
          y: 0,
          width: 2,
          height: 2,
          opacity: 1,
        ),
      ],
      sprites: const [],
    );
    final recorder = ui.PictureRecorder();
    DanmakuCaptureReplay.paintFrame(Canvas(recorder), frame, {'red': sprite});
    final picture = recorder.endRecording();
    final result = await picture.toImage(2, 2);
    picture.dispose();
    final pixels = await result.toByteData(format: ui.ImageByteFormat.rawRgba);

    expect(pixels, isNotNull);
    expect(pixels!.getUint8(3), inInclusiveRange(126, 129));
    result.dispose();
    sprite.dispose();
  });
}
