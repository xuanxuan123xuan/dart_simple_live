import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:simple_live_app/services/recording/mpv_recording_source.dart';
import 'package:simple_live_app/services/recording/recording_diagnostics.dart';
import 'package:simple_live_app/services/recording/recording_mpv_bridge.dart';
import 'package:simple_live_app/services/recording/recording_service.dart';

class _Platform extends PlatformPlayer {
  _Platform() : super(configuration: const PlayerConfiguration());
}

class _RejectedBridge implements RecordingMpvBridge {
  @override
  Future<void> command(List<String> command) async {
    if (command[1] == 'stream-record' && command.last.isNotEmpty) {
      throw const RecordingMpvError(-12, 'stream-record');
    }
  }

  @override
  Future<String> getProperty(String name) async => '';
  @override
  Future<void> drain() async {}
  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late RecordingDiagnostics previous;
  late RecordingDiagnostics diagnostics;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('recording-diagnostics-');
    previous = RecordingDiagnostics.instance;
    diagnostics =
        RecordingDiagnostics(supportDirectoryProvider: () async => directory);
    RecordingDiagnostics.instance = diagnostics;
    file = File('${directory.path}/log/recording.log');
  });
  tearDown(() async {
    await diagnostics.flush();
    RecordingDiagnostics.instance = previous;
    await directory.delete(recursive: true);
  });

  Future<List<Map<String, dynamic>>> events() async {
    await diagnostics.flush();
    return (await file.readAsLines())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
  }

  test('early stages are persisted in order without enabling the app logger',
      () async {
    final opening = Completer<Directory>();
    diagnostics =
        RecordingDiagnostics(supportDirectoryProvider: () => opening.future);
    diagnostics.write('directory');
    diagnostics.write('native.failed',
        error: StateError('rejected'), stackTrace: StackTrace.current);
    var flushed = false;
    final flushing = diagnostics.flush().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);
    expect(flushed, isFalse);
    opening.complete(directory);
    await flushing;
    final logs = await events();
    expect(logs.map((event) => event['event']), ['directory', 'native.failed']);
    expect(logs.last['error'], contains('rejected'));
    expect(logs.last['stack'], contains('recording_diagnostics_test.dart'));
  });

  test('write failures are observed and the next event retries', () async {
    var available = false;
    diagnostics = RecordingDiagnostics(supportDirectoryProvider: () async {
      if (!available) throw const FileSystemException('disk unavailable');
      return directory;
    });
    diagnostics.write('first');
    await diagnostics.flush();
    available = true;
    diagnostics.write('retry');
    expect((await events()).single['event'], 'retry');
  });

  test('rotation keeps only a current file and one previous file', () async {
    diagnostics = RecordingDiagnostics(
        supportDirectoryProvider: () async => directory, maxFileBytes: 1);
    for (final event in ['first', 'second', 'third']) {
      diagnostics.write(event);
    }
    expect((await events()).single['event'], 'third');
    final backup = File('${file.path}.previous.log');
    expect(jsonDecode(await backup.readAsString())['event'], 'second');
    expect(
        await directory
            .list(recursive: true)
            .where((entry) => entry is File)
            .length,
        2);
  });

  test('native error details redact stream credentials and bound long output',
      () async {
    diagnostics.write('native.failed', data: {
      'nativeCode': -12,
      'message':
          'Cannot open https://example.test/live?token=secret Cookie: session=secret',
      'longOutput': List.filled(10000, 'x').join(),
    });
    final log = (await events()).single;
    expect(log['nativeCode'], -12);
    expect(log['message'], contains('<stream-url>'));
    expect(await file.readAsString(), isNot(contains('secret')));
    expect((log['longOutput'] as String).length, lessThan(4200));
  });

  test('failure before a session exists still saves the original reason',
      () async {
    final platform = _Platform();
    final source = MpvRecordingSource(Player(platformPlayer: platform),
        bridge: _RejectedBridge(), captureTimeline: false);
    final service = RecordingService();
    try {
      await expectLater(
          service.start(RecordingStartRequest(
            roomId: 'test',
            roomTitle: 'test',
            platform: 'test',
            mode: RecordingMode.videoOnly,
            source: source,
          )),
          throwsStateError);
      final failure = (await events()).last;
      expect(failure['event'], 'service.start.failed');
      expect(failure['error'], contains('not initialized'));
      expect(failure['stack'], contains('recording_service.dart'));
    } finally {
      await service.shutdown();
      service.dispose();
      await platform.dispose();
    }
  });

  test('directory rejection records the failed destination and OS error',
      () async {
    final blocked = File('${directory.path}/blocked');
    await blocked.writeAsString('not a directory');
    final service = RecordingService();
    try {
      await expectLater(service.initialize(blocked.path),
          throwsA(isA<FileSystemException>()));
      final failure = (await events()).last;
      expect(failure['event'], 'service.directory.failed');
      expect(failure['directory'], p.normalize(p.absolute(blocked.path)));
      expect(failure['errorType'], isNotEmpty);
      expect(failure['error'], contains('blocked'));
    } finally {
      await service.shutdown();
      service.dispose();
    }
  });

  test('native start rejection saves its phase and actual mpv return code',
      () async {
    final platform = _Platform();
    final source = MpvRecordingSource(Player(platformPlayer: platform),
        bridge: _RejectedBridge(), captureTimeline: false);
    try {
      await expectLater(source.start('${directory.path}/raw.mkv'),
          throwsA(isA<RecordingMpvError>()));
      final failure = (await events())
          .singleWhere((event) => event['event'] == 'mpv.command.failed');
      expect(failure['phase'], '开始写入录制');
      expect(failure['nativeCode'], -12);
      expect(failure['rawPath'], endsWith('raw.mkv'));
      expect(failure['stack'], isNotEmpty);
    } finally {
      await source.release();
      await platform.dispose();
    }
  });
}
