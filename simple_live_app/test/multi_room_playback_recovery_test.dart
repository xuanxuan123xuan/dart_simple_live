import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_playback_recovery.dart';

void main() {
  group('MultiRoomPlaybackRecoveryCoordinator', () {
    test('recovers desired players serially from their real state', () async {
      const coordinator = MultiRoomPlaybackRecoveryCoordinator(
        maxAttempts: 2,
        confirmTimeout: Duration.zero,
        retryDelay: Duration.zero,
      );
      var firstPlaying = false;
      var secondPlaying = false;
      var activeRequests = 0;
      var maxActiveRequests = 0;

      Future<void> requestPlay(void Function() markPlaying) async {
        activeRequests += 1;
        if (activeRequests > maxActiveRequests) {
          maxActiveRequests = activeRequests;
        }
        await Future<void>.delayed(Duration.zero);
        markPlaying();
        activeRequests -= 1;
      }

      final recovered = await coordinator.recover(
        targets: [
          MultiRoomPlaybackRecoveryTarget(
            roomKey: 'first',
            shouldPlay: () => true,
            requestPlay: (_) => requestPlay(() {
              firstPlaying = true;
            }),
            waitUntilPlaying: (_) async => firstPlaying,
          ),
          MultiRoomPlaybackRecoveryTarget(
            roomKey: 'second',
            shouldPlay: () => true,
            requestPlay: (_) => requestPlay(() {
              secondPlaying = true;
            }),
            waitUntilPlaying: (_) async => secondPlaying,
          ),
        ],
        isCancelled: () => false,
      );

      expect(recovered, isTrue);
      expect(firstPlaying, isTrue);
      expect(secondPlaying, isTrue);
      expect(maxActiveRequests, 1);
    });

    test('retries a native player only up to the configured bound', () async {
      const coordinator = MultiRoomPlaybackRecoveryCoordinator(
        maxAttempts: 3,
        confirmTimeout: Duration.zero,
        retryDelay: Duration.zero,
      );
      var requests = 0;

      final recovered = await coordinator.recover(
        targets: [
          MultiRoomPlaybackRecoveryTarget(
            roomKey: 'stuck',
            shouldPlay: () => true,
            requestPlay: (_) async {
              requests += 1;
            },
            waitUntilPlaying: (_) async => false,
          ),
        ],
        isCancelled: () => false,
      );

      expect(recovered, isFalse);
      expect(requests, 3);
    });

    test('does not accept a play request without real progress', () async {
      const coordinator = MultiRoomPlaybackRecoveryCoordinator(
        maxAttempts: 1,
        confirmTimeout: Duration.zero,
        retryDelay: Duration.zero,
      );
      var requests = 0;

      final recovered = await coordinator.recover(
        targets: [
          MultiRoomPlaybackRecoveryTarget(
            roomKey: 'stale',
            shouldPlay: () => true,
            requestPlay: (_) async {
              requests += 1;
            },
            waitUntilPlaying: (_) async => false,
          ),
        ],
        isCancelled: () => false,
      );

      expect(requests, 1);
      expect(recovered, isFalse);
    });

    test('uses a forced restart only after progress verification fails',
        () async {
      const coordinator = MultiRoomPlaybackRecoveryCoordinator(
        maxAttempts: 2,
        confirmTimeout: Duration.zero,
        retryDelay: Duration.zero,
      );
      final restartFlags = <bool>[];
      var checks = 0;

      final recovered = await coordinator.recover(
        targets: [
          MultiRoomPlaybackRecoveryTarget(
            roomKey: 'stalled',
            shouldPlay: () => true,
            requestPlay: (forceRestart) async {
              restartFlags.add(forceRestart);
            },
            waitUntilPlaying: (_) async {
              checks += 1;
              return checks > 1;
            },
          ),
        ],
        isCancelled: () => false,
      );

      expect(recovered, isTrue);
      expect(restartFlags, [false, true]);
    });

    test('verifies all players after every play request has completed',
        () async {
      const coordinator = MultiRoomPlaybackRecoveryCoordinator(
        maxAttempts: 1,
        confirmTimeout: Duration.zero,
        retryDelay: Duration.zero,
      );
      var firstAdvancing = false;
      var secondAdvancing = false;

      final recovered = await coordinator.recover(
        targets: [
          MultiRoomPlaybackRecoveryTarget(
            roomKey: 'first',
            shouldPlay: () => true,
            requestPlay: (_) async {
              firstAdvancing = true;
            },
            waitUntilPlaying: (_) async => firstAdvancing,
          ),
          MultiRoomPlaybackRecoveryTarget(
            roomKey: 'second',
            shouldPlay: () => true,
            requestPlay: (_) async {
              // Simulate a later audio-session activation interrupting the
              // player which was requested first.
              firstAdvancing = false;
              secondAdvancing = true;
            },
            waitUntilPlaying: (_) async => secondAdvancing,
          ),
        ],
        isCancelled: () => false,
      );

      expect(recovered, isFalse);
    });

    test('never resumes a player after the user pauses it', () async {
      const coordinator = MultiRoomPlaybackRecoveryCoordinator(
        maxAttempts: 3,
        confirmTimeout: Duration.zero,
        retryDelay: Duration.zero,
      );
      var shouldPlay = true;
      var requests = 0;

      final recovered = await coordinator.recover(
        targets: [
          MultiRoomPlaybackRecoveryTarget(
            roomKey: 'paused-by-user',
            shouldPlay: () => shouldPlay,
            requestPlay: (_) async {
              requests += 1;
              shouldPlay = false;
            },
            waitUntilPlaying: (_) async => false,
          ),
        ],
        isCancelled: () => false,
      );

      expect(recovered, isTrue);
      expect(requests, 1);
    });

    test('skips a target that was already paused by the user', () async {
      const coordinator = MultiRoomPlaybackRecoveryCoordinator(
        maxAttempts: 3,
        confirmTimeout: Duration.zero,
        retryDelay: Duration.zero,
      );
      var requests = 0;

      final recovered = await coordinator.recover(
        targets: [
          MultiRoomPlaybackRecoveryTarget(
            roomKey: 'already-paused',
            shouldPlay: () => false,
            requestPlay: (_) async {
              requests += 1;
            },
            waitUntilPlaying: (_) async => false,
          ),
        ],
        isCancelled: () => false,
      );

      expect(recovered, isTrue);
      expect(requests, 0);
    });

    test('cancellation prevents later targets and retries', () async {
      const coordinator = MultiRoomPlaybackRecoveryCoordinator(
        maxAttempts: 3,
        confirmTimeout: Duration.zero,
        retryDelay: Duration.zero,
      );
      var cancelled = false;
      var firstRequests = 0;
      var secondRequests = 0;

      final recovered = await coordinator.recover(
        targets: [
          MultiRoomPlaybackRecoveryTarget(
            roomKey: 'first',
            shouldPlay: () => true,
            requestPlay: (_) async {
              firstRequests += 1;
              cancelled = true;
            },
            waitUntilPlaying: (_) async => false,
          ),
          MultiRoomPlaybackRecoveryTarget(
            roomKey: 'second',
            shouldPlay: () => true,
            requestPlay: (_) async {
              secondRequests += 1;
            },
            waitUntilPlaying: (_) async => false,
          ),
        ],
        isCancelled: () => cancelled,
      );

      expect(recovered, isFalse);
      expect(firstRequests, 1);
      expect(secondRequests, 0);
    });
  });
}
