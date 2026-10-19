import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/modules/live_room/player/live_listening_session.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';

class _ClosedPlayer with PlayerMixin {
  int playerAccesses = 0;

  @override
  bool get listeningPlaybackAvailable => true;

  @override
  Player get player {
    playerAccesses++;
    throw StateError('A closed room must not access the native player');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('closing drains an active source and drops queued source opens',
      () async {
    final sourceStarted = Completer<void>();
    final finishSource = Completer<void>();
    var lateSourceCalls = 0;
    final session = LiveListeningSession(
      writeVideoEnabled: (_) async {},
      canChange: () => true,
    );
    final activeSource = session.withSource(() async {
      sourceStarted.complete();
      await finishSource.future;
    });
    await sourceStarted.future;
    final queuedSource = session.withSource(() async => lateSourceCalls++);
    var closeFinished = false;
    final closing = session.close().then((_) => closeFinished = true);
    expect(session.closed, isTrue);
    expect(closeFinished, isFalse);

    finishSource.complete();
    await Future.wait([activeSource, queuedSource, closing]);
    expect(closeFinished, isTrue);
    expect(lateSourceCalls, 0);
  });

  test('room close rejects late source opens before creating a session',
      () async {
    final room = _ClosedPlayer();
    expect(room.canToggleListeningMode, isTrue);

    final closing = room.closeListeningSession();
    expect(room.canToggleListeningMode, isFalse,
        reason: 'Invalidation must happen before the close future completes');
    await room.openListeningMedia(Media('https://example.invalid/live'));
    await room.toggleListeningMode();
    await closing;
    await room.closeListeningSession();
    await room.openListeningMedia(Media('https://example.invalid/late'));

    expect(room.playerAccesses, 0);
    expect(room.listeningMode.value, isFalse);
    expect(room.listeningModeChanging.value, isFalse);
  });

  test('an obsolete queued playback request never opens its media', () async {
    final room = _ClosedPlayer();
    await room.openListeningMedia(
      Media('https://example.invalid/stale'),
      isCurrent: () => false,
    );
    expect(room.playerAccesses, 0);
    await room.closeListeningSession();
  });
}
