import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:simple_live_app/services/recording/recording_service.dart';

class FakeSource implements RecordingSource, RecordingSourceLifetime {
  int starts = 0, stops = 0;
  final startInvoked = Completer<void>();
  int releases = 0;
  int releaseFailures = 0;
  Completer<void>? startGate;
  bool failStart = false;
  bool timelineConfirmed = true;
  Duration mediaStart = const Duration(seconds: 100);
  Duration fileStart = Duration.zero;
  @override
  Future<void> start(String path) async {
    starts++;
    if (!startInvoked.isCompleted) startInvoked.complete();
    await startGate?.future;
    if (failStart) throw StateError('fixture start failure');
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
      mediaStart: mediaStart,
      confirmed: timelineConfirmed,
      fileStart: fileStart);

  @override
  Future<void> release() async {
    releases++;
    if (releaseFailures > 0) {
      releaseFailures--;
      throw StateError('fixture release failure');
    }
  }
}

class FakeBackend implements RecordingBackend {
  int remuxes = 0, transcodes = 0;
  bool failRemux = false, invalidOutput = false;
  bool invalidRaw = false;
  int probeFailures = 0;
  Completer<void>? gate;
  Completer<void>? cancelGate;
  Completer<void>? cancelStarted;
  Completer<void>? remuxStarted;
  Completer<void>? probeGate;
  Completer<void>? probeStarted;
  int cancelCalls = 0;
  int probeCalls = 0;
  final Map<String, RecordingMediaInfo> probeResults = {};
  final List<
          ({String input, String output, Duration? duration, Duration start})>
      remuxCalls = [];
  @override
  Future<RecordingMediaInfo> probe(String path) async {
    probeCalls++;
    if (probeStarted != null && !probeStarted!.isCompleted) {
      probeStarted!.complete();
    }
    await probeGate?.future;
    if (probeFailures > 0) {
      probeFailures--;
      throw StateError('flush pending');
    }
    final probed = probeResults[path];
    if (probed != null) return probed;
    return RecordingMediaInfo(
        duration: invalidRaw ? Duration.zero : const Duration(seconds: 10),
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
    if (remuxStarted != null && !remuxStarted!.isCompleted)
      remuxStarted!.complete();
    remuxCalls
        .add((input: input, output: output, duration: duration, start: start));
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
    cancelCalls++;
    if (cancelStarted != null && !cancelStarted!.isCompleted) {
      cancelStarted!.complete();
    }
    await cancelGate?.future;
    if (gate != null && !gate!.isCompleted) gate!.complete();
  }
}

Future<void> waitFor(RecordingService service, RecordingStatus status,
    {String? sessionId}) async {
  bool matches() => sessionId == null
      ? service.sessions.first.status == status
      : service.sessions.any(
          (session) => session.id == sessionId && session.status == status);
  if (matches()) return;
  final done = Completer<void>();
  void listener() {
    if (matches() && !done.isCompleted) {
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
    await service.shutdown();
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
    expect(source.releases, 1);
  });

  test('failed source start releases partially attached source resources',
      () async {
    source.failStart = true;

    await expectLater(service.start(request()), throwsStateError);

    expect(source.stops, 1);
    expect(source.releases, 1);
    expect(service.sessions.single.status, RecordingStatus.failed);
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

  test('first decoded video timestamp trims the raw stream before validation',
      () async {
    await service.start(request());
    final session = service.activeSession!;
    const rawDuration = Duration(milliseconds: 2165);
    const firstFrame = Duration(milliseconds: 699);
    const outputDuration = Duration(milliseconds: 1466);
    backend.probeResults[session.rawPath] = const RecordingMediaInfo(
        duration: rawDuration,
        width: 1920,
        height: 1080,
        videoCodec: 'h264',
        audioCodec: 'aac',
        firstVideoFrameStart: firstFrame);
    backend.probeResults[p.join(session.directory, 'export.partial.mp4')] =
        const RecordingMediaInfo(
            duration: outputDuration,
            width: 1920,
            height: 1080,
            videoCodec: 'h264',
            audioCodec: 'aac');

    await service.stop();
    await waitFor(service, RecordingStatus.complete);

    expect(session.fileStartMs, firstFrame.inMilliseconds);
    expect(backend.remuxCalls.single.start, firstFrame);
    expect(backend.remuxCalls.single.duration, outputDuration);
    expect(session.durationMs, outputDuration.inMilliseconds);
  });

  test('invalid raw media is retained without exposing a playable path',
      () async {
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

  test('non-finite overlay geometry fails capture without escaping callback',
      () async {
    service.setForeground(false);
    await service.start(request(RecordingMode.videoWithDanmaku));
    expect(
      () => service.recordFrame(const RecordingOverlayFrame(
          position: Duration(seconds: 100),
          canvasWidth: double.nan,
          canvasHeight: 10,
          items: [])),
      returnsNormally,
    );

    await service.stop();

    expect(service.sessions.single.status, RecordingStatus.failed);
    expect(service.sessions.single.captureFailed, isTrue);
    expect(source.releases, 1);
    expect(await File(service.sessions.single.rawPath).exists(), isTrue);
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

  test(
      'same-root refresh discovers new sessions and coalesces concurrent scans',
      () async {
    for (final id in ['one', 'two']) {
      final directory = await Directory('${root.path}/$id').create();
      final session = RecordingSession(
          id: id,
          directory: directory.path,
          roomId: '1',
          roomTitle: id,
          platform: 'test',
          mode: RecordingMode.videoOnly,
          createdAt: DateTime(2026),
          status: RecordingStatus.complete);
      await File('${directory.path}/session.json')
          .writeAsString(jsonEncode(session.toJson()));
    }

    await Future.wait(List.generate(5, (_) => service.initialize(root.path)));

    expect(
        service.sessions.map((session) => session.id).toSet(), {'one', 'two'});
    expect(service.sessions, hasLength(2));
  });

  test('capture finalization runs while a previous export is active', () async {
    service.dispose();
    final captureBackend = FakeBackend();
    service =
        RecordingService(backend: backend, captureBackend: captureBackend);
    await service.initialize(root.path);
    backend.gate = Completer<void>();
    backend.remuxStarted = Completer<void>();

    await service.start(request());
    await service.stop();
    final firstSession = service.sessions.single;
    await waitFor(service, RecordingStatus.exporting,
        sessionId: firstSession.id);
    await backend.remuxStarted!.future;

    await service.start(request());
    final secondSessionId = service.activeSession!.id;
    captureBackend.probeGate = Completer<void>();
    captureBackend.probeStarted = Completer<void>();
    var secondStopFinished = false;
    final secondStop = service.stop().then((_) => secondStopFinished = true);
    await captureBackend.probeStarted!.future;
    expect(captureBackend.probeCalls, 2);

    await service.cancelExport(firstSession.id);
    expect(secondStopFinished, isFalse);
    captureBackend.probeGate!.complete();
    await secondStop;

    await waitFor(service, RecordingStatus.failed, sessionId: firstSession.id);
    await waitFor(service, RecordingStatus.complete,
        sessionId: secondSessionId);
    expect(backend.remuxes, 2);
    expect(captureBackend.probeCalls, 2);
  });

  test('start waits behind a concurrent root switch scan', () async {
    final nextRoot = Directory('${root.path}/next-root');
    final initializing = service.initialize(nextRoot.path);
    final starting = service.start(request());

    await initializing;
    await starting;
    expect(p.isWithin(nextRoot.path, service.activeSession!.directory), isTrue);
    await service.stop();
  });

  test('directory scan excludes old-root export, leases and deletion',
      () async {
    service.setForeground(false);
    await service.start(request());
    await service.stop();
    final oldSession = service.sessions.single;
    await service.cancelExport(oldSession.id);
    final scanStarted = Completer<void>();
    void listener() {
      if (service.isScanningDirectory && !scanStarted.isCompleted)
        scanStarted.complete();
    }

    service.addListener(listener);
    final nextRoot = Directory('${root.path}/next-root');
    final initializing = service.initialize(nextRoot.path);
    await scanStarted.future.timeout(const Duration(seconds: 2));
    await Future.wait([
      expectLater(service.exportSession(oldSession.id), throwsStateError),
      expectLater(service.withSessionFiles(oldSession.id, (_) async {}),
          throwsStateError),
      expectLater(service.deleteSession(oldSession.id), throwsStateError),
    ]);
    await initializing;
    service.removeListener(listener);
    expect(service.sessions, isEmpty);
    expect(await File(oldSession.rawPath).exists(), isTrue);
  });

  test('failed root initialization preserves current list and can be retried',
      () async {
    final savedRoot = Directory('${root.path}-saved');
    await root.rename(savedRoot.path);
    await File(root.path).writeAsString('not a directory');

    await expectLater(
        service.initialize(root.path), throwsA(isA<FileSystemException>()));
    expect(service.sessions, isEmpty);

    await File(root.path).delete();
    await savedRoot.rename(root.path);
    final directory = await Directory('${root.path}/recovered').create();
    final session = RecordingSession(
        id: 'recovered',
        directory: directory.path,
        roomId: '1',
        roomTitle: 'Recovered',
        platform: 'test',
        mode: RecordingMode.videoOnly,
        createdAt: DateTime(2026),
        status: RecordingStatus.complete);
    await File('${directory.path}/session.json')
        .writeAsString(jsonEncode(session.toJson()));

    await service.initialize(root.path);
    expect(service.sessions.map((session) => session.id), ['recovered']);
  });

  test('malformed primary manifest falls back to a valid previous manifest',
      () async {
    final directory = await Directory('${root.path}/backup-session').create();
    final backupSession = RecordingSession(
        id: 'backup-session',
        directory: directory.path,
        roomId: '1',
        roomTitle: 'Recovered from backup',
        platform: 'test',
        mode: RecordingMode.videoOnly,
        createdAt: DateTime(2026),
        status: RecordingStatus.recording);
    await File('${directory.path}/session.json').writeAsString('{broken json');
    await File('${directory.path}/session.json.previous')
        .writeAsString(jsonEncode(backupSession.toJson()));
    await File(backupSession.rawPath).writeAsBytes([1, 2, 3]);

    await service.initialize(root.path);

    expect(service.sessions.map((session) => session.id), ['backup-session']);
    expect(service.sessions.single.roomTitle, 'Recovered from backup');
    expect(service.sessions.single.status, RecordingStatus.interrupted);
    expect(await File(backupSession.rawPath).exists(), isTrue);
  });

  test('shutdown is idempotent, releases source, and does not auto-export',
      () async {
    await service.start(request(RecordingMode.videoWithDanmaku));
    final firstShutdown = service.shutdown();
    final secondShutdown = service.shutdown();

    expect(identical(firstShutdown, secondShutdown), isTrue);
    await firstShutdown;
    await secondShutdown;

    expect(source.stops, 1);
    expect(source.releases, 1);
    expect(backend.remuxes, 0);
    expect(service.sessions.single.status, RecordingStatus.ready);
    expect(await File(service.sessions.single.rawPath).exists(), isTrue);
    await expectLater(service.start(request()), throwsStateError);
    await expectLater(
        service.exportSession(service.sessions.single.id), throwsStateError);
  });

  test('stop retains source owner after release failure and retries it',
      () async {
    await service.start(request());
    source.releaseFailures = 1;

    await expectLater(service.stop(), throwsStateError);

    expect(source.releases, 1);
    expect(service.isRecording, isFalse);
    expect(service.ownsSource(source), isTrue);
    expect(service.sessions.single.status, RecordingStatus.failed);
    await expectLater(service.start(request()), throwsStateError);
    await expectLater(
        service.initialize('${root.path}-other'), throwsStateError);

    await service.stop();
    expect(source.releases, 2);
    expect(service.ownsSource(source), isFalse);
    await service.start(request());
    expect(service.isRecording, isTrue);
    await service.stop();
  });

  test('source ownership is visible while startup is still in flight',
      () async {
    source.startGate = Completer<void>();
    final starting = service.start(request());
    await source.startInvoked.future;

    expect(source.starts, 1);
    expect(service.ownsSource(source), isTrue);
    final stopping = service.stop();
    source.startGate!.complete();
    await starting;
    await stopping;
    expect(service.ownsSource(source), isFalse);
  });

  test('start cleanup retains source owner after release failure', () async {
    source.failStart = true;
    source.releaseFailures = 1;

    await expectLater(service.start(request()), throwsStateError);

    expect(source.releases, 1);
    expect(service.isRecording, isFalse);
    expect(service.ownsSource(source), isTrue);
    await expectLater(service.start(request()), throwsStateError);
    await expectLater(
        service.initialize('${root.path}-other'), throwsStateError);

    await service.stop();
    expect(source.releases, 2);
    expect(service.ownsSource(source), isFalse);
    source.failStart = false;
    await service.start(request());
    expect(service.isRecording, isTrue);
  });

  test('shutdown can be retried after source release failure', () async {
    await service.start(request());
    source.releaseFailures = 1;

    await expectLater(service.shutdown(), throwsStateError);
    expect(source.releases, 1);
    await expectLater(service.start(request()), throwsStateError);

    await service.shutdown();
    expect(source.releases, 2);
    await expectLater(service.shutdown(), completes);
  });

  test('shutdown waits for canceled export before returning', () async {
    await service.start(request());
    backend.gate = Completer<void>();
    backend.cancelGate = Completer<void>();
    backend.cancelStarted = Completer<void>();
    final stopping = service.stop();
    await stopping;
    await waitFor(service, RecordingStatus.exporting);

    var shutdownFinished = false;
    final shutdown = service.shutdown().then((_) => shutdownFinished = true);
    await backend.cancelStarted!.future;
    expect(shutdownFinished, isFalse);
    backend.cancelGate!.complete();
    await shutdown;

    expect(shutdownFinished, isTrue);
    expect(service.sessions.single.status, RecordingStatus.ready);
    expect(await File(service.sessions.single.rawPath).exists(), isTrue);
  });

  test('rapid background and foreground transitions requeue canceled export',
      () async {
    await service.start(request());
    backend.gate = Completer<void>();
    backend.remuxStarted = Completer<void>();
    await service.stop();
    await waitFor(service, RecordingStatus.exporting);
    await backend.remuxStarted!.future;

    service.setForeground(false);
    service.setForeground(true);
    backend.gate!.complete();
    await waitFor(service, RecordingStatus.complete);

    expect(backend.remuxes, 2);
    expect(service.sessions.single.status, RecordingStatus.complete);
  });

  test('session file leases exclude export and deletion and release on error',
      () async {
    await service.start(request());
    await service.stop();
    await waitFor(service, RecordingStatus.complete);
    final session = service.sessions.single;
    var leaseReached = false;

    await expectLater(
        service.withSessionFiles(session.id, (leased) async {
          leaseReached = true;
          await expectLater(
              service.exportSession(session.id), throwsStateError);
          await expectLater(
              service.deleteSession(session.id), throwsStateError);
          throw StateError('lease fixture');
        }),
        throwsStateError);

    expect(leaseReached, isTrue);
    await service.deleteSession(session.id);
    expect(service.sessions, isEmpty);
  });

  test('delete holds a file mutation lock before awaiting filesystem removal',
      () async {
    await service.start(request());
    await service.stop();
    await waitFor(service, RecordingStatus.complete);
    final session = service.sessions.single;

    final deleting = service.deleteSession(session.id);
    await expectLater(
        service.withSessionFiles(session.id, (_) async {}), throwsStateError);
    await deleting;
    expect(service.sessions, isEmpty);
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
