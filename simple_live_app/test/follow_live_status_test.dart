import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  test('unknown follow refresh has no completed live status', () {
    expect(followStatusForLiveState(LiveStatusState.live), 2);
    expect(followStatusForLiveState(LiveStatusState.offline), 1);
    expect(followStatusForLiveState(LiveStatusState.unknown), isNull);
  });

  test('all sites refresh follow metadata', () {
    expect(shouldRefreshFollowMetadata(Constant.kKuaishou), isTrue);
    expect(shouldRefreshFollowMetadata(Constant.kDouyin), isTrue);
    expect(shouldRefreshFollowMetadata(Constant.kBiliBili), isTrue);
    expect(shouldRefreshFollowMetadata(Constant.kHuya), isTrue);
  });

  test('all follow preview caches use the same short freshness window', () {
    expect(
      followPreviewCacheTtl(Constant.kKuaishou),
      const Duration(minutes: 2),
    );
    expect(
      followPreviewCacheTtl(Constant.kDouyin),
      const Duration(minutes: 2),
    );
    expect(
      followPreviewCacheTtl(Constant.kBiliBili),
      const Duration(minutes: 2),
    );
    expect(
      followPreviewCacheTtl(Constant.kHuya),
      const Duration(minutes: 2),
    );
  });

  test('non-Kuaishou preview expires and missing anchor data refreshes', () {
    final now = DateTime(2026, 8, 11, 12);
    FollowUser bilibili({
      String userName = '主播',
      String face = 'avatar',
      DateTime? updatedAt,
    }) {
      return FollowUser(
        id: 'bilibili_room',
        roomId: 'room',
        siteId: Constant.kBiliBili,
        userName: userName,
        face: face,
        addTime: DateTime(2026),
        roomTitle: '标题',
        roomCover: 'cover',
        previewUpdatedAt: updatedAt,
      );
    }

    expect(
      isFollowPreviewMetadataStale(
        bilibili(updatedAt: now.subtract(const Duration(minutes: 1))),
        now: now,
      ),
      isFalse,
    );
    expect(
      isFollowPreviewMetadataStale(
        bilibili(updatedAt: now.subtract(const Duration(minutes: 2))),
        now: now,
      ),
      isTrue,
    );
    expect(
      isFollowPreviewMetadataStale(
        bilibili(userName: '', updatedAt: now),
        now: now,
      ),
      isTrue,
    );
    expect(
      isFollowPreviewMetadataStale(
        bilibili(face: '', updatedAt: now),
        now: now,
      ),
      isTrue,
    );
    expect(
      isFollowPreviewMetadataStale(
        bilibili(updatedAt: now.add(const Duration(days: 1))),
        now: now,
      ),
      isTrue,
    );
  });

  test('non-Kuaishou detail replaces historical room and anchor metadata', () {
    final item = FollowUser(
      id: 'bilibili_room',
      roomId: 'room',
      siteId: Constant.kBiliBili,
      userName: '旧主播',
      face: 'old-avatar',
      addTime: DateTime(2026),
      roomTitle: '旧标题',
      roomCover: 'old-cover',
    );
    final refreshedAt = DateTime(2026, 8, 11, 12);

    final changed = applyFollowPreviewDetail(
      item,
      LiveRoomDetail(
        roomId: 'room',
        title: '新标题',
        cover: 'new-cover',
        userName: '新主播',
        userAvatar: 'new-avatar',
        online: 1,
        status: true,
        url: 'https://live.bilibili.com/room',
      ),
      updatedAt: refreshedAt,
    );

    expect(changed, isTrue);
    expect(item.roomTitle, '新标题');
    expect(item.roomCover, 'new-cover');
    expect(item.userName, '新主播');
    expect(item.face, 'new-avatar');
    expect(item.previewUpdatedAt, refreshedAt);
  });

  test('empty error detail cannot erase the last valid follow preview', () {
    final item = FollowUser(
      id: 'kuaishou_room',
      roomId: 'room',
      siteId: Constant.kKuaishou,
      userName: '主播',
      face: 'avatar',
      addTime: DateTime(2026),
      roomTitle: '有效标题',
      roomCover: 'valid-cover',
    );

    final changed = applyFollowPreviewDetail(
      item,
      LiveRoomDetail(
        roomId: 'room',
        title: '',
        cover: '',
        userName: '',
        userAvatar: '',
        online: 0,
        status: false,
        liveStatusState: LiveStatusState.unknown,
        url: 'https://live.kuaishou.com/u/room',
      ),
    );

    expect(changed, isFalse);
    expect(item.roomTitle, '有效标题');
    expect(item.roomCover, 'valid-cover');
    expect(item.userName, '主播');
    expect(item.face, 'avatar');
    expect(item.previewUpdatedAt, isNull);
  });

  test('Kuaishou follow trace carries scope and force-network policy',
      () async {
    await KuaishouRequestTrace.run(
      KuaishouRequestSource.followStatus,
      () async {
        expect(
            KuaishouRequestTrace.current, KuaishouRequestSource.followStatus);
        expect(KuaishouRequestTrace.scopeId, 'kuaishou:follow-refresh');
        expect(KuaishouRequestTrace.forceNetwork, isTrue);
      },
      scopeId: 'kuaishou:follow-refresh',
      forceNetwork: true,
    );
  });

  test('Kuaishou follow limiter uses target count up to four', () {
    expect(
      KuaishouFollowRefreshLimiter(targetCount: 1).currentConcurrency,
      1,
    );
    expect(
      KuaishouFollowRefreshLimiter(targetCount: 2).currentConcurrency,
      2,
    );
    expect(
      KuaishouFollowRefreshLimiter(targetCount: 4).currentConcurrency,
      4,
    );
    expect(
      KuaishouFollowRefreshLimiter(targetCount: 100).currentConcurrency,
      4,
    );
  });

  test('Kuaishou follow limiter admits four tasks immediately and caps extras',
      () async {
    final limiter = KuaishouFollowRefreshLimiter(targetCount: 20);

    await Future.wait(List.generate(4, (_) => limiter.beforeRequest()));
    var fifthAcquired = false;
    final fifth = limiter.beforeRequest().then((_) {
      fifthAcquired = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(limiter.currentConcurrency, 4);
    expect(limiter.inFlight, 4);
    expect(fifthAcquired, isFalse);

    limiter.afterRequest();
    await fifth;

    expect(fifthAcquired, isTrue);
    expect(limiter.inFlight, 4);
    for (var i = 0; i < 4; i++) {
      limiter.afterRequest();
    }
    expect(limiter.inFlight, 0);
  });
}
