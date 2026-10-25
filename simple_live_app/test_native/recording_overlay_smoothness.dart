// Native cadence regression and optional offline re-export of existing material.
// SIMPLE_LIVE_RECORDING_RECOMPOSE_SOURCE: existing session directory (read only).
// SIMPLE_LIVE_RECORDING_SMOOTHNESS_DIR: output root; defaults inside this project.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:simple_live_app/services/recording/recording_backend.dart';
import 'package:simple_live_app/services/recording/recording_models.dart';
import 'package:simple_live_app/services/recording/recording_overlay_interpolation.dart';

Future<void> ffmpeg(List<String> args) async {
  final session = await FFmpegKit.executeWithArguments(args);
  if (!ReturnCode.isSuccess(await session.getReturnCode())) {
    throw StateError(
        'Native video operation failed: ${await session.getOutput()}');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
      home: Scaffold(body: Text('Overlay cadence verification'))));
  final root = Directory(p.join(
          Platform.environment['SIMPLE_LIVE_RECORDING_SMOOTHNESS_DIR'] ??
              p.join(Directory.current.path, '.tmp',
                  'recording-overlay-smoothness'),
          'run-${DateTime.now().microsecondsSinceEpoch}'))
      .absolute;
  await root.create(recursive: true);
  final result = <String, dynamic>{'root': root.path};
  final backend = FFmpegRecordingBackend();
  Future<void> save() => File(p.join(root.path, 'result.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(result),
      flush: true);
  try {
    result['synthetic'] = await synthetic(root, backend);
    await save();
    final existing =
        Platform.environment['SIMPLE_LIVE_RECORDING_RECOMPOSE_SOURCE'];
    if (existing != null) {
      final copied = Directory(p.join(root.path, 'materials'));
      await Directory(p.join(copied.path, 'sprites')).create(recursive: true);
      for (final name in ['raw.mkv', 'frames.jsonl', 'session.json']) {
        await File(p.join(existing, name)).copy(p.join(copied.path, name));
      }
      await for (final sprite
          in Directory(p.join(existing, 'sprites')).list()) {
        if (sprite is File) {
          await sprite
              .copy(p.join(copied.path, 'sprites', p.basename(sprite.path)));
        }
      }
      final session = RecordingSession.fromJson(
          jsonDecode(await File(p.join(copied.path, 'session.json'))
              .readAsString()) as Map<String, dynamic>,
          copied.path);
      final original = File(p.join(existing, 'recording.mp4'));
      final originalInfo = await backend.probe(original.path);
      result['original'] = infoJson(originalInfo);
      result['materialMotion'] = await motionStats(session);
      result['stage'] = 'recomposing';
      await save();
      final output = p.join(root.path, 'recording-smooth.mp4');
      await backend.burn(session, output, () => false);
      final info = await backend.probe(output);
      await ffmpeg(['-v', 'error', '-xerror', '-i', output, '-f', 'null', '-']);
      result['recomposed'] = {
        ...infoJson(info),
        'path': output,
        'fullDecode': true
      };
      for (final entry in {'before': original.path, 'after': output}.entries) {
        final folder = Directory(p.join(root.path, entry.key));
        await folder.create();
        await ffmpeg([
          '-y',
          '-v',
          'error',
          '-ss',
          '1',
          '-i',
          entry.value,
          '-vf',
          'crop=${math.min(640, info.width)}:${math.min(180, info.height)}:0:0',
          '-frames:v',
          '12',
          p.join(folder.path, 'frame%02d.png')
        ]);
      }
    }
    result['passed'] = true;
  } catch (error, stack) {
    result.addAll({'passed': false, 'error': '$error', 'stack': '$stack'});
  } finally {
    await backend.cancel();
    await save();
  }
  exit(result['passed'] == true ? 0 : 1);
}

Map<String, Object> infoJson(RecordingMediaInfo info) => {
      'width': info.width,
      'height': info.height,
      'frameRate': info.frameRate,
      'durationMs': info.duration.inMilliseconds,
    };

Future<Map<String, Object>> synthetic(
    Directory root, FFmpegRecordingBackend backend) async {
  final directory = Directory(p.join(root.path, 'synthetic'));
  await Directory(p.join(directory.path, 'sprites')).create(recursive: true);
  final session = RecordingSession(
      id: 'cadence',
      directory: directory.path,
      roomId: 'fixture',
      roomTitle: 'fixture',
      platform: 'fixture',
      mode: RecordingMode.burnDanmaku,
      createdAt: DateTime.now(),
      timelineConfirmed: true,
      mediaStartMs: 0,
      captureDurationMs: 1000);
  await ffmpeg([
    '-y',
    '-v',
    'error',
    '-f',
    'lavfi',
    '-i',
    'color=black:size=160x90:rate=30',
    '-t',
    '1',
    '-c:v',
    'libx264',
    '-pix_fmt',
    'yuv420p',
    session.rawPath
  ]);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 8, 8),
      ui.Paint()..color = const ui.Color(0xFFFF0000));
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
  picture.dispose();
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(p.join(directory.path, 'sprites', 'marker.png'))
        .writeAsBytes(png!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
  final frames = List.generate(
      31,
      (index) => RecordingOverlayFrame(
              position: Duration(microseconds: (index * 1000000 / 30).round()),
              canvasWidth: 160,
              canvasHeight: 90,
              items: [
                RecordingOverlayItem(
                    spriteId: 'marker',
                    instanceId: 'moving-marker',
                    x: 10 + index * 2.0,
                    y: 20,
                    width: 8,
                    height: 8)
              ]));
  await File(p.join(directory.path, 'frames.jsonl'))
      .writeAsString(frames.map((f) => jsonEncode(f.toJson())).join('\n'));
  final output = p.join(root.path, 'cadence.mp4');
  await backend.burn(session, output, () => false);
  final info = await backend.probe(output);
  final pixels = p.join(root.path, 'cadence.rgb');
  await ffmpeg([
    '-y',
    '-v',
    'error',
    '-xerror',
    '-i',
    output,
    '-pix_fmt',
    'rgb24',
    '-f',
    'rawvideo',
    pixels
  ]);
  final bytes = await File(pixels).readAsBytes();
  const frameBytes = 160 * 90 * 3;
  final positions = <double>[];
  for (var offset = 0;
      offset + frameBytes <= bytes.length;
      offset += frameBytes) {
    var count = 0, xSum = 0;
    for (var y = 18; y < 31; y++) {
      for (var x = 0; x < 100; x++) {
        final pixel = offset + (y * 160 + x) * 3;
        if (bytes[pixel] > 180 &&
            bytes[pixel + 1] < 80 &&
            bytes[pixel + 2] < 80) {
          xSum += x;
          count++;
        }
      }
    }
    if (count == 0) {
      throw StateError('Moving marker missing from decoded frame');
    }
    positions.add(xSum / count);
  }
  final repeats = List.generate(positions.length - 1,
          (i) => (positions[i + 1] - positions[i]).abs() < .25)
      .where((repeat) => repeat)
      .length;
  if ((info.frameRate - 60).abs() > .1 ||
      positions.length < 58 ||
      repeats > 2) {
    throw StateError(
        'Overlay cadence stalled: fps=${info.frameRate}, frames=${positions.length}, repeated=$repeats');
  }
  return {
    ...infoJson(info),
    'decodedFrames': positions.length,
    'repeatedMarkerPositions': repeats,
    'markerX': positions
  };
}

Future<Map<String, Object>> motionStats(RecordingSession session) async {
  final frames =
      (await File(p.join(session.directory, 'frames.jsonl')).readAsLines())
          .where((line) => line.trim().isNotEmpty)
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
  var cursor = 0, floorRepeated = 0, smoothRepeated = 0;
  Map<String, dynamic>? previousFloor, previousSmooth;
  final count = (session.captureDurationMs! * 60 / 1000).ceil();
  for (var index = 0; index < count; index++) {
    final time = session.mediaStartMs! + index * 1000 / 60;
    while (cursor + 1 < frames.length &&
        (frames[cursor + 1]['positionMs'] as num) <= time) {
      cursor++;
    }
    final current = frames[cursor];
    final next = cursor + 1 < frames.length ? frames[cursor + 1] : null;
    final smoothed = interpolateRecordingOverlayFrame(current, next, time);
    if (identical(current, previousFloor)) floorRepeated++;
    if (previousSmooth != null &&
        jsonEncode(smoothed?['items']) == jsonEncode(previousSmooth['items'])) {
      smoothRepeated++;
    }
    previousFloor = current;
    previousSmooth = smoothed;
  }
  return {
    'outputSamples': count,
    'heldSnapshotsBefore': floorRepeated,
    'unchangedPosesAfter': smoothRepeated
  };
}
