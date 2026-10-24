// Validate a gracefully finalized recording independently of its capture loop.
// SIMPLE_LIVE_RECORDING_VERIFY_FILE: absolute local media file.
// SIMPLE_LIVE_RECORDING_VERIFY_RESULT: absolute JSON result path.
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:simple_live_app/services/recording/recording_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
      const MaterialApp(home: Scaffold(body: Text('Recording verification'))));
  final path = Platform.environment['SIMPLE_LIVE_RECORDING_VERIFY_FILE'];
  final resultPath =
      Platform.environment['SIMPLE_LIVE_RECORDING_VERIFY_RESULT'];
  final minimum = int.tryParse(
      Platform.environment['SIMPLE_LIVE_RECORDING_VERIFY_SECONDS'] ?? '360');
  final result = <String, dynamic>{'path': path, 'minimumSeconds': minimum};
  final backend = FFmpegRecordingBackend();
  try {
    if (path == null || resultPath == null || minimum == null || minimum <= 0) {
      throw ArgumentError(
          'Supply the local file, result path and minimum duration');
    }
    final info = await backend.probe(path);
    result.addAll({
      'durationMs': info.duration.inMilliseconds,
      'width': info.width,
      'height': info.height,
      'videoCodec': info.videoCodec,
      'audioCodec': info.audioCodec,
      'bytes': await File(path).length(),
    });
    if (!info.valid || info.duration < Duration(seconds: minimum - 2)) {
      throw StateError(
          'Recording is invalid or shorter than the accepted duration');
    }
    final session = await FFmpegKit.executeWithArguments([
      '-protocol_whitelist',
      'file,pipe',
      '-v',
      'error',
      '-xerror',
      '-i',
      path,
      '-f',
      'null',
      '-',
    ]);
    final code = await session.getReturnCode();
    result['fullDecodeReturnCode'] = code?.getValue();
    if (!ReturnCode.isSuccess(code)) throw StateError('Full decode failed');
    result['passed'] = true;
  } catch (error, stack) {
    result.addAll({'passed': false, 'error': '$error', 'stack': '$stack'});
  } finally {
    await backend.cancel();
  }
  if (resultPath != null) {
    final file = File(resultPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(result),
        flush: true);
  }
  exit(result['passed'] == true ? 0 : 1);
}
