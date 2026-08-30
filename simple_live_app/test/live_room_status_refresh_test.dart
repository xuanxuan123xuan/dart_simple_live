import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  test('Kuaishou recovery countdown uses minute-second format', () {
    expect(formatKuaishouRecoveryCountdown(300), '5:00');
    expect(formatKuaishouRecoveryCountdown(61), '1:01');
    expect(formatKuaishouRecoveryCountdown(-1), '0:00');
  });

  test('Kuaishou device recovery only retries the original live room', () {
    expect(
      shouldAutoRetryKuaishouDeviceRecovery(
        roomDisposed: false,
        armed: true,
        recoveryRoomKey: 'kuaishou:room-a',
        currentRoomKey: 'kuaishou:room-a',
      ),
      isTrue,
    );
    expect(
      shouldAutoRetryKuaishouDeviceRecovery(
        roomDisposed: false,
        armed: true,
        recoveryRoomKey: 'kuaishou:room-a',
        currentRoomKey: 'kuaishou:room-b',
      ),
      isFalse,
    );
    expect(
      shouldAutoRetryKuaishouDeviceRecovery(
        roomDisposed: true,
        armed: true,
        recoveryRoomKey: 'kuaishou:room-a',
        currentRoomKey: 'kuaishou:room-a',
      ),
      isFalse,
    );
  });

  group('inline multi-room playback resume', () {
    test('resumes when the single room was playing or buffering', () {
      expect(
        shouldResumeLiveRoomAfterInlineMultiRoom(
          playing: true,
          buffering: false,
        ),
        isTrue,
      );
      expect(
        shouldResumeLiveRoomAfterInlineMultiRoom(
          playing: false,
          buffering: true,
        ),
        isTrue,
      );
      expect(
        shouldResumeLiveRoomAfterInlineMultiRoom(
          playing: false,
          buffering: false,
        ),
        isFalse,
      );
    });
  });

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

  group('room detail refresh commit guard', () {
    test('does not publish an offline snapshot rejected by active playback',
        () {
      final decision = resolveRoomLiveRefresh(
        currentState: LiveStatusState.live,
        incomingState: LiveStatusState.offline,
        consecutiveOfflineReports: 0,
        currentLiveStatus: true,
        playbackActive: true,
      );

      expect(
        shouldCommitRoomDetailRefresh(
          incomingState: LiveStatusState.offline,
          decision: decision,
        ),
        isFalse,
      );
    });

    test('publishes only a confirmed offline snapshot', () {
      final decision = resolveRoomLiveRefresh(
        currentState: LiveStatusState.live,
        incomingState: LiveStatusState.offline,
        consecutiveOfflineReports: 2,
        currentLiveStatus: true,
        playbackActive: false,
      );

      expect(
        shouldCommitRoomDetailRefresh(
          incomingState: LiveStatusState.offline,
          decision: decision,
        ),
        isTrue,
      );
    });

    test('never publishes an unknown snapshot', () {
      const decision = RoomLiveRefreshDecision(
        state: LiveStatusState.live,
        consecutiveOfflineReports: 0,
        liveStatus: true,
      );

      expect(
        shouldCommitRoomDetailRefresh(
          incomingState: LiveStatusState.unknown,
          decision: decision,
        ),
        isFalse,
      );
    });
  });

  group('Kuaishou room metadata retention', () {
    test('keeps presentation fields while adopting fresh session data', () {
      final oldData = <String, Object>{'play': 'old'};
      final newData = <String, Object>{'play': 'new'};
      final oldDanmaku = Object();
      final newDanmaku = Object();
      final merged = mergeKuaishouRoomDetailMetadata(
        current: _roomDetail(
          title: '原直播标题',
          cover: 'https://example.com/old-cover.jpg',
          userName: '原主播',
          userAvatar: 'https://example.com/old-avatar.jpg',
          online: 10,
          data: oldData,
          danmakuData: oldDanmaku,
        ),
        incoming: _roomDetail(
          title: ' ',
          cover: '',
          userName: '',
          userAvatar: '',
          online: 42,
          data: newData,
          danmakuData: newDanmaku,
        ),
      );

      expect(merged.title, '原直播标题');
      expect(merged.cover, 'https://example.com/old-cover.jpg');
      expect(merged.userName, '原主播');
      expect(merged.userAvatar, 'https://example.com/old-avatar.jpg');
      expect(merged.online, 42);
      expect(merged.data, same(newData));
      expect(merged.danmakuData, same(newDanmaku));
    });

    test('accepts fresh non-empty presentation fields', () {
      final merged = mergeKuaishouRoomDetailMetadata(
        current: _roomDetail(
          title: '旧标题',
          cover: 'old-cover',
          userName: '旧主播',
          userAvatar: 'old-avatar',
        ),
        incoming: _roomDetail(
          title: '新标题',
          cover: 'new-cover',
          userName: '新主播',
          userAvatar: 'new-avatar',
        ),
      );

      expect(merged.title, '新标题');
      expect(merged.cover, 'new-cover');
      expect(merged.userName, '新主播');
      expect(merged.userAvatar, 'new-avatar');
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

  group('Kuaishou stable playback recheck', () {
    test('jittered recheck remains within the 120-180 second boundary', () {
      expect(
        resolveKuaishouStableRefreshDelay(jitterSeconds: -999),
        const Duration(seconds: 120),
      );
      expect(
        resolveKuaishouStableRefreshDelay(jitterSeconds: 999),
        const Duration(seconds: 180),
      );
      expect(
        resolveKuaishouStableRefreshDelay(jitterSeconds: 0),
        const Duration(seconds: 150),
      );
    });

    test('buffering playback is not considered stable', () {
      expect(
        isLiveRoomPlaybackStable(
          initialized: true,
          playing: true,
          buffering: true,
          hasError: false,
        ),
        isFalse,
      );
      expect(
        isLiveRoomPlaybackStable(
          initialized: true,
          playing: true,
          buffering: false,
          hasError: false,
        ),
        isTrue,
      );
    });
  });

  group('Kuaishou recovery quality retention', () {
    test('prefers the prior quality name before falling back to its index', () {
      expect(
        resolveKuaishouRecoveryQualityIndex(
          qualities: const ['HD', 'FHD', 'SD'],
          previousQualityName: 'FHD',
          previousQualityIndex: 0,
        ),
        1,
      );
      expect(
        resolveKuaishouRecoveryQualityIndex(
          qualities: const ['FHD', 'HD'],
          previousQualityName: 'missing',
          previousQualityIndex: 99,
        ),
        1,
      );
    });

    test('keeps a CDN line by signature after signed URL reordering', () {
      expect(
        resolveKuaishouRecoveryLineIndex(
          urls: const [
            'https://b.example.com/live.flv?token=new-b',
            'https://a.example.com/live.flv?token=new-a',
          ],
          previousUrl: 'https://a.example.com/live.flv?token=old-a',
          fallbackIndex: 0,
        ),
        1,
      );
    });
  });
}

LiveRoomDetail _roomDetail({
  String roomId = 'room-id',
  String title = 'title',
  String cover = 'cover',
  String userName = 'anchor',
  String userAvatar = 'avatar',
  int online = 1,
  bool status = true,
  LiveStatusState liveStatusState = LiveStatusState.live,
  Object? data,
  Object? danmakuData,
  String url = 'https://live.kuaishou.com/u/room-id',
}) {
  return LiveRoomDetail(
    roomId: roomId,
    title: title,
    cover: cover,
    userName: userName,
    userAvatar: userAvatar,
    online: online,
    status: status,
    liveStatusState: liveStatusState,
    data: data,
    danmakuData: danmakuData,
    url: url,
  );
}
