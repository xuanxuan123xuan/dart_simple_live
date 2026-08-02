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
            isPlaying: () => firstPlaying,
            requestPlay: () => requestPlay(() {
              firstPlaying = true;
            }),
            waitUntilPlaying: (_) async => firstPlaying,
          ),
          MultiRoomPlaybackRecoveryTarget(
            roomKey: 'second',
            shouldPlay: () => true,
            isPlaying: () => secondPlaying,
            requestPlay: () => requestPlay(() {
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
            isPlaying: () => false,
            requestPlay: () async {
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
            isPlaying: () => false,
            requestPlay: () async {
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
            isPlaying: () => false,
            requestPlay: () async {
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
            isPlaying: () => false,
            requestPlay: () async {
              firstRequests += 1;
              cancelled = true;
            },
            waitUntilPlaying: (_) async => false,
          ),
          MultiRoomPlaybackRecoveryTarget(
            roomKey: 'second',
            shouldPlay: () => true,
            isPlaying: () => false,
            requestPlay: () async {
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
