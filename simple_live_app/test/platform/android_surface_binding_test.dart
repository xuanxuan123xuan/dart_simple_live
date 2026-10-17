import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/surface_binding.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

void main() {
  group('VideoControllerConfiguration diagnostics', () {
    test('copyWith preserves the diagnostic callback', () {
      void onDiagnostic(String event, Map<String, Object?> fields) {}

      final configuration = VideoControllerConfiguration(
        onDiagnostic: onDiagnostic,
      );

      expect(
          configuration.copyWith(hwdec: 'no').onDiagnostic, same(onDiagnostic));
    });
  });

  group('AndroidSurfaceBinding', () {
    test(
      'initializes with a safe 1x1 detached surface before wid arrives',
      () async {
        final writes = <String>[];
        final binding = _binding(writes);

        await binding.initialize(_initialProperties);

        expect(
          writes,
          [
            'vo=null',
            'gpu-context=android',
            'vo=null',
            'android-surface-size=1x1',
            'wid=0',
            'vo=null',
          ],
        );
        await binding.onLoad();
        expect(writes, isNot(contains('vo=gpu')));

        await binding.updateSurface(wid: 15, width: 640, height: 360);
        expect(writes.last, 'vo=gpu');
        expect(writes, contains('wid=15'));
      },
    );

    test('uses a surface received before initialization', () async {
      final writes = <String>[];
      final binding = _binding(writes);

      await binding.handleResize(
        wid: 27,
        width: 1280,
        height: 720,
        updateNotifiers: () {},
      );
      expect(writes, isEmpty);

      await binding.initialize(_initialProperties);

      expect(writes, contains('android-surface-size=1280x720'));
      expect(writes, contains('wid=27'));
      expect(writes.last, 'vo=gpu');
      await binding.onLoad();
      expect(writes.last, 'vo=gpu');
    });

    test('serializes external video parameter work with resize binding',
        () async {
      final events = <String>[];
      final enteredOperation = Completer<void>();
      final releaseOperation = Completer<void>();
      final binding = AndroidSurfaceBinding(
        writeProperty: (key, value) async {
          events.add('property:$key=$value');
        },
        vo: 'gpu',
        compatibilityMode: false,
      );
      await binding.initialize(_initialProperties);
      events.clear();

      final videoParams = binding.runExclusive(() async {
        events.add('video-params-start');
        enteredOperation.complete();
        await releaseOperation.future;
        events.add('video-params-end');
      });
      await enteredOperation.future;
      var notifierUpdated = false;
      final resize = binding.handleResize(
        wid: 62,
        width: 1280,
        height: 720,
        updateNotifiers: () {
          notifierUpdated = true;
          events.add('notifier-updated');
        },
      );
      expect(notifierUpdated, isFalse);

      releaseOperation.complete();
      await Future.wait([videoParams, resize]);

      expect(events, [
        'video-params-start',
        'video-params-end',
        'notifier-updated',
        'property:vo=null',
        'property:android-surface-size=1280x720',
        'property:wid=62',
        'property:vo=gpu',
      ]);
    });

    test(
      'serializes initialization and a resize queued during initialization',
      () async {
        final writes = <String>[];
        final enteredWriter = Completer<void>();
        final releaseWriter = Completer<void>();
        final binding = AndroidSurfaceBinding(
          writeProperty: (key, value) async {
            writes.add('$key=$value');
            if (key == 'gpu-context' && !enteredWriter.isCompleted) {
              enteredWriter.complete();
              await releaseWriter.future;
            }
          },
          vo: 'gpu',
          compatibilityMode: false,
        );

        final initializing = binding.initialize(_initialProperties);
        await enteredWriter.future;
        final resizing = binding.handleResize(
          wid: 44,
          width: 1920,
          height: 1080,
          updateNotifiers: () {},
        );
        releaseWriter.complete();
        await Future.wait([initializing, resizing]);

        final finalBinding = writes.sublist(writes.lastIndexOf('vo=null'));
        expect(finalBinding, [
          'vo=null',
          'android-surface-size=1920x1080',
          'wid=44',
          'vo=gpu',
        ]);
        await binding.onLoad();
        expect(writes.last, 'vo=gpu');
      },
    );

    test('detaches on wid zero and does not enable output from onLoad',
        () async {
      final writes = <String>[];
      final binding = _binding(writes);
      await binding.initialize(_initialProperties);
      await binding.updateSurface(wid: 8, width: 800, height: 450);
      final writesBeforeDetach = writes.length;

      await binding.updateSurface(wid: 0, width: 800, height: 450);
      await binding.onLoad();

      expect(
        writes.sublist(writesBeforeDetach),
        [
          'vo=null',
          'android-surface-size=800x450',
          'wid=0',
          'vo=null',
        ],
      );
    });

    test(
      'preserves mediacodec_embed vid behavior across attach and detach',
      () async {
        final writes = <String>[];
        final binding = _binding(
          writes,
          vo: 'mediacodec_embed',
          compatibilityMode: true,
        );
        await binding.initialize(_initialProperties);
        final writesBeforeAttach = writes.length;

        await binding.updateSurface(wid: 18, width: 1024, height: 576);
        expect(
          writes.sublist(writesBeforeAttach),
          [
            'vo=null',
            'android-surface-size=1024x576',
            'wid=18',
            'vo=mediacodec_embed',
            'vid=auto',
          ],
        );
        final writesBeforeDetach = writes.length;

        await binding.updateSurface(wid: 0, width: 1024, height: 576);
        expect(
          writes.sublist(writesBeforeDetach),
          [
            'vo=null',
            'android-surface-size=1024x576',
            'wid=0',
            'vo=null',
            'vid=no',
          ],
        );
      },
    );

    test('ignores callbacks and hooks after close', () async {
      final writes = <String>[];
      final binding = _binding(writes);
      var cleanupCount = 0;
      var exclusiveActionCount = 0;
      await binding.initialize(_initialProperties);
      final writeCountAtClose = writes.length;

      await binding.close(() async {
        cleanupCount++;
      });
      await binding.updateSurface(wid: 31, width: 640, height: 360);
      await binding.handleResize(
        wid: 32,
        width: 800,
        height: 450,
        updateNotifiers: () {},
      );
      await binding.initialize(_initialProperties);
      await binding.onLoad();
      await binding.onUnload();
      await binding.runExclusive(() async {
        exclusiveActionCount++;
      });
      await binding.close(() async {
        cleanupCount++;
      });

      expect(cleanupCount, 1);
      expect(exclusiveActionCount, 0);
      expect(writes, hasLength(writeCountAtClose));
    });

    test('reports close while ignoring a resize queued during cleanup',
        () async {
      final writes = <String>[];
      final diagnostics = <MapEntry<String, Map<String, Object?>>>[];
      final cleanupEntered = Completer<void>();
      final releaseCleanup = Completer<void>();
      final binding = AndroidSurfaceBinding(
        writeProperty: (key, value) async {
          writes.add('$key=$value');
        },
        vo: 'gpu',
        compatibilityMode: false,
        onDiagnostic: (event, fields) {
          diagnostics.add(MapEntry(event, fields));
        },
      );
      await binding.initialize(_initialProperties);
      final writesBeforeClose = writes.length;
      final close = binding.close(() async {
        cleanupEntered.complete();
        await releaseCleanup.future;
      });
      await cleanupEntered.future;

      var notifierUpdated = false;
      final lateResize = binding.handleResize(
        wid: 72,
        width: 1280,
        height: 720,
        updateNotifiers: () {
          notifierUpdated = true;
        },
      );
      releaseCleanup.complete();
      await Future.wait([close, lateResize]);

      expect(notifierUpdated, isFalse);
      expect(writes, hasLength(writesBeforeClose));
      expect(
        diagnostics
            .where((entry) => entry.key == 'dispose')
            .map((entry) => entry.value['stage']),
        ['closing', 'closed'],
      );
      expect(
        diagnostics.where((entry) => entry.key == 'texture_update'),
        isEmpty,
      );
    });

    test('continues serialized work after a property writer failure', () async {
      final writes = <String>[];
      final diagnostics = <MapEntry<String, Map<String, Object?>>>[];
      var failOnce = true;
      final binding = AndroidSurfaceBinding(
        writeProperty: (key, value) async {
          writes.add('$key=$value');
          if (key == 'wid' && value == '0' && failOnce) {
            failOnce = false;
            throw StateError('synthetic property failure');
          }
        },
        vo: 'gpu',
        compatibilityMode: false,
        onDiagnostic: (event, fields) {
          diagnostics.add(MapEntry(event, fields));
        },
      );

      await expectLater(
        binding.initialize(_initialProperties),
        throwsA(isA<StateError>()),
      );
      final writesAfterFailure = writes.length;
      await binding.onLoad();
      expect(writes, hasLength(writesAfterFailure));

      var exclusiveActionRan = false;
      await binding.runExclusive(() async {
        exclusiveActionRan = true;
      });
      await binding.updateSurface(wid: 52, width: 960, height: 540);

      expect(exclusiveActionRan, isTrue);
      expect(writes.last, 'vo=gpu');
      expect(writes, contains('wid=52'));
      final bindError = diagnostics.singleWhere(
        (entry) => entry.key == 'bind_error',
      );
      expect(bindError.value['error'], 'StateError');
      expect(bindError.value['reason'], 'property_write_failed');
      expect(bindError.value.containsKey('message'), isFalse);
    });

    test('ignores diagnostic callback failures during surface binding',
        () async {
      final writes = <String>[];
      final binding = AndroidSurfaceBinding(
        writeProperty: (key, value) async {
          writes.add('$key=$value');
        },
        vo: 'gpu',
        compatibilityMode: false,
        onDiagnostic: (event, fields) {
          throw StateError('diagnostic callback failure');
        },
      );

      await binding.initialize(_initialProperties);
      await binding.handleResize(
        wid: 53,
        width: 960,
        height: 540,
        updateNotifiers: () {},
      );
      await binding.onLoad();

      expect(writes, contains('wid=53'));
      expect(writes.last, 'vo=gpu');
    });
  });
}

AndroidSurfaceBinding _binding(
  List<String> writes, {
  String vo = 'gpu',
  bool compatibilityMode = false,
}) {
  return AndroidSurfaceBinding(
    writeProperty: (key, value) async {
      writes.add('$key=$value');
    },
    vo: vo,
    compatibilityMode: compatibilityMode,
  );
}

const _initialProperties = <String, String>{
  'vo': 'null',
  'gpu-context': 'android',
};
