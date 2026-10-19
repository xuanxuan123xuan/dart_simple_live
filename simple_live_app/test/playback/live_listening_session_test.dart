import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/live_listening_session.dart';

void main() {
  group('LiveListeningSession', () {
    test('starts with video policy untouched in a fresh session', () async {
      final writes = <bool>[];
      final session = LiveListeningSession(
        writeVideoEnabled: (enabled) async => writes.add(enabled),
        canChange: () => true,
      );

      expect(session.listening, isFalse);
      expect(session.changing, isFalse);
      expect(await session.setListening(false), isFalse);
      expect(writes, isEmpty);
    });

    test('listening toggles video independently of paused playback', () async {
      final writes = <bool>[];
      var playbackPaused = true;
      final session = LiveListeningSession(
        writeVideoEnabled: (enabled) async => writes.add(enabled),
        canChange: () => true,
      );

      expect(await session.setListening(true), isTrue);
      expect(session.listening, isTrue);
      expect(playbackPaused, isTrue);
      expect(await session.setListening(false), isTrue);
      expect(session.listening, isFalse);
      expect(playbackPaused, isTrue);
      expect(writes, [false, true]);
    });

    test('publishes changing synchronously and ignores rapid toggle calls',
        () async {
      final preparation = Completer<void>();
      final writes = <bool>[];
      final notifications = <({bool listening, bool changing})>[];
      late final LiveListeningSession session;
      session = LiveListeningSession(
        writeVideoEnabled: (enabled) async => writes.add(enabled),
        canChange: () => true,
        prepareToListen: () => preparation.future,
        onChanged: () => notifications.add((
          listening: session.listening,
          changing: session.changing,
        )),
      );

      final first = session.setListening(true);
      expect(session.changing, isTrue);
      expect(await session.setListening(true), isFalse);
      expect(await session.setListening(false), isFalse);

      preparation.complete();
      expect(await first, isTrue);
      expect(writes, [false]);
      expect(session.changing, isFalse);
      expect(notifications, hasLength(2));
      expect(notifications.first.changing, isTrue);
      expect(notifications.last.listening, isTrue);
      expect(notifications.last.changing, isFalse);
    });

    test('serializes source operations before a pending listening toggle',
        () async {
      final sourceStarted = Completer<void>();
      final finishSource = Completer<void>();
      final events = <String>[];
      final session = LiveListeningSession(
        writeVideoEnabled: (enabled) async => events.add('video:$enabled'),
        canChange: () => true,
      );

      final source = session.withSource(() async {
        events.add('source:start');
        sourceStarted.complete();
        await finishSource.future;
        events.add('source:end');
      });
      final toggle = session.setListening(true);

      await sourceStarted.future;
      expect(events, ['source:start']);
      finishSource.complete();
      await source;
      expect(await toggle, isTrue);
      expect(events, ['source:start', 'source:end', 'video:false']);
    });

    test('reapplies audio-only policy around source opens', () async {
      final writes = <bool>[];
      var videoEnabled = true;
      final session = LiveListeningSession(
        writeVideoEnabled: (enabled) async {
          writes.add(enabled);
          videoEnabled = enabled;
        },
        canChange: () => true,
      );

      await session.setListening(true);
      expect(videoEnabled, isFalse);
      await session.withSource(() async {
        videoEnabled = true; // A native source open restores its video track.
      });

      expect(session.listening, isTrue);
      expect(videoEnabled, isFalse);
      expect(writes, [false, false, false]);
    });

    test('rolls back a failed toggle and keeps the queue usable', () async {
      final writes = <bool>[];
      var failNextDisable = true;
      final session = LiveListeningSession(
        writeVideoEnabled: (enabled) async {
          writes.add(enabled);
          if (!enabled && failNextDisable) {
            failNextDisable = false;
            throw StateError('video track write failed');
          }
        },
        canChange: () => true,
      );

      await expectLater(
        session.setListening(true),
        throwsA(isA<StateError>()),
      );
      expect(writes, [false, true]);
      expect(session.listening, isFalse);
      expect(session.changing, isFalse);

      expect(await session.setListening(true), isTrue);
      expect(writes, [false, true, false]);
      expect(session.listening, isTrue);
    });

    test('does not write video policy when preparation fails', () async {
      final writes = <bool>[];
      final session = LiveListeningSession(
        writeVideoEnabled: (enabled) async => writes.add(enabled),
        canChange: () => true,
        prepareToListen: () async => throw StateError('prepare failed'),
      );

      await expectLater(
        session.setListening(true),
        throwsA(isA<StateError>()),
      );
      expect(writes, isEmpty);
      expect(session.listening, isFalse);
      expect(session.changing, isFalse);
    });

    test('rechecks room availability after listen preparation', () async {
      final preparation = Completer<void>();
      final writes = <bool>[];
      var available = true;
      final session = LiveListeningSession(
        writeVideoEnabled: (enabled) async => writes.add(enabled),
        canChange: () => available,
        prepareToListen: () => preparation.future,
      );

      final toggle = session.setListening(true);
      available = false;
      preparation.complete();

      expect(await toggle, isFalse);
      expect(writes, isEmpty);
      expect(session.listening, isFalse);
      expect(session.changing, isFalse);
    });

    test('does not write or notify after closing during preparation', () async {
      final preparation = Completer<void>();
      final preparationStarted = Completer<void>();
      final writes = <bool>[];
      var notifications = 0;
      final session = LiveListeningSession(
        writeVideoEnabled: (enabled) async => writes.add(enabled),
        canChange: () => true,
        prepareToListen: () {
          preparationStarted.complete();
          return preparation.future;
        },
        onChanged: () => notifications++,
      );

      final toggle = session.setListening(true);
      await preparationStarted.future;
      final closing = session.close();
      expect(session.closed, isTrue);
      preparation.complete();

      expect(await toggle, isFalse);
      await closing;
      expect(writes, isEmpty);
      expect(notifications, 1);
      expect(session.changing, isFalse);
    });

    test('does not roll back or notify after closing during a video write',
        () async {
      final writeStarted = Completer<void>();
      final finishWrite = Completer<void>();
      final writes = <bool>[];
      var notifications = 0;
      final session = LiveListeningSession(
        writeVideoEnabled: (enabled) async {
          writes.add(enabled);
          writeStarted.complete();
          await finishWrite.future;
          throw StateError('write failed after close');
        },
        canChange: () => true,
        onChanged: () => notifications++,
      );

      final toggle = session.setListening(true);
      await writeStarted.future;
      final closing = session.close();
      finishWrite.complete();

      await expectLater(toggle, throwsA(isA<StateError>()));
      await closing;
      expect(writes, [false]);
      expect(notifications, 1);
      expect(session.changing, isFalse);
    });

    test('returns false when unavailable and rejects new work after close',
        () async {
      final writes = <bool>[];
      var available = false;
      final session = LiveListeningSession(
        writeVideoEnabled: (enabled) async => writes.add(enabled),
        canChange: () => available,
      );

      expect(await session.setListening(true), isFalse);
      expect(writes, isEmpty);
      available = true;
      await session.close();
      expect(await session.setListening(true), isFalse);
      await session.withSource(() async => writes.add(false));
      expect(writes, isEmpty);
    });

    test(
        'reapplies policy and propagates source errors without poisoning queue',
        () async {
      final writes = <bool>[];
      var videoEnabled = true;
      final session = LiveListeningSession(
        writeVideoEnabled: (enabled) async {
          writes.add(enabled);
          videoEnabled = enabled;
        },
        canChange: () => true,
      );

      await session.setListening(true);
      await expectLater(
        session.withSource(() async {
          videoEnabled = true;
          throw StateError('source open failed');
        }),
        throwsA(isA<StateError>()),
      );
      expect(videoEnabled, isFalse);
      expect(session.listening, isTrue);

      await session.withSource(() async {});
      expect(videoEnabled, isFalse);
      expect(await session.setListening(false), isTrue);
      expect(session.listening, isFalse);
      expect(writes, [false, false, false, false, false, true]);
    });
  });
}
