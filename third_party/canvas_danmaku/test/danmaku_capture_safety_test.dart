import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_danmaku/danmaku_capture.dart';
import 'package:canvas_danmaku/danmaku_capture_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DanmakuCaptureSource source(String key, Future<Uint8List> Function() render,
        {VoidCallback? dispose}) =>
    DanmakuCaptureSource(
      visualKey: key,
      renderPng: render,
      x: 0,
      y: 0,
      width: 1,
      height: 1,
      dispose: dispose,
    );

Future<ui.Image> tinyImage() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint());
  final picture = recorder.endRecording();
  return picture.toImage(1, 1).whenComplete(picture.dispose);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('later PNG rejection is observed while an earlier sprite is pending',
      () async {
    final first = Completer<Uint8List>();
    final second = Completer<Uint8List>();
    final errors = <Object>[];
    var delivered = 0;
    final controller = DanmakuCaptureController(
      onFrame: (_) => delivered++,
      onError: (error, _) => errors.add(error),
    )..enabled = true;
    expect(
        controller.capture(
            rendererTickMilliseconds: 0,
            viewportSize: const Size(10, 10),
            sources: [
              source('pending', () => first.future),
              source('rejected', () => second.future),
            ]),
        isTrue);
    second.completeError(StateError('later PNG failed'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(errors, isEmpty,
        reason: 'ordered delivery is still awaiting the first PNG');
    first.complete(Uint8List(1));
    await controller.flush();
    expect(errors.single, isA<StateError>());
    expect(delivered, 0);
    expect(controller.enabled, isFalse);
    controller.dispose();
  });

  test('oversized frame fails before any PNG starts and releases every source',
      () async {
    var renders = 0;
    var disposed = 0;
    final errors = <Object>[];
    final controller = DanmakuCaptureController(
      onFrame: (_) => fail('oversized frame must not be delivered'),
      onError: (error, _) => errors.add(error),
    )..enabled = true;
    expect(
        controller.capture(
            rendererTickMilliseconds: 0,
            viewportSize: const Size(10, 10),
            sources: List.generate(
                501,
                (index) => source('$index', () async {
                      renders++;
                      return Uint8List(1);
                    }, dispose: () => disposed++))),
        isFalse);
    await controller.flush();
    expect(renders, 0);
    expect(disposed, 501);
    expect(errors, hasLength(1));
    expect(controller.enabled, isFalse);
    controller.dispose();
  });

  test('temporary source painters are released on cache hit and throttle',
      () async {
    var disposed = 0;
    var paints = 0;
    final controller = DanmakuCaptureController(onFrame: (_) {})
      ..enabled = true;
    DanmakuCaptureSource nextSource() => source('cached', () async {
          paints++;
          return Uint8List(1);
        }, dispose: () => disposed++);
    for (final tick in [0, 16, 17]) {
      controller.capture(
          rendererTickMilliseconds: tick,
          viewportSize: const Size(10, 10),
          sources: [nextSource()]);
      expect(
          disposed,
          tick == 0
              ? 1
              : tick == 16
                  ? 2
                  : 3);
    }
    await controller.flush();
    expect(paints, 1);
    controller.dispose();
  });

  test('invalid and oversized sprites never reach painting or native raster',
      () async {
    var paints = 0;
    for (final dimensions in [
      [0, 1],
      [1, -1],
      [4097, 4096],
      [1 << 40, 1]
    ]) {
      await expectLater(
          DanmakuCapturePainter.renderPngForTesting(
              dimensions[0], dimensions[1], (_) => paints++),
          throwsStateError);
    }
    expect(paints, 0);
  });

  test(
      'global raster pressure rejects excess work before painting and recovers',
      () async {
    final firstImage = Completer<ui.Image>();
    final secondImage = Completer<ui.Image>();
    var paints = 0;
    final first = DanmakuCapturePainter.renderPngForTesting(
        2048, 2048, (_) => paints++,
        rasterize: (_, __, ___) => firstImage.future);
    final second = DanmakuCapturePainter.renderPngForTesting(
        2048, 2048, (_) => paints++,
        rasterize: (_, __, ___) => secondImage.future);
    expect(paints, 2, reason: 'Picture recording must remain synchronous');
    await expectLater(
        DanmakuCapturePainter.renderPngForTesting(1, 1, (_) => paints++),
        throwsStateError);
    expect(paints, 2);
    firstImage.complete(await tinyImage());
    secondImage.complete(await tinyImage());
    await Future.wait([first, second]);
    expect(
        await DanmakuCapturePainter.renderPngForTesting(1, 1, (_) => paints++),
        isNotEmpty);
    expect(paints, 3);
  });

  test('failed native raster returns its entire memory reservation', () async {
    await expectLater(
        DanmakuCapturePainter.renderPngForTesting(8192, 1024, (_) {},
            rasterize: (_, __, ___) async {
          throw StateError('native raster failed');
        }),
        throwsStateError);
    expect(
        await DanmakuCapturePainter.renderPngForTesting(8192, 1024, (_) {},
            rasterize: (_, __, ___) => tinyImage()),
        isNotEmpty);
  });

  test('text snapshot is recorded before its temporary painter is disposed',
      () async {
    final painter = TextPainter(
      text: const TextSpan(text: 'capture', style: TextStyle(fontSize: 16)),
      textDirection: TextDirection.ltr,
    )..layout();
    final encoding = DanmakuCapturePainter.renderPngForTesting(
        painter.width.ceil() + 8,
        painter.height.ceil() + 8,
        (canvas) => painter.paint(canvas, const Offset(4, 4)));
    painter.dispose();
    expect(await encoding, isNotEmpty);
  });
}
