import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  group('offline room refresh guard', () {
    test('never accepts an offline snapshot while playback is active', () {
      expect(
        shouldAcceptOfflineRoomRefresh(
          playbackActive: true,
          consecutiveOfflineReports: 10,
        ),
        isFalse,
      );
    });

    test('requires three consecutive offline snapshots after playback stops',
        () {
      expect(
        shouldAcceptOfflineRoomRefresh(
          playbackActive: false,
          consecutiveOfflineReports: 2,
        ),
        isFalse,
      );
      expect(
        shouldAcceptOfflineRoomRefresh(
          playbackActive: false,
          consecutiveOfflineReports: 3,
        ),
        isTrue,
      );
    });
  });

  group('room live tri-state transition', () {
    test('unknown breaks an unconfirmed offline sequence', () {
      final decision = resolveRoomLiveRefresh(
        currentState: LiveStatusState.live,
        incomingState: LiveStatusState.unknown,
        consecutiveOfflineReports: 2,
        currentLiveStatus: true,
        playbackActive: false,
      );
      expect(decision.state, LiveStatusState.live);
      expect(decision.consecutiveOfflineReports, 0);
      expect(decision.liveStatus, isTrue);
    });

    test('active playback rejects an offline report', () {
      final decision = resolveRoomLiveRefresh(
        currentState: LiveStatusState.live,
        incomingState: LiveStatusState.offline,
        consecutiveOfflineReports: 2,
        currentLiveStatus: true,
        playbackActive: true,
      );
      expect(decision.state, LiveStatusState.live);
      expect(decision.consecutiveOfflineReports, 0);
      expect(decision.liveStatus, isTrue);
    });

    test('third explicit offline report confirms offline', () {
      final decision = resolveRoomLiveRefresh(
        currentState: LiveStatusState.live,
        incomingState: LiveStatusState.offline,
        consecutiveOfflineReports: 2,
        currentLiveStatus: true,
        playbackActive: false,
      );
      expect(decision.state, LiveStatusState.offline);
      expect(decision.consecutiveOfflineReports, 3);
      expect(decision.liveStatus, isFalse);
    });

    test('live report reopens a confirmed offline room', () {
      final decision = resolveRoomLiveRefresh(
        currentState: LiveStatusState.offline,
        incomingState: LiveStatusState.live,
        consecutiveOfflineReports: 3,
        currentLiveStatus: false,
        playbackActive: false,
      );
      expect(decision.state, LiveStatusState.live);
      expect(decision.consecutiveOfflineReports, 0);
      expect(decision.liveStatus, isTrue);
    });
  });

  group('online refresh backoff', () {
    test('normal unknown responses increment the backoff exactly once', () {
      final firstFailure = resolveOnlineRefreshFailureCount(
        incomingState: LiveStatusState.unknown,
        currentFailures: 0,
      );
      final secondFailure = resolveOnlineRefreshFailureCount(
        incomingState: LiveStatusState.unknown,
        currentFailures: firstFailure,
      );

      expect(firstFailure, 1);
      expect(secondFailure, 2);
      expect(
        resolveOnlineRefreshDelay(
          LiveStatusState.unknown,
          firstFailure,
        ),
        const Duration(seconds: 30),
      );
    });

    test('live clears failures while offline preserves the existing count', () {
      expect(
        resolveOnlineRefreshFailureCount(
          incomingState: LiveStatusState.live,
          currentFailures: 5,
        ),
        0,
      );
      expect(
        resolveOnlineRefreshFailureCount(
          incomingState: LiveStatusState.offline,
          currentFailures: 5,
        ),
        5,
      );
    });

    test('live state resets to the 10s base interval', () {
      expect(
        resolveOnlineRefreshDelay(LiveStatusState.live, 5),
        const Duration(seconds: 10),
      );
    });

    test('offline uses the low-frequency 45s interval', () {
      expect(
        resolveOnlineRefreshDelay(LiveStatusState.offline, 0),
        const Duration(seconds: 45),
      );
    });

    test('unknown backoff grows exponentially and caps at 300s', () {
      expect(
        resolveOnlineRefreshDelay(LiveStatusState.unknown, 0),
        const Duration(seconds: 10),
      );
      expect(
        resolveOnlineRefreshDelay(LiveStatusState.unknown, 1),
        const Duration(seconds: 30),
      );
      expect(
        resolveOnlineRefreshDelay(LiveStatusState.unknown, 2),
        const Duration(seconds: 60),
      );
      expect(
        resolveOnlineRefreshDelay(LiveStatusState.unknown, 3),
        const Duration(seconds: 120),
      );
      expect(
        resolveOnlineRefreshDelay(LiveStatusState.unknown, 4),
        const Duration(seconds: 240),
      );
      expect(
        resolveOnlineRefreshDelay(LiveStatusState.unknown, 100),
        const Duration(seconds: 300),
      );
    });
  });
}
