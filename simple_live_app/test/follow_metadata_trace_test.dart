import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// Snapshot of the KuaishouRequestTrace zone observed inside getRoomDetail.
class _TraceRecord {
  const _TraceRecord(
    this.siteId,
    this.source,
    this.scopeId,
    this.forceNetwork,
  );

  final String siteId;
  final KuaishouRequestSource source;
  final String? scopeId;
  final bool forceNetwork;
}

/// LiveSite stub that records the async-local Kuaishou trace state at the
/// moment getRoomDetail is entered, then returns a canned detail or throws.
class _RecordingLiveSite extends LiveSite {
  _RecordingLiveSite(
    this.siteId, {
    this.detail,
    this.errorFor,
  });

  final String siteId;
  final LiveRoomDetail? detail;

  /// Per-room error factory; a non-null result is thrown to simulate a failed
  /// detail request (e.g. CoreError from the network layer).
  final Object? Function(String roomId)? errorFor;

  final List<_TraceRecord> records = [];

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    records.add(
      _TraceRecord(
        siteId,
        KuaishouRequestTrace.current,
        KuaishouRequestTrace.scopeId,
        KuaishouRequestTrace.forceNetwork,
      ),
    );
    final error = errorFor?.call(roomId);
    if (error != null) {
      throw error;
    }
    return detail!;
  }
}

/// DBService stub backed by nothing: the metadata refresh worker only calls
/// addFollow on this path, and the follow-DB write is neutralized in tests.
class _NoopDBService extends DBService {
  @override
  Future addFollow(FollowUser follow) async {}

  @override
  Future addFollows(Iterable<FollowUser> follows) async {}
}

FollowUser _staleLiveItem({
  required String siteId,
  required String roomId,
}) {
  return FollowUser(
    id: '${siteId}_$roomId',
    roomId: roomId,
    siteId: siteId,
    userName: '主播$roomId',
    face: 'avatar$roomId',
    addTime: DateTime(2026, 8, 11),
    // Empty roomTitle marks the preview as stale so refreshVisiblePreviews
    // picks the item up without forcing.
    roomTitle: '',
    roomCover: 'cover$roomId',
  )
    ..liveStatus.value = 2
    ..liveCheckState.value = FollowLiveCheckState.unknown;
}

LiveRoomDetail _liveDetail(String roomId) => LiveRoomDetail(
      roomId: roomId,
      title: '新标题$roomId',
      cover: 'new-cover',
      userName: '主播$roomId',
      userAvatar: 'new-avatar',
      online: 1,
      status: true,
      url: 'https://example.com/$roomId',
    );

/// Swap [Sites.allSites] entries for recording stubs and return a restore
/// closure. Sites.allSites is a mutable static map shared per isolate, so the
/// originals must be restored after each test.
void Function() useRecordingSites({
  required _RecordingLiveSite kuaishou,
  _RecordingLiveSite? bilibili,
}) {
  final originalKuaishou = Sites.allSites[Constant.kKuaishou];
  final originalBilibili = Sites.allSites[Constant.kBiliBili];
  Sites.allSites[Constant.kKuaishou] = Site(
    id: Constant.kKuaishou,
    logo: '',
    name: '快手直播',
    liveSite: kuaishou,
  );
  if (bilibili != null) {
    Sites.allSites[Constant.kBiliBili] = Site(
      id: Constant.kBiliBili,
      logo: '',
      name: '哔哩哔哩',
      liveSite: bilibili,
    );
  }
  return () {
    Sites.allSites[Constant.kKuaishou] = originalKuaishou!;
    if (bilibili != null) {
      Sites.allSites[Constant.kBiliBili] = originalBilibili!;
    }
  };
}

void main() {
  setUpAll(() {
    if (!Get.isRegistered<DBService>()) {
      Get.put<DBService>(_NoopDBService());
    }
  });

  test('follow metadata refresh marks Kuaishou detail as followStatus trace',
      () async {
    final kuaishouSite = _RecordingLiveSite(
      Constant.kKuaishou,
      detail: _liveDetail('ks_room'),
    );
    final restore = useRecordingSites(kuaishou: kuaishouSite);

    final item = _staleLiveItem(siteId: Constant.kKuaishou, roomId: 'ks_room');
    final service = FollowService();
    await service.refreshVisiblePreviews([item]);
    restore();

    expect(kuaishouSite.records, hasLength(1));
    final record = kuaishouSite.records.single;
    expect(record.source, KuaishouRequestSource.followStatus);
    expect(record.scopeId, 'kuaishou:follow-refresh');
    expect(record.forceNetwork, isTrue);

    // Sanity: the detail was applied to the preview.
    expect(item.roomTitle, '新标题ks_room');
  });

  test('follow metadata refresh leaves non-Kuaishou sites untraced', () async {
    final kuaishouSite = _RecordingLiveSite(
      Constant.kKuaishou,
      detail: _liveDetail('ks_room'),
    );
    final bilibiliSite = _RecordingLiveSite(
      Constant.kBiliBili,
      detail: _liveDetail('bili_room'),
    );
    final restore = useRecordingSites(
      kuaishou: kuaishouSite,
      bilibili: bilibiliSite,
    );

    final bilibiliItem = _staleLiveItem(
      siteId: Constant.kBiliBili,
      roomId: 'bili_room',
    );
    final kuaishouItem = _staleLiveItem(
      siteId: Constant.kKuaishou,
      roomId: 'ks_room',
    );
    final service = FollowService();
    await service.refreshVisiblePreviews([bilibiliItem, kuaishouItem]);
    restore();

    // Bilibili detail runs outside any Kuaishou trace zone.
    expect(bilibiliSite.records, hasLength(1));
    final biliRecord = bilibiliSite.records.single;
    expect(biliRecord.source, KuaishouRequestSource.unknown);
    expect(biliRecord.scopeId, isNull);
    expect(biliRecord.forceNetwork, isFalse);

    // Kuaishou detail in the same refresh carries the trace.
    expect(kuaishouSite.records, hasLength(1));
    final ksRecord = kuaishouSite.records.single;
    expect(ksRecord.source, KuaishouRequestSource.followStatus);
    expect(ksRecord.scopeId, 'kuaishou:follow-refresh');
    expect(ksRecord.forceNetwork, isTrue);

    // Both items got their metadata refreshed.
    expect(bilibiliItem.roomTitle, '新标题bili_room');
    expect(kuaishouItem.roomTitle, '新标题ks_room');
  });

  test('failed Kuaishou detail counts as failure without crashing the refresh',
      () async {
    final kuaishouSite = _RecordingLiveSite(
      Constant.kKuaishou,
      detail: _liveDetail('ok_room'),
      errorFor: (roomId) => roomId == 'bad_room'
          ? CoreError(
              '快手请求失败',
              statusCode: 429,
              kind: CoreErrorKind.http,
            )
          : null,
    );
    final restore = useRecordingSites(kuaishou: kuaishouSite);

    final failingItem = _staleLiveItem(
      siteId: Constant.kKuaishou,
      roomId: 'bad_room',
    );
    final succeedingItem = _staleLiveItem(
      siteId: Constant.kKuaishou,
      roomId: 'ok_room',
    );
    final service = FollowService();
    // Must complete without throwing: the worker catches the CoreError,
    // counts it as a failure and keeps draining the queue.
    await service.refreshVisiblePreviews([failingItem, succeedingItem]);
    restore();

    expect(kuaishouSite.records, hasLength(2));
    for (final record in kuaishouSite.records) {
      expect(record.source, KuaishouRequestSource.followStatus);
      expect(record.scopeId, 'kuaishou:follow-refresh');
      expect(record.forceNetwork, isTrue);
    }

    // The failing item keeps its previous preview; nothing was clobbered.
    expect(failingItem.roomTitle, '');
    expect(failingItem.previewUpdatedAt, isNull);

    // The worker moved on to the next item after the failure.
    expect(succeedingItem.roomTitle, '新标题ok_room');
  });
}
