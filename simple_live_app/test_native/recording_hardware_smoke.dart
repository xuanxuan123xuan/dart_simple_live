// Native GPU regression (a software fallback deliberately fails this test):
// flutter run -d windows -t test_native/recording_hardware_smoke.dart --no-pub
// SIMPLE_LIVE_RECORDING_HARDWARE_DIR optionally selects an absolute output root.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:simple_live_app/services/recording/mpv_recording_source.dart';
import 'package:simple_live_app/services/recording/recording_backend.dart';
import 'package:simple_live_app/services/recording/recording_mpv_bridge.dart';
import 'package:simple_live_app/services/recording/recording_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final base = Platform.environment['SIMPLE_LIVE_RECORDING_HARDWARE_DIR'] ??
      p.join(Directory.current.path, '.tmp', 'recording-hardware-smoke');
  final root = Directory(
      p.join(p.absolute(base), 'run-${DateTime.now().microsecondsSinceEpoch}'));
  await root.create(recursive: true);
  final results = <String, dynamic>{
    'startedAt': DateTime.now().toUtc().toIso8601String(),
    'outputDirectory': root.path,
    'platform': Platform.operatingSystem,
    'stages': <Map<String, dynamic>>[],
    'logs': <Map<String, String>>[],
  };
  void save() => File(p.join(root.path, 'result.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(results),
      flush: true);
  final watchdog = Timer(const Duration(minutes: 4), () {
    results['passed'] = false;
    results['error'] = 'Hardware recording watchdog expired after four minutes';
    save();
    exit(2);
  });
  try {
    save();
    await _run(root, results, save);
    results['passed'] = true;
  } catch (error, stack) {
    results['passed'] = false;
    results['error'] = '$error';
    results['stack'] = '$stack';
  } finally {
    watchdog.cancel();
    results['finishedAt'] = DateTime.now().toUtc().toIso8601String();
    save();
  }
  debugPrint('Hardware recording result: ${p.join(root.path, 'result.json')}');
  exit(results['passed'] == true ? 0 : 1);
}

Future<void> _ffmpeg(List<String> arguments) async {
  final session = await FFmpegKit.executeWithArguments(arguments);
  if (!ReturnCode.isSuccess(await session.getReturnCode())) {
    final output = await session.getOutput() ?? '';
    // This executable opens only its generated local fixture/output files.
    throw StateError(
        'FFmpeg failed: ${output.length > 6000 ? output.substring(output.length - 6000) : output}');
  }
}

Future<void> _run(
    Directory root, Map<String, dynamic> results, void Function() save) async {
  final clock = Stopwatch()..start();
  void stage(String name) {
    (results['stages'] as List).add({
      'name': name,
      'elapsedMs': clock.elapsedMilliseconds,
    });
    save();
  }

  stage('fixtureGenerating');
  final fixture = p.join(root.path, 'fixture.flv');
  await _ffmpeg([
    '-y',
    '-f',
    'lavfi',
    '-i',
    'testsrc2=size=640x360:rate=30',
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=440:sample_rate=48000',
    '-t',
    '24',
    '-c:v',
    'libx264',
    '-preset',
    'ultrafast',
    '-g',
    '30',
    '-keyint_min',
    '30',
    '-sc_threshold',
    '0',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    fixture,
  ]);
  stage('fixtureReady');
  final player = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn));
  final controller = VideoController(player,
      configuration: const VideoControllerConfiguration(hwdec: 'auto-safe'));
  final service = RecordingService();
  MpvRecordingSource? source;
  RecordingMpvBridge? bridge;
  Timer? capture;
  final logs = player.stream.log.listen((log) {
    final entries = results['logs'] as List;
    if (entries.length == 200) entries.removeAt(0);
    entries.add({
      'prefix': log.prefix,
      'level': log.level,
      'text': log.text.length > 1500 ? log.text.substring(0, 1500) : log.text,
    });
  });
  runApp(MaterialApp(
      home: Scaffold(
          body: Center(
              child: SizedBox(
                  width: 640,
                  height: 360,
                  child: Video(
                      controller: controller, controls: NoVideoControls))))));
  try {
    // A mounted Video creates the actual native render context, unlike vo=null.
    await WidgetsBinding.instance.endOfFrame;
    bridge = await IsolateRecordingMpvBridge.create(player);
    for (final option in <String, String>{
      'hwdec': 'auto-safe',
      'ao': 'null',
      'vid': 'auto',
      'cache': 'yes',
      'cache-on-disk': 'no',
      'demuxer-max-bytes': '524288',
      'demuxer-readahead-secs': '1',
      'cache-pause': 'no',
    }.entries) {
      await bridge.command(['set', option.key, option.value]);
    }
    await player.open(Media(fixture));
    await controller.waitUntilFirstFrameRendered
        .timeout(const Duration(seconds: 30));
    final playbackDeadline = DateTime.now().add(const Duration(seconds: 20));
    while (player.state.position.inMilliseconds < 500) {
      if (DateTime.now().isAfter(playbackDeadline)) {
        throw StateError('Rendered player failed to advance beyond 500ms');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    Future<Map<String, String>> snapshot() async {
      final values = <String, String>{};
      for (final property in [
        'hwdec',
        'hwdec-current',
        'vo',
        'video-params/pixelformat',
        'video-out-params/pixelformat',
        'vf',
      ]) {
        try {
          values[property] = await bridge!
              .getProperty(property)
              .timeout(const Duration(seconds: 5));
        } on RecordingMpvError catch (error) {
          values[property] = 'unavailable (${error.code})';
        }
      }
      return values;
    }

    final before = await snapshot();
    results['beforeRecording'] = before;
    stage('hardwarePlaying');
    final hwdec = before['hwdec-current']!.trim().toLowerCase();
    if (hwdec.isEmpty ||
        {'no', 'none', 'software', 'auto', 'auto-safe'}.contains(hwdec) ||
        hwdec.contains('copy') ||
        hwdec.startsWith('unavailable')) {
      throw StateError(
          'Actual hardware decoding required; hwdec-current=$hwdec');
    }
    if (before['vo'] == 'null' || before['vo']!.startsWith('unavailable')) {
      throw StateError('Actual native video output required');
    }
    await service.initialize(p.join(root.path, 'recordings'));
    source = MpvRecordingSource(player, captureTimeline: true);
    await service.start(RecordingStartRequest(
        roomId: 'hardware-fixture',
        roomTitle: 'Hardware fingerprint regression',
        platform: 'local fixture',
        mode: RecordingMode.burnDanmaku,
        source: source));
    final during = await snapshot();
    results['duringRecording'] = during;
    if (during['hwdec-current'] != before['hwdec-current'] ||
        during['hwdec'] != before['hwdec'] ||
        during['video-out-params/pixelformat'] != 'yuv420p') {
      throw StateError(
          'Fingerprint adapter did not preserve hardware decoding and normalize its output');
    }
    stage('recordingStarted');
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 60, 20),
        ui.Paint()..color = const ui.Color(0xFFFF0000));
    final picture = recorder.endRecording();
    final image = await picture.toImage(60, 20);
    picture.dispose();
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    await service.registerSprite('marker', png);
    var frameCount = 0;
    capture = Timer.periodic(const Duration(milliseconds: 16), (_) {
      frameCount++;
      service.recordFrame(RecordingOverlayFrame(
          position: readMpvRecordingPosition(player),
          canvasWidth: 640,
          canvasHeight: 360,
          items: const [
            RecordingOverlayItem(
                spriteId: 'marker', x: 20, y: 20, width: 60, height: 20)
          ]));
    });
    await Future<void>.delayed(const Duration(seconds: 7));
    capture.cancel();
    results['overlayFrameCount'] = frameCount;
    stage('stopping');
    await service.stop();
    final after = await snapshot();
    results['afterStop'] = after;
    stage('stopped');
    if (after['hwdec'] != before['hwdec'] ||
        after['hwdec-current'] != before['hwdec-current']) {
      throw StateError('Recording changed the configured hardware decoder');
    }
    for (final label in ['simplelive_recording', 'simplelive_capture_pixels']) {
      if (after['vf']!.contains(label)) {
        throw StateError('Recording filter leaked after stop: $label');
      }
    }
    final session = service.sessions.single;
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    while (session.status == RecordingStatus.queued ||
        session.status == RecordingStatus.exporting) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Automatic burn export timed out');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    results['recording'] = {
      'timelineConfirmed': session.timelineConfirmed,
      'status': session.status.name,
      'error': session.error,
      'mediaStartMs': session.mediaStartMs,
      'fileStartMs': session.fileStartMs,
      'outputPath': session.outputPath,
    };
    stage('automaticExportFinished');
    if (!session.timelineConfirmed ||
        session.status != RecordingStatus.complete ||
        session.error != null ||
        session.outputPath == null) {
      throw StateError('Hardware automatic burn failed: ${session.error}');
    }
    if (p.extension(session.outputPath!).toLowerCase() != '.mp4') {
      throw StateError('Automatic burn did not produce MP4');
    }
    final info = await FFmpegRecordingBackend().probe(session.outputPath!);
    results['probe'] = {
      'durationMs': info.duration.inMilliseconds,
      'videoCodec': info.videoCodec,
      'audioCodec': info.audioCodec,
      'width': info.width,
      'height': info.height,
    };
    if (info.width != 640 ||
        info.height != 360 ||
        info.duration < const Duration(seconds: 3)) {
      throw StateError('Unexpected exported geometry or duration');
    }
    await _ffmpeg([
      '-v',
      'error',
      '-xerror',
      '-i',
      session.outputPath!,
      '-f',
      'null',
      '-'
    ]);
    results['fullDecodePassed'] = true;
    stage('verified');
  } finally {
    capture?.cancel();
    // Keep the native core alive until every recording client has released it.
    await service.shutdown();
    await source?.release();
    await bridge?.close();
    await logs.cancel();
    service.dispose();
    runApp(const MaterialApp(
        home: Scaffold(body: Text('Hardware smoke finished'))));
    await WidgetsBinding.instance.endOfFrame;
    await player.dispose();
    stage('released');
  }
}
