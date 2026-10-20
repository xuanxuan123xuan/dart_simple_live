import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/recording/recording_backend.dart';
import 'package:simple_live_app/services/recording/recording_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final backend = FFmpegRecordingBackend();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('recording-replay-');
    await Directory('${root.path}/sprites').create();
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2),
        ui.Paint()..color = const ui.Color(0xFFFF0000));
    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 2);
    picture.dispose();
    try {
      await File('${root.path}/sprites/red.png').writeAsBytes(
          (await image.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List());
    } finally {
      image.dispose();
    }
  });
  tearDown(() => root.delete(recursive: true));

  Future<Uint8List> pixels(RecordingOverlayFrame frame) async {
    final png = await backend.renderOverlayPreview(frame,
        width: 4, height: 4, directory: root.path);
    final codec = await ui.instantiateImageCodec(png);
    try {
      final image = (await codec.getNextFrame()).image;
      try {
        return (await image.toByteData(
                format: ui.ImageByteFormat.rawStraightRgba))!
            .buffer
            .asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  test(
      'overlapping sprites receive group opacity once, preserving transparent background',
      () async {
    final rgba = await pixels(const RecordingOverlayFrame(
        position: Duration.zero,
        canvasWidth: 4,
        canvasHeight: 4,
        opacity: .5,
        items: [
          RecordingOverlayItem(
              spriteId: 'red', x: 1, y: 1, width: 2, height: 2),
          RecordingOverlayItem(
              spriteId: 'red', x: 1, y: 1, width: 2, height: 2),
        ]));
    expect(rgba.sublist(0, 4), [0, 0, 0, 0]);
    const middle = (1 * 4 + 1) * 4;
    expect(rgba[middle], 255);
    expect(rgba[middle + 1], 0);
    expect(rgba[middle + 2], 0);
    expect(rgba[middle + 3], closeTo(128, 1));
  });

  test('recorded viewport scales to source resolution and clips outside pixels',
      () async {
    final rgba = await pixels(const RecordingOverlayFrame(
        position: Duration.zero,
        canvasWidth: 2,
        canvasHeight: 2,
        items: [
          RecordingOverlayItem(spriteId: 'red', x: 1, y: 1, width: 2, height: 2)
        ]));
    expect(rgba[(1 * 4 + 1) * 4 + 3], 0);
    expect(rgba[(2 * 4 + 2) * 4 + 3], 255);
    expect(rgba[(3 * 4 + 3) * 4 + 3], 255);
  });

  test('special danmaku transform translates sprite before composition',
      () async {
    final rgba = await pixels(const RecordingOverlayFrame(
      position: Duration.zero,
      canvasWidth: 4,
      canvasHeight: 4,
      items: [
        RecordingOverlayItem(
            spriteId: 'red',
            x: 0,
            y: 0,
            width: 1,
            height: 1,
            transform: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 2, 1, 0, 1])
      ],
    ));
    expect(rgba[3], 0);
    expect(rgba[(1 * 4 + 2) * 4 + 3], 255);
  });

  test('letterbox and danmaku inset map through the displayed video rectangle',
      () async {
    final rgba = await pixels(const RecordingOverlayFrame(
      position: Duration.zero,
      canvasWidth: 8,
      canvasHeight: 6,
      videoLeft: 2,
      videoTop: 1,
      videoWidth: 4,
      videoHeight: 4,
      items: [
        RecordingOverlayItem(spriteId: 'red', x: 2, y: 1, width: 1, height: 1)
      ],
    ));
    expect(rgba[3], 255);
    expect(rgba[(1 * 4 + 1) * 4 + 3], 0);
  });

  test('cover exports transparent source edges outside the visible viewport',
      () async {
    final rgba = await pixels(const RecordingOverlayFrame(
      position: Duration.zero,
      canvasWidth: 2,
      canvasHeight: 4,
      videoLeft: -1,
      videoWidth: 4,
      videoHeight: 4,
      items: [
        RecordingOverlayItem(spriteId: 'red', x: -1, y: 0, width: 4, height: 4)
      ],
    ));
    expect(rgba[3], 0);
    expect(rgba[1 * 4 + 3], 255);
    expect(rgba[2 * 4 + 3], 255);
    expect(rgba[3 * 4 + 3], 0);
  });

  test('transform scales around the item origin rather than viewport origin',
      () async {
    final rgba = await pixels(const RecordingOverlayFrame(
      position: Duration.zero,
      canvasWidth: 4,
      canvasHeight: 4,
      items: [
        RecordingOverlayItem(
            spriteId: 'red',
            x: 1,
            y: 1,
            width: 1,
            height: 1,
            transform: [2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
      ],
    ));
    expect(rgba[(1 * 4 + 1) * 4 + 3], 255);
    expect(rgba[(2 * 4 + 2) * 4 + 3], 255);
    expect(rgba[(3 * 4 + 3) * 4 + 3], 0);
  });
}
