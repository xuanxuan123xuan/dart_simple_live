// Run on a desktop/device host with native plugins, for example:
// flutter run -d windows -t test_native/recording_smoke.dart --no-pub
// Set SIMPLE_LIVE_RECORDING_SMOKE_DIR to an absolute writable output directory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:simple_live_app/services/recording/mpv_recording_source.dart';
import 'package:simple_live_app/services/recording/recording_backend.dart';
import 'package:simple_live_app/services/recording/recording_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(
      home:
          Scaffold(body: Center(child: Text('Recording native smoke test')))));
  final root = Directory(
      Platform.environment['SIMPLE_LIVE_RECORDING_SMOKE_DIR'] ??
          p.join(Directory.current.path, '.tmp', 'recording-native-smoke'));
  await root.create(recursive: true);
  final results = <String, dynamic>{};
  try {
    await _run(root, results);
    results['passed'] = true;
  } catch (error, stack) {
    results['passed'] = false;
    results['error'] = '$error';
    results['stack'] = '$stack';
  }
  await File(p.join(root.path, 'result.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(results),
      flush: true);
  exit(results['passed'] == true ? 0 : 1);
}

Future<void> _ffmpeg(List<String> arguments) async {
  final session = await FFmpegKit.executeWithArguments(arguments);
  if (!ReturnCode.isSuccess(await session.getReturnCode())) {
    throw StateError('Fixture operation failed: ${await session.getOutput()}');
  }
}

Future<void> _run(Directory root, Map<String, dynamic> results) async {
  final fixture = p.join(root.path, 'fixture.flv');
  await _ffmpeg([
    '-y',
    '-f',
    'lavfi',
    '-i',
    'testsrc2=size=320x180:rate=30',
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=440:sample_rate=48000',
    '-t',
    '20',
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
    fixture
  ]);
  final hls = p.join(root.path, 'fixture.m3u8');
  await _ffmpeg([
    '-y',
    '-i',
    fixture,
    '-c',
    'copy',
    '-hls_time',
    '1',
    '-hls_list_size',
    '0',
    hls
  ]);
  final hevc = p.join(root.path, 'fixture-hevc.m3u8');
  await _ffmpeg([
    '-y',
    '-i',
    fixture,
    '-c:v',
    'libx265',
    '-preset',
    'ultrafast',
    '-x265-params',
    'log-level=error:keyint=30:min-keyint=30:scenecut=0',
    '-c:a',
    'copy',
    '-hls_time',
    '1',
    '-hls_list_size',
    '0',
    hevc
  ]);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(() async {
    await for (final request in server) {
      unawaited(() async {
        try {
          final name = p.basename(request.uri.path);
          final file = File(p.join(root.path, name));
          if (!await file.exists()) {
            request.response.statusCode = 404;
          } else {
            request.response.contentLength = await file.length();
            if (name.endsWith('.flv')) {
              final handle = await file.open();
              try {
                while (true) {
                  final bytes = await handle.read(4096);
                  if (bytes.isEmpty) break;
                  request.response.add(bytes);
                  await request.response.flush();
                  await Future<void>.delayed(const Duration(milliseconds: 20));
                }
              } finally {
                await handle.close();
              }
            } else {
              await request.response.addStream(file.openRead());
            }
          }
          await request.response.close();
        } on Object {/* Test players may close an HTTP connection early. */}
      }());
    }
  }());
  try {
    for (final name in ['fixture.flv', 'fixture.m3u8', 'fixture-hevc.m3u8']) {
      final service = RecordingService();
      final player = Player(
          configuration:
              const PlayerConfiguration(logLevel: MPVLogLevel.error));
      final logs = player.stream.log.listen((log) {
        // Fixtures have no credentials or private addresses.
        debugPrint('mpv ${log.prefix}: ${log.text}');
      });
      Timer? capture;
      try {
        final native = player.platform as NativePlayer;
        await native.setProperty('vo', 'null');
        await native.setProperty('ao', 'null');
        await native.setProperty('vid', 'auto');
        await native.setProperty('cache', 'yes');
        await native.setProperty('cache-on-disk', 'no');
        await native.setProperty('demuxer-max-bytes', '524288');
        await native.setProperty('demuxer-readahead-secs', '1');
        await native.setProperty('cache-pause', 'no');
        await player.open(Media('http://127.0.0.1:${server.port}/$name'));
        for (var i = 0;
            i < 100 && player.state.position.inMilliseconds < 500;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await service.initialize(p.join(root.path, name.replaceAll('.', '-')));
        await service.start(RecordingStartRequest(
            roomId: name,
            roomTitle: name,
            platform: 'local fixture',
            mode: RecordingMode.videoWithDanmaku,
            source: MpvRecordingSource(player)));
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
        capture = Timer.periodic(const Duration(milliseconds: 16), (_) {
          service.recordFrame(RecordingOverlayFrame(
              position: readMpvRecordingPosition(player),
              canvasWidth: 320,
              canvasHeight: 180,
              items: const [
                RecordingOverlayItem(
                    spriteId: 'marker', x: 20, y: 20, width: 60, height: 20)
              ]));
        });
        await Future<void>.delayed(const Duration(seconds: 7));
        capture.cancel();
        await service.stop();
        final session = service.sessions.single;
        await _wait(service, session);
        if (!session.timelineConfirmed) {
          throw StateError('Unconfirmed ${session.roomId} timeline');
        }
        await service.exportSession(session.id, burnDanmaku: true);
        await _wait(service, session);
        if (session.status != RecordingStatus.complete ||
            session.error != null) {
          throw StateError('Native burn failed: ${session.error}');
        }
        final info = await FFmpegRecordingBackend().probe(session.outputPath!);
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
        results[name] = {
          'timelineConfirmed': session.timelineConfirmed,
          'mediaStartMs': session.mediaStartMs,
          'fileStartMs': session.fileStartMs,
          'durationMs': info.duration.inMilliseconds,
          'videoCodec': info.videoCodec,
          'audioCodec': info.audioCodec,
          'width': info.width,
          'height': info.height,
          'path': session.outputPath
        };

        // Reuse the same live player for a second segment. This exercises the
        // stop/flush/restart boundary used when a room reconnects.
        await service.start(RecordingStartRequest(
            roomId: name,
            roomTitle: '$name segment 2',
            platform: 'local fixture',
            mode: RecordingMode.videoOnly,
            source: MpvRecordingSource(player)));
        await Future<void>.delayed(const Duration(seconds: 2));
        await service.stop(reason: 'smoke-segment-boundary');
        final second = service.sessions.first;
        await _wait(service, second);
        if (second.status != RecordingStatus.complete ||
            second.outputPath == null) {
          throw StateError('Second segment failed: ${second.error}');
        }
        final secondInfo = await FFmpegRecordingBackend().probe(
          second.outputPath!,
        );
        await _ffmpeg([
          '-v',
          'error',
          '-xerror',
          '-i',
          second.outputPath!,
          '-f',
          'null',
          '-'
        ]);
        (results[name] as Map<String, dynamic>)['segments'] = [
          {
            'durationMs': info.duration.inMilliseconds,
            'path': session.outputPath,
          },
          {
            'durationMs': secondInfo.duration.inMilliseconds,
            'path': second.outputPath,
          },
        ];
      } finally {
        capture?.cancel();
        await logs.cancel();
        await player.dispose();
        service.dispose();
      }
    }
  } finally {
    await server.close(force: true);
  }
}

Future<void> _wait(RecordingService service, RecordingSession session) async {
  for (var i = 0; i < 1200; i++) {
    if (session.status != RecordingStatus.queued &&
        session.status != RecordingStatus.exporting) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Native export timed out');
}
