import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/android_video_diagnostic_service.dart';

void main() {
  group('AndroidVideoDiagnosticService', () {
    testWidgets('samples immediately and every five seconds, then stops',
        (tester) async {
      final lines = <String>[];
      var generation = 3;
      var enabled = true;
      final service = AndroidVideoDiagnosticService(
        readLocalSnapshot: () => const {
          'playing': true,
          'buffering': false,
          'videoTrackCount': 1,
          'audioTrackCount': 1,
          'sourceWidth': 1920,
          'sourceHeight': 1080,
          'outputWidth': 1280,
          'outputHeight': 720,
          'textureId': 0,
          'wid': 17,
          'url': 'https://private.example/stream',
        },
        readNativeProperty: (property) async => switch (property) {
          'current-vo' => 'gpu',
          'wid' => '17',
          'hwdec-current' => 'mediacodec-copy',
          'video-codec' => 'h264',
          'estimated-vf-fps' => '59.94',
          _ => null,
        },
        write: lines.add,
        flush: () async {},
        readGeneration: () => generation,
        isLogEnabled: () => enabled,
      );

      service.setEnabled(true);
      await tester.pump();
      expect(lines, hasLength(1));
      final first =
          jsonDecode(lines.single.substring('[android-video] '.length))
              as Map<String, dynamic>;
      expect(first['event'], 'snapshot');
      expect(first['generation'], 3);
      expect(first['textureId'], 0);
      expect(first['videoTrackCount'], 1);
      expect(first['audioTrackCount'], 1);
      expect(first['sourceWidth'], 1920);
      expect(first['sourceHeight'], 1080);
      expect(first['outputWidth'], 1280);
      expect(first['outputHeight'], 720);
      expect(first['current-vo'], 'gpu');
      expect(first['renderConfirmed'], 'unknown');
      expect(first.containsKey('url'), isFalse);

      await tester.pump(const Duration(seconds: 4));
      expect(lines, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(lines, hasLength(2));

      enabled = false;
      service.setEnabled(false);
      await tester.pump(const Duration(seconds: 10));
      expect(lines, hasLength(2));
      service.dispose();
    });

    testWidgets('resuming samples immediately without waiting for the timer',
        (tester) async {
      final lines = <String>[];
      final service = AndroidVideoDiagnosticService(
        readLocalSnapshot: () => const {'playing': true},
        readNativeProperty: (_) async => 'gpu',
        write: lines.add,
        flush: () async {},
        readGeneration: () => 2,
        isLogEnabled: () => true,
      );

      service.setEnabled(true);
      await tester.pump();
      expect(lines, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      service.onAppResumed();
      await tester.pump();
      expect(lines, hasLength(2));
      service.dispose();
    });

    testWidgets(
        'teardown generation records cleanup and dispose without samples',
        (tester) async {
      final lines = <String>[];
      final pending = Completer<Object?>();
      var generation = 2;
      final service = AndroidVideoDiagnosticService(
        readLocalSnapshot: () => const {},
        readNativeProperty: (_) => pending.future,
        write: lines.add,
        flush: () async {},
        readGeneration: () => generation,
        isLogEnabled: () => true,
        nativePropertyTimeout: const Duration(milliseconds: 20),
      );

      service.setEnabled(true);
      service.stopSamplingForClose();
      generation += 1;
      service.updateGeneration(generation);
      service.recordNativeEvent(
        'surface_cleanup',
        const {'handle': 123, 'surfaceIdentity': 45},
        generation: generation,
      );
      service.recordNativeEvent('dispose', const {'handle': 123},
          generation: generation);
      pending.complete('gpu');
      await tester.pump(const Duration(seconds: 6));
      expect(lines, hasLength(2));
      expect(lines.first, contains('"event":"surface_cleanup"'));
      expect(lines.first, contains('"surfaceIdentity":45'));
      expect(lines.last, contains('"event":"dispose"'));
      expect(lines.every((line) => line.contains('"generation":3')), isTrue);
      service.dispose();
    });

    testWidgets('restart drops old same-generation results and samples now',
        (tester) async {
      final lines = <String>[];
      final stale = Completer<Object?>();
      final readCounts = <String, int>{};
      var useStaleRead = true;
      var enabled = true;
      final service = AndroidVideoDiagnosticService(
        readLocalSnapshot: () => const {'playing': true},
        readNativeProperty: (property) {
          readCounts.update(property, (count) => count + 1, ifAbsent: () => 1);
          if (property == 'current-vo' && useStaleRead) {
            return stale.future;
          }
          return Future<Object?>.value('gpu');
        },
        write: lines.add,
        flush: () async {},
        readGeneration: () => 6,
        isLogEnabled: () => enabled,
        nativePropertyTimeout: const Duration(milliseconds: 600),
      );

      service.setEnabled(true);
      enabled = false;
      service.setEnabled(false);
      useStaleRead = false;
      enabled = true;
      service.setEnabled(true);
      await tester.pump();
      expect(lines, hasLength(1));
      final fresh =
          jsonDecode(lines.single.substring('[android-video] '.length))
              as Map<String, dynamic>;
      expect(fresh['generation'], 6);
      expect(fresh['current-vo'], 'unknown');
      expect(readCounts['current-vo'], 1);

      stale.complete('stale-vo');
      await tester.pump();
      await service.sampleNow();
      expect(lines, hasLength(2));
      final next = jsonDecode(lines.last.substring('[android-video] '.length))
          as Map<String, dynamic>;
      expect(next['current-vo'], 'gpu');
      expect(readCounts['current-vo'], 2);
      service.dispose();
    });

    testWidgets('drops an old generation sample and samples the new one',
        (tester) async {
      final lines = <String>[];
      final pending = <String, Completer<Object?>>{};
      var generation = 4;
      final service = AndroidVideoDiagnosticService(
        readLocalSnapshot: () => {'playing': true},
        readNativeProperty: (property) {
          return (pending[property] ??= Completer<Object?>()).future;
        },
        write: lines.add,
        flush: () async {},
        readGeneration: () => generation,
        isLogEnabled: () => true,
        nativePropertyTimeout: const Duration(milliseconds: 20),
      );

      service.setEnabled(true);
      generation = 5;
      service.updateGeneration(generation);
      await tester.pump(const Duration(milliseconds: 40));

      final snapshots = lines
          .map((line) => jsonDecode(line.substring('[android-video] '.length)))
          .whereType<Map<String, dynamic>>()
          .toList();
      expect(snapshots, isNotEmpty);
      expect(snapshots.every((item) => item['generation'] == 5), isTrue);

      service.dispose();
      for (final completer in pending.values) {
        completer.complete('unknown');
      }
    });

    testWidgets('times out native properties without overlapping reads',
        (tester) async {
      final lines = <String>[];
      final pending = <String, Completer<Object?>>{};
      final readCounts = <String, int>{};
      final service = AndroidVideoDiagnosticService(
        readLocalSnapshot: () => const {
          'playing': true,
          'buffering': false,
          'textureId': 1,
        },
        readNativeProperty: (property) {
          readCounts.update(property, (count) => count + 1, ifAbsent: () => 1);
          return (pending[property] ??= Completer<Object?>()).future;
        },
        write: lines.add,
        flush: () async {},
        readGeneration: () => 9,
        isLogEnabled: () => true,
        nativePropertyTimeout: const Duration(milliseconds: 20),
      );

      service.setEnabled(true);
      await tester.pump(const Duration(milliseconds: 20));
      expect(lines, hasLength(1));
      final first =
          jsonDecode(lines.single.substring('[android-video] '.length))
              as Map<String, dynamic>;
      expect(first['playing'], isTrue);
      expect(first['current-vo'], 'unknown');
      expect(readCounts.values, everyElement(1));

      unawaited(service.sampleNow());
      await tester.pump(const Duration(milliseconds: 20));
      expect(lines, hasLength(2));
      expect(readCounts.values, everyElement(1));

      service.dispose();
      for (final completer in pending.values) {
        completer.complete('gpu');
      }
    });

    testWidgets(
        'filters sensitive callback fields and contains writer failures',
        (tester) async {
      final lines = <String>[];
      final service = AndroidVideoDiagnosticService(
        readLocalSnapshot: () => const {},
        readNativeProperty: (_) async => 'unknown',
        write: lines.add,
        flush: () async {},
        readGeneration: () => 12,
        isLogEnabled: () => true,
      );
      service.setEnabled(true);
      await tester.pump();
      lines.clear();

      service.recordNativeEvent(
        'bind_error',
        const {
          'handle': '42',
          'surfaceIdentity': 9001,
          'bindRevision': 7,
          'reason': 'https://private.example/path?token=secret',
          'error': 'IllegalStateException',
          'vo': 'gpu',
          'hwdec': 'auto-safe',
          'cookie': 'session=secret',
          'url': 'https://private.example/stream',
        },
        generation: 12,
      );
      await tester.pump();

      expect(lines, hasLength(1));
      expect(lines.single, contains('IllegalStateException'));
      expect(lines.single, contains('"handle":42'));
      expect(lines.single, contains('"reason":"unknown"'));
      expect(lines.single, contains('"vo":"gpu"'));
      expect(lines.single, contains('"hwdec":"auto-safe"'));
      expect(lines.single, isNot(contains('private.example')));
      expect(lines.single, isNot(contains('session=secret')));
      service.recordNativeEvent(
        'surface_publish',
        const {
          'handle': 42,
          'textureId': 0,
          'surfaceIdentity': 9001,
          'bindRevision': 8,
          'oldWid': 7,
          'wid': 0,
          'width': 1280,
          'height': 720,
          'valid': true,
          'reason': 'surface_ready',
          'level': 'info',
        },
        generation: 12,
      );
      service.recordNativeEvent(
        'bind_complete',
        const {'wid': 0},
        generation: 12,
      );
      await service.sampleNow();
      final snapshot =
          jsonDecode(lines.last.substring('[android-video] '.length))
              as Map<String, dynamic>;
      expect(snapshot['bindState'], 'unbound');
      expect(snapshot['lastNativeTextureId'], 0);
      expect(snapshot['lastNativeSurfaceIdentity'], 9001);
      expect(snapshot['lastNativeBindRevision'], 8);
      expect(snapshot['lastNativeOldWid'], 7);
      expect(snapshot['lastNativeWidth'], 1280);
      expect(snapshot['lastNativeHeight'], 720);
      expect(snapshot['renderConfirmed'], 'unknown');
      service.dispose();

      final throwingService = AndroidVideoDiagnosticService(
        readLocalSnapshot: () => const {},
        readNativeProperty: (_) async => null,
        write: (_) => throw StateError('test sink failure'),
        flush: () async => throw StateError('test flush failure'),
        readGeneration: () => 1,
        isLogEnabled: () => true,
      );
      throwingService.setEnabled(true);
      expect(
        () => throwingService.recordNativeEvent(
          'init',
          const {},
          generation: 1,
        ),
        returnsNormally,
      );
      await tester.pump();
      throwingService.dispose();
    });
  });
}
