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
}
