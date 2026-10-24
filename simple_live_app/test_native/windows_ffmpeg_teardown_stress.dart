// Windows native teardown stress entrypoint.
// Build as a separate app target, then launch with:
//   --mode=active-close|cancel-close --output-dir=<unique-directory>
// The parent PowerShell harness starts it hidden and observes started.json.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

const _watchdogDuration = Duration(seconds: 8);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = _parseArguments(args);
  final outputDirectory = Directory(options.outputDirectory).absolute;
  await outputDirectory.create(recursive: true);

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(child: Text('FFmpegKit native teardown stress test')),
    ),
  ));

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'FFmpegKit teardown stress',
      skipTaskbar: true,
    ),
  );
  await windowManager.hide();

  var firstStatisticsSeen = false;
  var failureReported = false;

  Future<void> reportFailure(String stage, Object error,
      [StackTrace? stack]) async {
    if (failureReported) return;
    failureReported = true;
    await _writeJson(
      File('${outputDirectory.path}${Platform.pathSeparator}failure.json'),
      <String, Object?>{
        'mode': options.mode,
        'stage': stage,
        'error': error.toString(),
        if (stack != null) 'stack': stack.toString(),
        'reportedAtUtc': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  // Keep this watchdog armed through the close request. If native teardown or
  // the close channel stalls, the parent can distinguish it from a clean run.
  Timer(_watchdogDuration, () {
    unawaited(() async {
      await reportFailure(
        'watchdog',
        'No process exit within ${_watchdogDuration.inSeconds} seconds.',
      );
      try {
        await windowManager.close();
      } on Object {
        // The parent harness remains responsible for its own PID timeout.
      }
    }());
  });

  final outputFile = File(
    '${outputDirectory.path}${Platform.pathSeparator}long-running.mkv',
  );

  Future<void> closeAfterNativeProgress(Statistics statistics) async {
    await _writeJson(
      File('${outputDirectory.path}${Platform.pathSeparator}started.json'),
      <String, Object?>{
        'mode': options.mode,
        'sessionId': statistics.getSessionId(),
        'videoFrameNumber': statistics.getVideoFrameNumber(),
        'timeMs': statistics.getTime(),
        'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'output': outputFile.path,
      },
    );

    try {
      if (options.mode == 'cancel-close') {
        // This API requests cancellation. The teardown test intentionally
        // closes immediately after its MethodChannel response without waiting
        // for the FFmpeg session-complete callback.
        await FFmpegKit.cancel(statistics.getSessionId());
      }
      await windowManager.close();
    } on Object catch (error, stack) {
      await reportFailure('close-request', error, stack);
      try {
        await windowManager.close();
      } on Object {
        // The parent harness will time out and stop only this process.
      }
    }
  }

  try {
    await FFmpegKit.executeWithArgumentsAsync(
      <String>[
        '-hide_banner',
        '-loglevel',
        'warning',
        '-nostdin',
        '-y',
        '-re',
        '-f',
        'lavfi',
        '-i',
        'testsrc2=size=1280x720:rate=30',
        '-t',
        '30',
        '-an',
        '-c:v',
        'libx264',
        '-preset',
        'ultrafast',
        '-pix_fmt',
        'yuv420p',
        '-f',
        'matroska',
        outputFile.path,
      ],
      null,
      null,
      (Statistics statistics) {
        if (firstStatisticsSeen ||
            statistics.getVideoFrameNumber() < 1 ||
            statistics.getTime() <= 0) return;
        firstStatisticsSeen = true;
        unawaited(closeAfterNativeProgress(statistics));
      },
    );
  } on Object catch (error, stack) {
    await reportFailure('start-native-session', error, stack);
    try {
      await windowManager.close();
    } on Object {
      // The parent harness will time out and stop only this process.
    }
  }
}

({String mode, String outputDirectory}) _parseArguments(List<String> args) {
  final options = <String, String>{};
  for (final arg in args) {
    final separator = arg.indexOf('=');
    if (separator > 0) {
      options[arg.substring(0, separator)] = arg.substring(separator + 1);
    }
  }

  final mode = switch (options['--mode']) {
    'active-close' => 'active-close',
    'cancel-close' => 'cancel-close',
    _ =>
      throw const FormatException('Expected --mode=active-close|cancel-close.'),
  };
  final outputDirectory = options['--output-dir'];
  if (outputDirectory == null || outputDirectory.isEmpty) {
    throw const FormatException('Expected a non-empty --output-dir.');
  }
  return (mode: mode, outputDirectory: outputDirectory);
}

Future<void> _writeJson(File file, Map<String, Object?> value) async {
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(value),
    flush: true,
  );
}
