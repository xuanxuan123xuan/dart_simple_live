import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/recording/recording_backend.dart';

class _FakeCommand implements RecordingNativeCommand {
  _FakeCommand(this.onCancel);

  final void Function() onCancel;
  int cancellations = 0;

  @override
  Future<void> cancel() async {
    cancellations++;
    onCancel();
  }
}

class _FakeRunner implements RecordingNativeCommandRunner {
  final Completer<void> ffmpegStarted = Completer<void>();
  final Completer<void> ffprobeStarted = Completer<void>();
  final Completer<void> cancellationRequested = Completer<void>();
  final List<List<String>> ffmpegArguments = [];
  final List<List<String>> ffprobeArguments = [];
  void Function(RecordingNativeResult)? _ffmpegComplete;
  late final _FakeCommand ffmpegCommand = _FakeCommand(() {
    if (!cancellationRequested.isCompleted) {
      cancellationRequested.complete();
    }
  });
  late final _FakeCommand ffprobeCommand = _FakeCommand(() {
    if (!cancellationRequested.isCompleted) {
      cancellationRequested.complete();
    }
  });
  String ffprobeOutput = '{}';
  bool completeProbeImmediately = false;

  @override
  Future<RecordingNativeCommand> runFfmpeg(List<String> arguments,
      void Function(RecordingNativeResult) onComplete) async {
    ffmpegArguments.add(arguments.toList());
    _ffmpegComplete = onComplete;
    if (!ffmpegStarted.isCompleted) ffmpegStarted.complete();
    return ffmpegCommand;
  }

  @override
  Future<RecordingNativeCommand> runFfprobe(List<String> arguments,
      void Function(RecordingNativeResult) onComplete) async {
    ffprobeArguments.add(arguments.toList());
    if (!ffprobeStarted.isCompleted) ffprobeStarted.complete();
    if (completeProbeImmediately) {
      onComplete(RecordingNativeResult(success: true, output: ffprobeOutput));
    }
    return ffprobeCommand;
  }

  void finishFfmpeg({bool success = true}) {
    _ffmpegComplete!(RecordingNativeResult(success: success));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cancel waits for the native completion callback', () async {
    final runner = _FakeRunner();
    final backend = FFmpegRecordingBackend(nativeRunner: runner);
    final operation = backend.remux('raw.mkv', 'partial.mp4');
    await runner.ffmpegStarted.future;

    var cancelFinished = false;
    final cancelling = backend.cancel().then((_) => cancelFinished = true);
    await Future<void>.delayed(Duration.zero);
    expect(runner.ffmpegCommand.cancellations, 1);
    expect(cancelFinished, isFalse);

    runner.finishFfmpeg(success: false);
    await expectLater(operation, throwsStateError);
    await cancelling;
    expect(cancelFinished, isTrue);
  });

  test('timeout cancels native work and waits before reporting failure',
      () async {
    final runner = _FakeRunner();
    final backend = FFmpegRecordingBackend(
        nativeRunner: runner, executeTimeout: const Duration(milliseconds: 5));
    var operationFinished = false;
    final operation = backend.transcode('raw.mkv', 'partial.mp4').then((_) {
      operationFinished = true;
    });
    await runner.ffmpegStarted.future;
    await runner.cancellationRequested.future;
    await Future<void>.delayed(Duration.zero);
    expect(operationFinished, isFalse);

    runner.finishFfmpeg(success: false);
    await expectLater(operation, throwsA(isA<TimeoutException>()));
    expect(operationFinished, isFalse);
    expect(runner.ffmpegCommand.cancellations, 1);
  });

  test('probe exposes the first decoded frame timestamp for trimming',
      () async {
    final runner = _FakeRunner()
      ..completeProbeImmediately = true
      ..ffprobeOutput = jsonEncode({
        'format': {'duration': '2.165'},
        'streams': [
          {
            'codec_type': 'video',
            'codec_name': 'h264',
            'width': 1920,
            'height': 1080,
            'avg_frame_rate': '30/1'
          },
          {'codec_type': 'audio', 'codec_name': 'aac'}
        ],
        'frames': [
          {'media_type': 'audio', 'best_effort_timestamp_time': '0.666'},
          {'media_type': 'video', 'best_effort_timestamp_time': '0.699'},
          {'media_type': 'video', 'best_effort_timestamp_time': '0.733'}
        ]
      });
    final backend = FFmpegRecordingBackend(nativeRunner: runner);

    final info = await backend.probe('raw.mkv');

    expect(info.duration, const Duration(milliseconds: 2165));
    expect(info.firstVideoFrameStart, const Duration(milliseconds: 699));
    expect(info.audioCodec, 'aac');
    expect(runner.ffprobeArguments.single, contains('%+30'));
    expect(runner.ffprobeArguments.single, contains('-show_frames'));
  });

  test('serializes FFprobe behind an active FFmpeg command', () async {
    final runner = _FakeRunner()
      ..completeProbeImmediately = true
      ..ffprobeOutput = jsonEncode({
        'format': {'duration': '10.0'},
        'frames': [
          {'media_type': 'video', 'best_effort_timestamp_time': '0'}
        ],
        'streams': [
          {
            'codec_type': 'video',
            'codec_name': 'h264',
            'width': 1920,
            'height': 1080,
            'avg_frame_rate': '30/1'
          },
          {'codec_type': 'audio', 'codec_name': 'aac'}
        ]
      });
    final backend = FFmpegRecordingBackend(nativeRunner: runner);
    final remux = backend.remux('raw.mkv', 'first.mp4');
    await runner.ffmpegStarted.future;
    final probe = backend.probe('raw.mkv');
    await Future<void>.delayed(Duration.zero);

    expect(runner.ffprobeArguments, isEmpty);
    runner.finishFfmpeg();
    await remux;
    expect((await probe).valid, isTrue);
    expect(runner.ffprobeArguments, hasLength(1));
  });

  test('cancel invalidates queued native work after active callback drains',
      () async {
    final runner = _FakeRunner();
    final backend = FFmpegRecordingBackend(nativeRunner: runner);
    final remux = backend.remux('raw.mkv', 'first.mp4');
    await runner.ffmpegStarted.future;
    final probe = backend.probe('raw.mkv');
    final cancelling = backend.cancel();
    await runner.cancellationRequested.future;

    expect(runner.ffprobeArguments, isEmpty);
    runner.finishFfmpeg(success: false);
    await expectLater(remux, throwsStateError);
    await expectLater(probe, throwsStateError);
    await cancelling;
    expect(runner.ffprobeArguments, isEmpty);
  });

  test('positive container metadata without a decodable frame is rejected',
      () async {
    final runner = _FakeRunner()
      ..completeProbeImmediately = true
      ..ffprobeOutput = jsonEncode({
        'format': {'duration': '10'},
        'streams': [
          {
            'codec_type': 'video',
            'codec_name': 'h264',
            'width': 320,
            'height': 180
          }
        ],
        'frames': [],
      });
    await expectLater(
        FFmpegRecordingBackend(nativeRunner: runner).probe('broken.mkv'),
        throwsStateError);
  });
}
