import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/services/recording/mpv_recording_source.dart';
import 'package:simple_live_app/services/recording/recording_mpv_bridge.dart';

class _Platform extends PlatformPlayer {
  _Platform() : super(configuration: const PlayerConfiguration());
  void emitLog(PlayerLog log) => logController.add(log);
}

class _Bridge implements RecordingMpvBridge {
  final commands = <List<String>>[];
  final pending = <Future<void>>[];
  Future<void> Function(List<String>)? handler;
  Future<String> Function(String)? propertyHandler;
  bool closed = false;
  int drainFailures = 0;
  int closeFailures = 0;
  @override
  Future<void> command(List<String> command) async {
    commands.add(command);
    final operation = handler?.call(command) ?? Future<void>.value();
    pending.add(operation);
    try {
      await operation;
      if (command.length == 3 &&
          command[1] == 'stream-record' &&
          command[2].isNotEmpty) {
        await File(command[2]).writeAsBytes([1, 2, 3]);
      }
    } finally {
      pending.remove(operation);
    }
  }

  @override
  Future<String> getProperty(String name) async =>
      propertyHandler == null ? '' : await propertyHandler!(name);
  @override
  Future<void> drain() async {
    if (drainFailures > 0) {
      drainFailures--;
      throw StateError('transient drain failure');
    }
    while (pending.isNotEmpty) {
      await Future.wait(pending
          .map((future) =>
              future.then<void>((_) {}, onError: (Object _, StackTrace __) {}))
          .toList());
    }
  }

  @override
  Future<void> close() async {
    if (closeFailures > 0) {
      closeFailures--;
      throw StateError('transient close failure');
    }
    await drain();
    closed = true;
  }
}

void main() {
  late Directory directory;
  late _Bridge bridge;
  late MpvRecordingSource source;
  late _Platform platform;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('recording-lifecycle-');
    bridge = _Bridge();
    platform = _Platform();
    source = MpvRecordingSource(Player(platformPlayer: platform),
        captureTimeline: false,
        bridge: bridge,
        nativeOperationTimeout: const Duration(seconds: 3));
  });
  tearDown(() async {
    await platform.dispose();
    await directory.delete(recursive: true);
  });

  String metadata() => jsonEncode({
        'fp0.pts': '1.0',
        'fp0.hex': List.filled(512, 'a').join(),
      });

  MpvRecordingSource timelineSource(
          {void Function(Object, StackTrace)? onError}) =>
      MpvRecordingSource(Player(platformPlayer: platform),
          bridge: bridge, onError: onError);

  test(
      'timeline readiness waits for a real frame and cleans both owned filters',
      () async {
    final queried = Completer<void>();
    final frames = Completer<String>();
    bridge.propertyHandler = (name) {
      if (!queried.isCompleted) queried.complete();
      return frames.future;
    };
    source = timelineSource();
    final starting = source.start('${directory.path}/raw.mkv');
    await queried.future;
    expect(source.state, MpvRecordingState.starting);
    frames.complete(metadata());
    await starting;
    expect(source.state, MpvRecordingState.recording);
    expect(bridge.commands.take(2), [
      ['vf', 'add', '@simplelive_capture_pixels:format=fmt=yuv420p'],
      ['vf', 'add', '@simplelive_recording:fingerprint=clear-on-query=no'],
    ]);
    await source.stop();
    expect(bridge.commands.skip(bridge.commands.length - 2), [
      ['vf', 'remove', '@simplelive_recording'],
      ['vf', 'remove', '@simplelive_capture_pixels'],
    ]);
    await source.release();
  });

  test('a late first fingerprint cannot complete a cancelled start', () async {
    final queried = Completer<void>();
    final frames = Completer<String>();
    bridge.propertyHandler = (_) {
      if (!queried.isCompleted) queried.complete();
      return frames.future;
    };
    source = timelineSource();
    final starting = source.start('${directory.path}/raw.mkv');
    await queried.future;
    final stopping = source.stop();
    final rejected = expectLater(starting, throwsStateError);
    frames.complete(metadata());
    await rejected;
    await stopping;
    expect(source.state, isNot(MpvRecordingState.recording));
    await source.release();
    expect(bridge.closed, isTrue);
  });

  test(
      'asynchronous format rejection during add is observed before stream attach',
      () async {
    final errors = <Object>[];
    source = timelineSource(onError: (error, _) => errors.add(error));
    bridge.handler = (command) async {
      if (command[1] == 'add' && command.last.contains('format=fmt=')) {
        platform.emitLog(const PlayerLog(
            prefix: 'vf',
            level: 'error',
            text:
                'Disabling filter simplelive_capture_pixels because it has failed.'));
        await Future<void>.delayed(Duration.zero);
      }
    };
    await expectLater(
        source.start('${directory.path}/raw.mkv'), throwsStateError);
    expect(errors.single.toString(), contains('时间轴采样失败'));
    expect(bridge.commands.where((command) => command[1] == 'stream-record'),
        isEmpty);
    expect(
        bridge.commands.last, ['vf', 'remove', '@simplelive_capture_pixels']);
    await source.release();
  });

  test(
      'fingerprint format failure after command acceptance cannot report ready',
      () async {
    source = timelineSource();
    bridge.handler = (command) async {
      if (command[1] == 'add' && command.last.contains(':fingerprint=')) {
        platform.emitLog(const PlayerLog(
            prefix: 'fingerprint',
            level: 'error',
            text: 'unsupported video format'));
        await Future<void>.delayed(Duration.zero);
      }
    };
    await expectLater(
        source.start('${directory.path}/raw.mkv'), throwsStateError);
    expect(source.state, MpvRecordingState.failed);
    expect(bridge.commands.where((command) => command[1] == 'stream-record'),
        isEmpty);
    expect(bridge.commands.skip(bridge.commands.length - 2), [
      ['vf', 'remove', '@simplelive_recording'],
      ['vf', 'remove', '@simplelive_capture_pixels'],
    ]);
    await source.release();
  });

  test(
      'pixel adapter cleanup failure retains ownership until a successful retry',
      () async {
    bridge.propertyHandler =
        (name) async => name == 'vf' ? 'simplelive_capture_pixels' : metadata();
    source = timelineSource();
    await source.start('${directory.path}/raw.mkv');
    var reject = true;
    bridge.handler = (command) async {
      if (command[1] == 'remove' &&
          command.last == '@simplelive_capture_pixels' &&
          reject) {
        throw const RecordingMpvError(-12, 'remove format');
      }
    };
    await expectLater(source.stop(), throwsA(isA<RecordingMpvError>()));
    expect(source.state, MpvRecordingState.failed);
    expect(bridge.closed, isFalse);
    reject = false;
    await source.release();
    expect(bridge.closed, isTrue);
    expect(
        bridge.commands
            .where((command) => command.last == '@simplelive_recording'),
        hasLength(1));
    expect(
        bridge.commands
            .where((command) => command.last == '@simplelive_capture_pixels'),
        hasLength(2));
  });

  const experimentalNotice = PlayerLog(
      prefix: 'recorder',
      level: 'warn',
      text: 'This is an experimental feature. Output files might be broken or '
          'not play correctly with various players (including mpv itself).');

  test(
      'startup notice before the native reply does not reject a successful start',
      () async {
    bridge.handler = (command) async {
      if (command[1] == 'stream-record' && command.last.isNotEmpty) {
        platform.emitLog(experimentalNotice);
        await Future<void>.delayed(Duration.zero);
      }
    };
    await source.start('${directory.path}/raw.mkv');
    expect(source.state, MpvRecordingState.recording);
    await source.stop();
    await source.release();
    expect(bridge.closed, isTrue);
  });

  test('a real write failure after the notice still reaches the error callback',
      () async {
    final errors = <Object>[];
    source = MpvRecordingSource(Player(platformPlayer: platform),
        bridge: bridge,
        captureTimeline: false,
        onError: (error, _) => errors.add(error));
    await source.start('${directory.path}/raw.mkv');
    platform.emitLog(experimentalNotice);
    await Future<void>.delayed(Duration.zero);
    expect(errors, isEmpty);
    platform.emitLog(const PlayerLog(
        prefix: 'recorder',
        level: 'warn',
        text: 'Error writing packet: No space left on device'));
    await Future<void>.delayed(Duration.zero);
    expect(errors.single.toString(), contains('No space left on device'));
    await expectLater(source.stop(), throwsStateError);
    await source.release();
  });

  test('stop rejection remains failed and release retries detach', () async {
    await source.start('${directory.path}/raw.mkv');
    var reject = true;
    bridge.handler = (command) async {
      if (command.last.isEmpty && reject) {
        throw const RecordingMpvError(-12, 'detach');
      }
    };
    await expectLater(source.stop(), throwsA(isA<RecordingMpvError>()));
    expect(source.state, MpvRecordingState.failed);
    await expectLater(
        source.start('${directory.path}/other.mkv'), throwsStateError);
    expect(bridge.closed, isFalse);
    reject = false;
    await source.release();
    expect(
        bridge.commands.where((command) => command.last.isEmpty), hasLength(2));
    expect(bridge.closed, isTrue);
  });

  test('release retries drain failure without releasing its owner', () async {
    await source.start('${directory.path}/raw.mkv');
    bridge.drainFailures = 1;
    await expectLater(source.release(), throwsStateError);
    expect(bridge.closed, isFalse);
    expect(source.state, MpvRecordingState.failed);
    await expectLater(
        source.start('${directory.path}/other.mkv'), throwsStateError);
    await source.release();
    expect(bridge.commands.last, ['set', 'stream-record', '']);
    expect(bridge.closed, isTrue);
  });

  test('release retries close failure after detach without false completion',
      () async {
    await source.start('${directory.path}/raw.mkv');
    bridge.closeFailures = 1;
    await expectLater(source.release(), throwsStateError);
    expect(bridge.closed, isFalse);
    expect(source.state, MpvRecordingState.failed);
    await source.release();
    expect(
        bridge.commands.where((command) => command.last.isEmpty), hasLength(1));
    expect(bridge.closed, isTrue);
  });

  test('reentrant stop sends only one detach and closes after completion',
      () async {
    await source.start('${directory.path}/raw.mkv');
    final detached = Completer<void>();
    bridge.handler =
        (command) => command.last.isEmpty ? detached.future : Future.value();
    final first = source.stop();
    final second = source.stop();
    expect(identical(first, second), isTrue);
    detached.complete();
    await Future.wait([first, second]);
    expect(
        bridge.commands.where((command) => command.last.isEmpty), hasLength(1));
    await source.release();
    expect(bridge.closed, isTrue);
  });

  test('late attach cannot escape timeout then release barrier', () async {
    var protectedDepth = 0;
    source = MpvRecordingSource(Player(platformPlayer: platform),
        captureTimeline: false,
        bridge: bridge,
        nativeOperationTimeout: const Duration(milliseconds: 30),
        protectNativeMutation: (operation) async {
      protectedDepth++;
      try {
        await operation();
      } finally {
        protectedDepth--;
      }
    });
    final attached = Completer<void>();
    bridge.handler =
        (command) => command.last.isNotEmpty ? attached.future : Future.value();
    final starting = source.start('${directory.path}/raw.mkv');
    await expectLater(starting, throwsA(isA<TimeoutException>()));
    expect(source.state, MpvRecordingState.failed);
    expect(protectedDepth, 1);
    var released = false;
    final releasing = source.release().then((_) => released = true);
    await Future<void>.delayed(Duration.zero);
    expect(released, isFalse);
    expect(bridge.closed, isFalse);
    attached.complete();
    await releasing;
    expect(bridge.commands.last, ['set', 'stream-record', '']);
    expect(bridge.closed, isTrue);
    expect(protectedDepth, 0);
  });

  test('release during start waits for attach then detaches without self-await',
      () async {
    final attached = Completer<void>();
    final commandSeen = Completer<void>();
    source = MpvRecordingSource(Player(platformPlayer: platform),
        captureTimeline: false, bridge: bridge);
    bridge.handler = (command) {
      if (command.last.isEmpty) return Future.value();
      commandSeen.complete();
      return attached.future;
    };
    final starting = source.start('${directory.path}/raw.mkv');
    await commandSeen.future;
    final releasing = source.release();
    attached.complete();
    await starting;
    await releasing;
    expect(bridge.commands.last, ['set', 'stream-record', '']);
    expect(bridge.closed, isTrue);
  });

  test('duplicate start rejection does not stop the active recorder', () async {
    await source.start('${directory.path}/raw.mkv');
    await expectLater(
        source.start('${directory.path}/other.mkv'), throwsStateError);
    expect(source.state, MpvRecordingState.recording);
    expect(bridge.commands, hasLength(1));
    await source.release();
  });
}
