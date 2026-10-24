// Windows-only native recording soak. This is a separate Flutter entrypoint;
// it does not change the regular recording smoke test.
// Set SIMPLE_LIVE_RECORDING_LONG_SECONDS=10 for a short native validation.
// The default performs an actual six-minute media-position capture.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:simple_live_app/services/recording/mpv_recording_source.dart';
import 'package:simple_live_app/services/recording/recording_backend.dart';
import 'package:simple_live_app/services/recording/recording_service.dart';

const _defaultRecordingSeconds = 360;
const _progressInterval = Duration(seconds: 30);
const _playbackStartTimeout = Duration(seconds: 30);
const _exportTimeout = Duration(minutes: 10);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(child: Text('Long video-only recording smoke test')),
    ),
  ));

  final baseDirectory = Directory(
    Platform.environment['SIMPLE_LIVE_RECORDING_LONG_DIR'] ??
        p.join(Directory.current.path, '.tmp', 'recording-long-smoke'),
  ).absolute;
  final results = <String, dynamic>{
    'platform': Platform.operatingSystem,
    'mode': RecordingMode.videoOnly.name,
    'timelineCaptureEnabled': false,
    'validationScope':
        'Windows videoOnly long capture; danmaku timeline synchronization is not measured.',
    'requestedRecordingSeconds': _defaultRecordingSeconds,
    'fixtureGeneration': 'pending',
  };
  Directory? runDirectory;

  try {
    await baseDirectory.create(recursive: true);
    runDirectory = Directory(p.join(
      baseDirectory.path,
      'run-${DateTime.now().microsecondsSinceEpoch}',
    ));
    await runDirectory.create(recursive: true);
    results['runDirectory'] = runDirectory.path;
    results['startedAtUtc'] = DateTime.now().toUtc().toIso8601String();
    if (!Platform.isWindows) {
      throw UnsupportedError('This long smoke validates Windows only.');
    }
    final recordingSeconds = _readRecordingSeconds();
    results['requestedRecordingSeconds'] = recordingSeconds;

    await _runLongRecording(
      runDirectory: runDirectory,
      recordingSeconds: recordingSeconds,
      results: results,
    );
    results['passed'] = true;
  } on Object catch (error, stack) {
    results['passed'] = false;
    results['error'] = error.toString();
    results['stack'] = stack.toString();
  }

  var passed = results['passed'] == true &&
      ((results['cleanupErrors'] as List<Object?>?)?.isEmpty ?? true);
  results['passed'] = passed;
  results['finishedAtUtc'] = DateTime.now().toUtc().toIso8601String();
  if (runDirectory != null) {
    try {
      results['exitCode'] = passed ? 0 : 1;
      await _writeJson(File(p.join(runDirectory.path, 'result.json')), results);
    } on Object catch (error) {
      passed = false;
      results['passed'] = false;
      results['exitCode'] = 1;
      debugPrint('Could not write final result.json: $error');
    }
  } else {
    results['exitCode'] = 1;
  }
  exit(passed ? 0 : 1);
}

int _readRecordingSeconds() {
  final raw = Platform.environment['SIMPLE_LIVE_RECORDING_LONG_SECONDS'];
  if (raw == null || raw.trim().isEmpty) return _defaultRecordingSeconds;
  final seconds = int.tryParse(raw.trim());
  if (seconds == null || seconds <= 0 || seconds > 24 * 60 * 60) {
    throw const FormatException(
      'SIMPLE_LIVE_RECORDING_LONG_SECONDS must be between 1 and 86400.',
    );
  }
  return seconds;
}

Future<void> _runLongRecording({
  required Directory runDirectory,
  required int recordingSeconds,
  required Map<String, dynamic> results,
}) async {
  final fixtureSeconds = recordingSeconds + 15;
  final fixture = File(p.join(runDirectory.path, 'fixture.flv'));
  final recordingsDirectory =
      Directory(p.join(runDirectory.path, 'recordings'));
  HttpServer? server;
  StreamSubscription<HttpRequest>? requests;
  RecordingService? service;
  MpvRecordingSource? recordingSource;
  Player? player;
  StreamSubscription<PlayerLog>? playerLogs;
  final activeResponses = <Future<void>>{};

  try {
    results['fixtureDurationSeconds'] = fixtureSeconds;
    results['fixtureGeneration'] = 'running';
    await _generateFixture(fixture, fixtureSeconds);
    results['fixtureGeneration'] = 'complete';
    results['fixtureBytes'] = await fixture.length();

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixtureServer = server;
    requests = fixtureServer.listen((request) {
      late final Future<void> responseTask;
      responseTask = _serveFixture(request, fixture).whenComplete(() {
        activeResponses.remove(responseTask);
      });
      activeResponses.add(responseTask);
    });

    player = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error),
    );
    playerLogs = player.stream.log.listen((log) {
      debugPrint('mpv ${log.prefix}: ${log.text}');
    });
    final nativePlayer = player.platform as NativePlayer;
    await nativePlayer.setProperty('vo', 'null');
    await nativePlayer.setProperty('ao', 'null');
    await nativePlayer.setProperty('vid', 'auto');
    await nativePlayer.setProperty('cache', 'no');
    await nativePlayer.setProperty('cache-on-disk', 'no');
    await nativePlayer.setProperty('demuxer-max-bytes', '524288');
    await nativePlayer.setProperty('demuxer-readahead-secs', '1');
    await nativePlayer.setProperty('cache-pause', 'no');
    await player.open(
      Media('http://127.0.0.1:${fixtureServer.port}/fixture.flv'),
    );
    await _waitForPlayback(player);

    service = RecordingService();
    await service.initialize(recordingsDirectory.path);
    recordingSource = MpvRecordingSource(player, captureTimeline: false);
    await service.start(RecordingStartRequest(
      roomId: 'local-long-fixture',
      roomTitle: 'Local long recording fixture',
      platform: 'local fixture',
      mode: RecordingMode.videoOnly,
      source: recordingSource,
    ));

    final session = service.activeSession;
    if (session == null) {
      throw StateError(
          'RecordingService.start returned without an active session.');
    }
    final startPosition = readMpvRecordingPosition(player);
    final targetPosition = startPosition + Duration(seconds: recordingSeconds);
    final captureClock = Stopwatch()..start();
    var lastProgress = Duration.zero;

    await _writeProgress(
      runDirectory: runDirectory,
      session: session,
      player: player,
      startPosition: startPosition,
      elapsed: captureClock.elapsed,
      stage: 'recording',
      targetSeconds: recordingSeconds,
    );

    // Success is determined only by decoded media position. Wall-clock time
    // below is a maximum watchdog, not a substitute for the requested duration.
    while (readMpvRecordingPosition(player) < targetPosition) {
      final elapsed = captureClock.elapsed;
      if (elapsed >= Duration(seconds: recordingSeconds + 30)) {
        throw TimeoutException(
          'Playback advanced only ${readMpvRecordingPosition(player) - startPosition} '
          'within the ${recordingSeconds + 30}s recording watchdog.',
        );
      }
      if (elapsed - lastProgress >= _progressInterval) {
        await _writeProgress(
          runDirectory: runDirectory,
          session: session,
          player: player,
          startPosition: startPosition,
          elapsed: elapsed,
          stage: 'recording',
          targetSeconds: recordingSeconds,
        );
        lastProgress = elapsed;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    final endPosition = readMpvRecordingPosition(player);
    results['recordingStartMediaPositionMs'] = startPosition.inMilliseconds;
    results['recordingEndMediaPositionMs'] = endPosition.inMilliseconds;
    results['mediaPositionAdvancedMs'] =
        (endPosition - startPosition).inMilliseconds;
    results['recordingElapsedSeconds'] = captureClock.elapsed.inSeconds;
    await _writeProgress(
      runDirectory: runDirectory,
      session: session,
      player: player,
      startPosition: startPosition,
      elapsed: captureClock.elapsed,
      stage: 'stopping',
      targetSeconds: recordingSeconds,
    );

    await service.stop(reason: 'long-smoke-media-position-target-reached');
    await _waitForExport(session);
    if (session.status != RecordingStatus.complete ||
        session.outputPath == null) {
      throw StateError(
        'Recording/export did not complete: status=${session.status.name}, '
        'error=${session.error}',
      );
    }

    final backend = FFmpegRecordingBackend();
    final mediaInfo = await backend.probe(session.outputPath!);
    if (!mediaInfo.valid) {
      throw StateError('Final recording failed backend.probe validation.');
    }
    final durationTolerance = Duration(seconds: recordingSeconds - 2);
    if (mediaInfo.duration < durationTolerance) {
      throw StateError(
        'Final media duration ${mediaInfo.duration.inMilliseconds}ms is shorter '
        'than the requested ${recordingSeconds}s capture.',
      );
    }
    if (mediaInfo.width != 320 ||
        mediaInfo.height != 180 ||
        mediaInfo.videoCodec != 'h264' ||
        mediaInfo.audioCodec != 'aac') {
      throw StateError(
        'Unexpected final stream layout: ${mediaInfo.width}x${mediaInfo.height} '
        '${mediaInfo.videoCodec}/${mediaInfo.audioCodec}.',
      );
    }

    final decode = await FFmpegKit.executeWithArguments(<String>[
      '-v',
      'error',
      '-xerror',
      '-i',
      session.outputPath!,
      '-f',
      'null',
      '-',
    ]);
    final decodeReturnCode = await decode.getReturnCode();
    if (!ReturnCode.isSuccess(decodeReturnCode)) {
      throw StateError(
        'Full decode failed with return code $decodeReturnCode: '
        '${await decode.getOutput()}',
      );
    }

    final outputSize = await File(session.outputPath!).length();
    results.addAll(<String, Object?>{
      'sessionId': session.id,
      'sessionStatus': session.status.name,
      'sessionError': session.error,
      'timelineConfirmed': session.timelineConfirmed,
      'timelineCaptureEnabled': false,
      'rawPath': session.rawPath,
      'outputPath': session.outputPath,
      'outputBytes': outputSize,
      'probe': <String, Object?>{
        'valid': mediaInfo.valid,
        'durationMs': mediaInfo.duration.inMilliseconds,
        'width': mediaInfo.width,
        'height': mediaInfo.height,
        'videoCodec': mediaInfo.videoCodec,
        'audioCodec': mediaInfo.audioCodec,
        'frameRate': mediaInfo.frameRate,
      },
      'fullDecode': <String, Object?>{
        'returnCode': decodeReturnCode?.getValue(),
        'success': ReturnCode.isSuccess(decodeReturnCode),
        'validation': 'ffmpeg -v error -xerror -i <output> -f null -',
      },
    });
    await _writeProgress(
      runDirectory: runDirectory,
      session: session,
      player: player,
      startPosition: startPosition,
      elapsed: captureClock.elapsed,
      stage: 'complete',
      targetSeconds: recordingSeconds,
    );
  } finally {
    final cleanupErrors = <String>[];
    Future<void> cleanup(String name, Future<void> Function() action) async {
      try {
        await action();
      } on Object catch (error) {
        cleanupErrors.add('$name: $error');
      }
    }

    if (service != null) {
      await cleanup('RecordingService.shutdown', service.shutdown);
    }
    if (recordingSource != null) {
      await cleanup('MpvRecordingSource.release', recordingSource.release);
    }
    if (playerLogs != null) {
      await cleanup('player log subscription', playerLogs.cancel);
    }
    if (player != null) {
      await cleanup('Player.dispose', player.dispose);
    }
    if (requests != null) {
      await cleanup('HTTP request listener', requests.cancel);
    }
    if (server != null) {
      await cleanup('HttpServer.close', () => server!.close(force: true));
    }
    if (activeResponses.isNotEmpty) {
      await cleanup(
        'HTTP response drain',
        () => Future.wait(activeResponses.toList(), eagerError: false),
      );
    }
    if (service != null) {
      service.dispose();
    }
    results['cleanupErrors'] = cleanupErrors;
  }
}

Future<void> _generateFixture(File fixture, int durationSeconds) async {
  final session = await FFmpegKit.executeWithArguments(<String>[
    '-hide_banner',
    '-loglevel',
    'warning',
    '-nostdin',
    '-y',
    '-f',
    'lavfi',
    '-i',
    'testsrc2=size=320x180:rate=30',
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=440:sample_rate=44100',
    '-t',
    '$durationSeconds',
    '-c:v',
    'libx264',
    '-preset',
    'ultrafast',
    '-b:v',
    '300k',
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
    '-b:a',
    '48k',
    '-ar',
    '44100',
    '-f',
    'flv',
    fixture.path,
  ]);
  final returnCode = await session.getReturnCode();
  if (!ReturnCode.isSuccess(returnCode)) {
    throw StateError(
      'Local fixture generation failed with $returnCode: '
      '${await session.getOutput()}',
    );
  }
}

Future<void> _serveFixture(HttpRequest request, File fixture) async {
  final response = request.response;
  try {
    if (request.uri.path != '/fixture.flv') {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    response.headers.contentType = ContentType('video', 'x-flv');
    response.contentLength = await fixture.length();
    await response.addStream(fixture.openRead());
  } on Object {
    // mpv may close the HTTP response while replacing or disposing the source.
  } finally {
    try {
      await response.close();
    } on Object {
      // The client may already have closed its socket.
    }
  }
}

Future<void> _waitForPlayback(Player player) async {
  final startupClock = Stopwatch()..start();
  while (readMpvRecordingPosition(player) < const Duration(milliseconds: 500)) {
    if (startupClock.elapsed >= _playbackStartTimeout) {
      throw TimeoutException(
        'Local fixture playback did not advance within '
        '${_playbackStartTimeout.inSeconds}s.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForExport(RecordingSession session) async {
  final exportClock = Stopwatch()..start();
  while (session.status == RecordingStatus.queued ||
      session.status == RecordingStatus.exporting) {
    if (exportClock.elapsed >= _exportTimeout) {
      throw TimeoutException(
        'Recording export did not finish within ${_exportTimeout.inMinutes} '
        'minutes.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

Future<void> _writeProgress({
  required Directory runDirectory,
  required RecordingSession session,
  required Player player,
  required Duration startPosition,
  required Duration elapsed,
  required String stage,
  required int targetSeconds,
}) async {
  int? sizeBytes;
  try {
    final rawFile = File(session.rawPath);
    if (await rawFile.exists()) sizeBytes = await rawFile.length();
  } on Object {
    // A transient sharing violation should not interrupt a recording run.
  }

  final position = readMpvRecordingPosition(player);
  await _writeJson(
    File(p.join(runDirectory.path, 'progress.json')),
    <String, Object?>{
      'stage': stage,
      'recordingMode': RecordingMode.videoOnly.name,
      'timelineCaptureEnabled': false,
      'mediaPositionMs': position.inMilliseconds,
      'mediaPositionAdvancedMs': (position - startPosition).inMilliseconds,
      'recordingFileSizeBytes': sizeBytes,
      'elapsedSeconds': elapsed.inSeconds,
      'targetSeconds': targetSeconds,
      'updatedAtUtc': DateTime.now().toUtc().toIso8601String(),
    },
  );
}

Future<void> _writeJson(File file, Map<String, dynamic> value) async {
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(value),
    flush: true,
  );
}
