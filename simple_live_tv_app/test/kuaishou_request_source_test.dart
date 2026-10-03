import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/models/db/follow_user.dart';
import 'package:simple_live_tv_app/models/db/history.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_tv_app/services/current_room_service.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/services/follow_user_service.dart';

/// 记录一次 getRoomDetail 调用时所在的快手 trace zone。
class _KuaishouTraceRecord {
  const _KuaishouTraceRecord({
    required this.roomId,
    required this.source,
    required this.scopeId,
    required this.forceNetwork,
  });

  final String roomId;
  final KuaishouRequestSource source;
  final String? scopeId;
  final bool forceNetwork;
}

class _RecordingLiveSite extends LiveSite {
  _RecordingLiveSite({required this.records, this.onRequested});

  final List<_KuaishouTraceRecord> records;
  final void Function(String roomId)? onRequested;

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    records.add(
      _KuaishouTraceRecord(
        roomId: roomId,
        source: KuaishouRequestTrace.current,
        scopeId: KuaishouRequestTrace.scopeId,
        forceNetwork: KuaishouRequestTrace.forceNetwork,
      ),
    );
    onRequested?.call(roomId);
    return LiveRoomDetail(
      roomId: roomId,
      title: 'title-$roomId',
      cover: 'cover-$roomId',
      userName: 'user-$roomId',
      userAvatar: 'avatar-$roomId',
      online: 1,
      status: false,
      url: '',
    );
  }
}

/// 记录 cancelScope 调用的快手站点，用于验证取消路径与请求侧 scope 一致。
class _RecordingKuaishouSite extends KuaishouSite {
  _RecordingKuaishouSite(this.cancelledScopes);

  final List<String> cancelledScopes;

  @override
  void cancelScope(String scopeId) {
    cancelledScopes.add(scopeId);
  }
}

/// 覆盖 Hive 依赖，避免单测初始化真实数据库。
class _TestDBService extends DBService {
  @override
  Future addFollow(FollowUser follow) async {}

  @override
  Future addFollows(Iterable<FollowUser> follows) async {}

  @override
  Future deleteFollow(String id) async {}

  @override
  bool getFollowExist(String id) => false;

  @override
  List<FollowUser> getFollowList() => const [];

  @override
  History? getHistory(String id) => null;

  @override
  Future addOrUpdateHistory(History history) async {}
}

/// 覆盖 onInit 以跳过 LocalStorageService/Hive 初始化。
class _TestAppSettingsController extends AppSettingsController {
  @override
  // 单测环境没有 Hive，设置项全部使用默认值。
  // ignore: must_call_super
  void onInit() {}
}

Site _fakeSite(String siteId, LiveSite liveSite, int index) {
  return Site(
    id: siteId,
    name: 'test-$siteId',
    logo: '',
    liveSite: liveSite,
    index: index,
  );
}

FollowUser _followItem({
  required String siteId,
  required String roomId,
}) {
  final item = FollowUser(
    id: '${siteId}_$roomId',
    roomId: roomId,
    siteId: siteId,
    userName: 'user-$roomId',
    face: '',
    addTime: DateTime.now(),
  );
  item.liveStatus.value = 2;
  return item;
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<AppSettingsController>(_TestAppSettingsController());
    Get.put<CurrentRoomService>(CurrentRoomService());
    Get.put<DBService>(_TestDBService());
  });

  tearDown(() {
    Get.reset();
  });

  group('FollowUserService 快手详情补齐来源标记', () {
    test('refreshVisiblePreviews 对快手 getRoomDetail 标记 followStatus '
        '与 follow-refresh scope，非快手项不标记', () async {
      final kuaishouRecords = <_KuaishouTraceRecord>[];
      final bilibiliRecords = <_KuaishouTraceRecord>[];
      final originalKuaishou = Sites.allSites[Constant.kKuaishou]!;
      final originalBilibili = Sites.allSites[Constant.kBiliBili]!;
      Sites.allSites[Constant.kKuaishou] = _fakeSite(
        Constant.kKuaishou,
        _RecordingLiveSite(records: kuaishouRecords),
        originalKuaishou.index,
      );
      Sites.allSites[Constant.kBiliBili] = _fakeSite(
        Constant.kBiliBili,
        _RecordingLiveSite(records: bilibiliRecords),
        originalBilibili.index,
      );

      final service = FollowUserService();
      try {
        await service.refreshVisiblePreviews(
          [
            _followItem(siteId: Constant.kKuaishou, roomId: 'ks-1'),
            _followItem(siteId: Constant.kBiliBili, roomId: 'bili-1'),
          ],
          force: true,
        );
      } finally {
        Sites.allSites[Constant.kKuaishou] = originalKuaishou;
        Sites.allSites[Constant.kBiliBili] = originalBilibili;
      }

      expect(kuaishouRecords, hasLength(1));
      expect(kuaishouRecords.single.roomId, 'ks-1');
      expect(kuaishouRecords.single.source, KuaishouRequestSource.followStatus);
      expect(kuaishouRecords.single.scopeId, 'kuaishou:follow-refresh');
      expect(kuaishouRecords.single.forceNetwork, isTrue);

      expect(bilibiliRecords, hasLength(1));
      expect(bilibiliRecords.single.roomId, 'bili-1');
      expect(bilibiliRecords.single.source, KuaishouRequestSource.unknown);
      expect(bilibiliRecords.single.scopeId, isNull);
      expect(bilibiliRecords.single.forceNetwork, isFalse);
    });

    test('请求 scope 与关注页退出/服务关闭时的 cancelScope 字符串一致', () {
      const requestScope = 'kuaishou:follow-refresh';
      final cancelledScopes = <String>[];
      final originalKuaishou = Sites.allSites[Constant.kKuaishou]!;
      Sites.allSites[Constant.kKuaishou] = _fakeSite(
        Constant.kKuaishou,
        _RecordingKuaishouSite(cancelledScopes),
        originalKuaishou.index,
      );

      final service = FollowUserService();
      try {
        service.onFollowPageExited();
        service.onClose();
      } finally {
        Sites.allSites[Constant.kKuaishou] = originalKuaishou;
      }

      // onFollowPageExited 与 onClose 各取消一次；必须与请求侧 scopeId 相同，
      // 离开关注页后挂起的快手请求才能被协调器取消。
      expect(cancelledScopes, [requestScope, requestScope]);
    });
  });

  group('LiveRoomController loadData 快手进房来源标记', () {
    test('快手房间 getRoomDetail 运行在 userEnter 来源的 zone 内', () async {
      final kuaishouRecords = <_KuaishouTraceRecord>[];
      final requested = Completer<void>();
      final originalKuaishou = Sites.allSites[Constant.kKuaishou]!;
      Sites.allSites[Constant.kKuaishou] = _fakeSite(
        Constant.kKuaishou,
        _RecordingLiveSite(
          records: kuaishouRecords,
          onRequested: (_) => requested.complete(),
        ),
        originalKuaishou.index,
      );

      final controller = LiveRoomController(
        pSite: Sites.allSites[Constant.kKuaishou]!,
        pRoomId: 'ks-live-1',
      );
      try {
        controller.loadData();
        await requested.future;
        // loadData 为 void async，flush 其余微任务让详情赋值与弹幕初始化完成。
        await Future<void>.delayed(Duration.zero);

        expect(kuaishouRecords, hasLength(1));
        expect(kuaishouRecords.single.roomId, 'ks-live-1');
        expect(kuaishouRecords.single.source, KuaishouRequestSource.userEnter);
        expect(kuaishouRecords.single.scopeId, isNull);
        expect(kuaishouRecords.single.forceNetwork, isFalse);
        expect(controller.detail.value, isNotNull);
        expect(controller.detail.value!.roomId, 'ks-live-1');
      } finally {
        Sites.allSites[Constant.kKuaishou] = originalKuaishou;
      }
    });

    test('非快手房间 getRoomDetail 不带来源标记', () async {
      final bilibiliRecords = <_KuaishouTraceRecord>[];
      final requested = Completer<void>();
      final originalBilibili = Sites.allSites[Constant.kBiliBili]!;
      Sites.allSites[Constant.kBiliBili] = _fakeSite(
        Constant.kBiliBili,
        _RecordingLiveSite(
          records: bilibiliRecords,
          onRequested: (_) => requested.complete(),
        ),
        originalBilibili.index,
      );

      final controller = LiveRoomController(
        pSite: Sites.allSites[Constant.kBiliBili]!,
        pRoomId: 'bili-live-1',
      );
      try {
        controller.loadData();
        await requested.future;
        await Future<void>.delayed(Duration.zero);

        expect(bilibiliRecords, hasLength(1));
        expect(bilibiliRecords.single.roomId, 'bili-live-1');
        expect(bilibiliRecords.single.source, KuaishouRequestSource.unknown);
        expect(bilibiliRecords.single.scopeId, isNull);
        expect(controller.detail.value, isNotNull);
      } finally {
        Sites.allSites[Constant.kBiliBili] = originalBilibili;
      }
    });
  });
}
