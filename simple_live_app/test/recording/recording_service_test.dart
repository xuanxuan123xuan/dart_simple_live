import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:simple_live_app/services/recording/recording_service.dart';

class FakeSource implements RecordingSource {
  int starts = 0, stops = 0;
  Completer<void>? startGate;
  bool timelineConfirmed = true;
  @override
  Future<void> start(String path) async {
    starts++;
    await startGate?.future;
    await File(path).writeAsBytes([1, 2, 3]);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<Duration> mediaPosition() async => const Duration(seconds: 110);
  @override
  Future<RecordingTimeline?> timeline() async => RecordingTimeline(
      mediaStart: const Duration(seconds: 100), confirmed: timelineConfirmed);
}

class FakeBackend implements RecordingBackend {
  int remuxes = 0, transcodes = 0;
  bool failRemux = false, invalidOutput = false;
  bool invalidRaw = false;
  int probeFailures = 0;
  Completer<void>? gate;
  @override
  Future<RecordingMediaInfo> probe(String path) async {
    if (probeFailures > 0) {
      probeFailures--;
      throw StateError('flush pending');
    }
    return RecordingMediaInfo(
        duration: invalidRaw
            ? Duration.zero
            : const Duration(seconds: 10),
        width: invalidRaw
            ? 0
            : invalidOutput && path.endsWith('partial.mp4')
                ? 640
                : 1920,
        height: 1080,
        videoCodec: 'h264',
        audioCodec: 'aac');
  }
  @override
  Future<void> remux(String input, String output,
      {Duration? duration, Duration start = Duration.zero}) async {
    remuxes++;
    await gate?.future;
    if (failRemux) throw StateError('fixture');
    await File(output).writeAsBytes([4, 5, 6]);
  }

  @override
  Future<void> transcode(String input, String output) async {
    transcodes++;
    await File(output).writeAsBytes([4, 5, 6]);
  }

  @override
  Future<void> burn(
      RecordingSession session, String output, bool Function() cancelled,
      {void Function(double progress)? onProgress}) async {
    if (!session.timelineConfirmed) throw StateError('No confirmed anchor');
    await transcode(session.rawPath, output);
  }

  @override
  Future<void> cancel() async {
    if (gate != null && !gate!.isCompleted) gate!.complete();
  }
}

Future<void> waitFor(RecordingService service, RecordingStatus status) async {
  if (service.sessions.first.status == status) return;
  final done = Completer<void>();
  void listener() {
    if (service.sessions.first.status == status && !done.isCompleted) {
      done.complete();
    }
  }

  service.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 5));
  } finally {
    service.removeListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FakeBackend backend;
  late RecordingService service;
  late FakeSource source;
  RecordingStartRequest request(
          [RecordingMode mode = RecordingMode.videoOnly]) =>
      RecordingStartRequest(
          roomId: 'room-1',
          roomTitle: 'Room',
          platform: 'test',
          mode: mode,
          source: source);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('recording-test-');
    backend = FakeBackend();
    source = FakeSource();
    service = RecordingService(backend: backend);
    await service.initialize(root.path);
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    if (service.isRecording) await service.stop();
    if (service.sessions.isNotEmpty &&
        {RecordingStatus.queued, RecordingStatus.exporting}
            .contains(service.sessions.first.status)) {
      await service.cancelExport(service.sessions.first.id);
      await waitFor(service, RecordingStatus.failed);
    }
    service.dispose();
    await root.delete(recursive: true);
  });

  test('one source is reused, MP4 validated, raw file preserved', () async {
    await service.start(request());
    await expectLater(service.start(request()), throwsStateError);
    await service.stop();
    await waitFor(service, RecordingStatus.complete);
    expect(source.starts, 1);
    expect(source.stops, 1);
    expect(backend.remuxes, 1);
    expect(await File(service.sessions.single.rawPath).exists(), isTrue);
    expect(await File(service.sessions.single.outputPath!).exists(), isTrue);
  });

  test('remux failure retains MKV without any transcoding', () async {
    backend.failRemux = true;
    await service.start(request());
    await service.stop();
    await waitFor(service, RecordingStatus.complete);
    expect(backend.transcodes, 0);
    expect(service.sessions.single.outputPath, service.sessions.single.rawPath);
  });

  test('stop retries a delayed flush before exporting', () async {
    backend.probeFailures = 2;
    await service.start(request());
    await service.stop();
    await waitFor(service, RecordingStatus.complete);
    expect(service.sessions.single.outputPath, isNotNull);
    expect(backend.remuxes, 1);
  });

  test('invalid raw media is retained without exposing a playable path', () async {
    backend.invalidRaw = true;
    await service.start(request());
    await service.stop();
    await waitFor(service, RecordingStatus.failed);
    expect(service.sessions.single.outputPath, isNull);
    expect(await File(service.sessions.single.rawPath).exists(), isTrue);
  });

  test('stop waits for an in-flight source start before detaching recorder',
      () async {
    source.startGate = Completer<void>();
    final starting = service.start(request());
    final stopping = service.stop(reason: 'room-exit');
    source.startGate!.complete();
    await starting;
    await stopping;
    await waitFor(service, RecordingStatus.complete);
    expect(source.starts, 1);
    expect(source.stops, 1);
    expect(service.sessions.single.stopReason, 'room-exit');
    expect(service.isRecording, isFalse);
  });

  test('wrong output dimensions fail validation and preserve source', () async {
    backend.invalidOutput = true;
    await service.start(request());
    await service.stop();
    await waitFor(service, RecordingStatus.failed);
    expect(service.sessions.single.outputPath, service.sessions.single.rawPath);
    expect(await File(service.sessions.single.rawPath).exists(), isTrue);
  });

  test('sidecar recording can later compose danmaku explicitly', () async {
    await service.start(request(RecordingMode.videoWithDanmaku));
    await service.stop();
    await waitFor(service, RecordingStatus.complete);
    expect(backend.transcodes, 0);
    await service.exportSession(service.sessions.single.id, burnDanmaku: true);
    await waitFor(service, RecordingStatus.complete);
    expect(backend.transcodes, 1);
    expect(service.sessions.single.exportBurnDanmaku, isTrue);
    expect(service.sessions.single.exportProgress, 1);
  });

  test('unconfirmed timeline cannot produce a claimed synchronized burn',
      () async {
    source.timelineConfirmed = false;
    await service.start(request(RecordingMode.burnDanmaku));
    await service.stop();
    await waitFor(service, RecordingStatus.failed);
    expect(service.sessions.single.outputPath, service.sessions.single.rawPath);
    expect(await File(service.sessions.single.rawPath).exists(), isTrue);
  });

  test('capture failure keeps original accessible and prevents later burning',
      () async {
    await service.start(request(RecordingMode.videoWithDanmaku));
    service.markCaptureFailure();
    await service.stop();
    expect(service.sessions.single.status, RecordingStatus.failed);
    expect(service.sessions.single.captureFailed, isTrue);
    expect(service.sessions.single.outputPath, service.sessions.single.rawPath);
    await service.exportSession(service.sessions.single.id, burnDanmaku: true);
    await waitFor(service, RecordingStatus.failed);
    expect(backend.transcodes, 0);
    expect(service.sessions.single.error, contains('弹幕素材捕获失败'));
  });

  test('danmaku capture failure flag cannot damage video-only recording',
      () async {
    await service.start(request());
    service.markCaptureFailure();
    await service.stop();
    await waitFor(service, RecordingStatus.complete);
    expect(service.sessions.single.captureFailed, isFalse);
  });

  test('background queues export until foreground and cancellation keeps raw',
      () async {
    service.setForeground(false);
    await service.start(request());
    await service.stop();
    expect(service.sessions.single.status, RecordingStatus.queued);
    expect(backend.remuxes, 0);
    backend.gate = Completer<void>();
    service.setForeground(true);
    await waitFor(service, RecordingStatus.exporting);
    await service.cancelExport(service.sessions.single.id);
    await waitFor(service, RecordingStatus.failed);
    expect(await File(service.sessions.single.rawPath).exists(), isTrue);
  });

  test('mobile background stops capture and resumed starts pending export',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await service.start(request());
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await waitFor(service, RecordingStatus.queued);
    expect(service.isRecording, isFalse);
    expect(service.sessions.single.stopReason, 'background');
    expect(backend.remuxes, 0);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await waitFor(service, RecordingStatus.complete);
  });

  test('service lifecycle stop flushes pending paint before detaching source',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final gate = Completer<void>();
    await service.start(RecordingStartRequest(
        roomId: 'room',
        roomTitle: 'Room',
        platform: 'test',
        mode: RecordingMode.videoWithDanmaku,
        source: source,
        beforeStop: () async {
          await gate.future;
          service.recordFrame(const RecordingOverlayFrame(
              position: Duration(seconds: 100),
              canvasWidth: 10,
              canvasHeight: 10,
              items: []));
        }));
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(source.stops, 0);
    gate.complete();
    await waitFor(service, RecordingStatus.queued);
    expect(source.stops, 1);
    final frameFile = File('${service.sessions.single.directory}/frames.jsonl');
    expect(await frameFile.readAsLines(), hasLength(1));
    await service.cancelExport(service.sessions.single.id);
  });

  test(
      'capture rejects backwards/oversampled frames and persists group opacity',
      () async {
    service.setForeground(false);
    await service.start(request(RecordingMode.videoWithDanmaku));
    await service.registerSprite('one', Uint8List.fromList([1]));
    for (final ms in [100000, 100010, 99999, 100100]) {
      service.recordFrame(RecordingOverlayFrame(
          position: Duration(milliseconds: ms),
          canvasWidth: 1280,
          canvasHeight: 720,
          opacity: .5,
          items: []));
    }
    await service.stop();
    final session = service.sessions.single;
    final lines = await File('${session.directory}/frames.jsonl').readAsLines();
    expect(lines.length, 2);
    expect((jsonDecode(lines.first) as Map)['opacity'], .5);
    expect(session.mediaStartMs, 100000);
    expect(session.timelineConfirmed, isTrue);
    await service.cancelExport(session.id);
  });

  test('recovery marks abandoned recording interrupted and keeps media',
      () async {
    final directory = await Directory('${root.path}/abandoned').create();
    final abandoned = RecordingSession(
        id: 'abandoned',
        directory: directory.path,
        roomId: '1',
        roomTitle: 'Old',
        platform: 'test',
        mode: RecordingMode.videoOnly,
        createdAt: DateTime(2026));
    await File('${directory.path}/session.json')
        .writeAsString(jsonEncode(abandoned.toJson()));
    await File(abandoned.rawPath).writeAsBytes([1]);
    final recovered = RecordingService(backend: backend);
    await recovered.initialize(root.path);
    expect(recovered.sessions.single.status, RecordingStatus.interrupted);
    expect(await File(recovered.sessions.single.rawPath).exists(), isTrue);
    await recovered.deleteSession('abandoned');
    expect(await directory.exists(), isFalse);
    recovered.dispose();
  });

  test('manifest write failure still releases capture and keeps original',
      () async {
    await service.start(request());
    final session = service.activeSession!;
    await Directory('${session.directory}/session.json.new').create();
    await service.stop();
    expect(service.isRecording, isFalse);
    expect(source.stops, 1);
    expect(session.status, RecordingStatus.failed);
    expect(session.error, contains('存储空间'));
    expect(await File(session.rawPath).exists(), isTrue);
    expect(backend.remuxes, 0);
  });
}
