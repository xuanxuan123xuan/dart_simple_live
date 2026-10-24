import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:simple_live_app/modules/live_room/live_room_recording_coordinator.dart';
import 'package:simple_live_app/services/recording/recording_service.dart';

class _UnusedContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backend implements RecordingBackend {
  @override
  Future<RecordingMediaInfo> probe(String path) async =>
      const RecordingMediaInfo(
          duration: Duration(seconds: 5),
          width: 320,
          height: 180,
          videoCodec: 'h264',
          audioCodec: 'aac');
  @override
  Future<void> cancel() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Source implements RecordingSource, RecordingSourceLifetime {
  _Source(this.onError, this.gate);
  final void Function(Object, StackTrace) onError;
  final Completer<void>? gate;
  int stops = 0;
  int releaseFailures = 0;
  int releases = 0;
  @override
  Future<void> start(String path) async {
    await gate?.future;
    await File(path).writeAsBytes([1]);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<Duration> mediaPosition() async => const Duration(seconds: 5);
  @override
  Future<RecordingTimeline?> timeline() async => null;
  @override
  Future<void> release() async {
    releases++;
    if (releaseFailures > 0) {
      releaseFailures--;
      throw StateError('Native cleanup has not completed');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late RecordingService service;
  late LiveRoomRecordingCoordinator room;
  late List<_Source> sources;
  late StreamController<bool> playingChanges;
  late bool playing;
  late String roomId;
  Completer<void>? startGate;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('recording-coordinator-');
    service = RecordingService(backend: _Backend());
    await service.initialize(directory.path);
    service.setForeground(false);
    sources = [];
    playing = true;
    roomId = 'one';
    startGate = null;
    playingChanges = StreamController<bool>.broadcast(sync: true);
    room = LiveRoomRecordingCoordinator(
      player: () =>
          throw StateError('Native player must not be used by these tests'),
      roomId: () => roomId,
      roomTitle: () => 'room',
      platform: () => 'test',
      canRecord: () => playing,
      danmakuVisible: () => true,
      service: service,
      isPlaying: () => playing,
      playingChanges: () => playingChanges.stream,
      mediaPosition: () => const Duration(seconds: 5),
      showMessage: (_) {},
      sourceFactory: (_, onError) {
        final source = _Source(onError, startGate);
        sources.add(source);
        return source;
      },
    );
  });

  tearDown(() async {
    startGate?.complete();
    await room.close();
    await service.shutdown();
    service.dispose();
    await playingChanges.close();
    await directory.delete(recursive: true);
  });

  test('manual cancellation during resume wait cannot start another segment',
      () async {
    await room.start(RecordingMode.videoOnly);
    await room.suspendForPlayerMutation(resumeAfterMutation: true);
    playing = false;
    final resuming = room.resumeAfterPlayerMutation();
    expect(room.busy, isTrue);
    final stopping = room.stop();
    playing = true;
    await Future.wait([resuming, stopping]);
    expect(sources, hasLength(1));
    expect(room.requested, isFalse);
    expect(service.isRecording, isFalse);
  });

  test(
      'leaving during resume wait closes once and cannot access disposed player',
      () async {
    await room.start(RecordingMode.videoOnly);
    await room.suspendForPlayerMutation(resumeAfterMutation: true);
    playing = false;
    final resuming = room.resumeAfterPlayerMutation();
    final closing = room.close();
    expect(identical(closing, room.close()), isTrue);
    playing = true;
    await Future.wait([resuming, closing]);
    expect(sources, hasLength(1));
    expect(service.isRecording, isFalse);
  });

  test('stop waits for source start but invalidates its intent immediately',
      () async {
    startGate = Completer<void>();
    final starting = room.start(RecordingMode.videoOnly);
    while (sources.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final stopping = room.stop();
    expect(room.requested, isFalse);
    expect(sources.single.stops, 0);
    startGate!.complete();
    startGate = null;
    await Future.wait([starting, stopping]);
    expect(sources.single.stops, 1);
    expect(service.isRecording, isFalse);
  });

  test('repeated recoverable mutations produce only one resumed segment',
      () async {
    await room.start(RecordingMode.videoOnly);
    await Future.wait([
      room.suspendForPlayerMutation(resumeAfterMutation: true),
      room.suspendForPlayerMutation(resumeAfterMutation: true),
    ]);
    await Future.wait(
        [room.resumeAfterPlayerMutation(), room.resumeAfterPlayerMutation()]);
    expect(sources, hasLength(2));
    expect(sources.first.stops, 1);
    expect(room.active, isTrue);
  });

  test('room identity change invalidates a suspended recording', () async {
    await room.start(RecordingMode.videoOnly);
    await room.suspendForPlayerMutation(resumeAfterMutation: true);
    roomId = 'two';
    await room.resumeAfterPlayerMutation();
    expect(sources, hasLength(1));
    expect(service.isRecording, isFalse);
  });

  test('late old-source error cannot stop the next segment', () async {
    await room.start(RecordingMode.videoOnly);
    final previous = sources.single;
    await room.stop();
    await room.start(RecordingMode.videoOnly);
    previous.onError(StateError('old native error'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);
    expect(room.active, isTrue);
    expect(sources.last.stops, 0);
  });
  test('failed close keeps native ownership and can retry the close barrier',
      () async {
    await room.start(RecordingMode.videoOnly);
    final source = sources.single;
    source.releaseFailures = 1;
    await expectLater(room.close(), throwsStateError);
    expect(service.ownsSource(source), isTrue);
    await room.close();
    expect(service.ownsSource(source), isFalse);
    expect(source.releases, 2);
  });
  test('manual UI stop handles cleanup failure and can be retried', () async {
    await room.start(RecordingMode.videoOnly);
    final source = sources.single;
    source.releaseFailures = 1;
    await room.toggle(_UnusedContext());
    expect(room.requested, isTrue);
    expect(service.ownsSource(source), isTrue);
    await room.toggle(_UnusedContext());
    expect(room.requested, isFalse);
    expect(service.ownsSource(source), isFalse);
  });
}
