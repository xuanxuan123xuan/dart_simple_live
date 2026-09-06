import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/services/bulk_data_import_service.dart';
import 'package:simple_live_app/services/current_room_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';
import 'package:simple_live_app/services/live_notification_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/ohos_document_service.dart';
import 'package:simple_live_app/services/ohos_follow_widget_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

int? followStatusForLiveState(LiveStatusState state) {
  return switch (state) {
    LiveStatusState.live => 2,
    LiveStatusState.offline => 1,
    LiveStatusState.unknown => null,
  };
}

/// 关注直播状态快照：跨进程重启复用最近一次刷新结果，
/// 避免快速重开 App 时重复全量刷新（降低风控风险）。
class FollowStatusSnapshot {
  const FollowStatusSnapshot({
    required this.completedAt,
    required this.statuses,
  });

  final DateTime completedAt;

  /// follow id -> liveStatus（0=未知 1=未开播 2=直播中）
  final Map<String, int> statuses;

  Map<String, dynamic> toJson() => {
        'completedAt': completedAt.toIso8601String(),
        'statuses': statuses,
      };

  static FollowStatusSnapshot? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final completedAt =
        DateTime.tryParse(json['completedAt']?.toString() ?? "");
    if (completedAt == null) return null;
    final raw = json['statuses'];
    if (raw is! Map) return null;
    final statuses = <String, int>{};
    raw.forEach((key, value) {
      if (key == null) return;
      final parsed = int.tryParse(value?.toString() ?? "");
      if (parsed != null) {
        statuses[key.toString()] = parsed;
      }
    });
    return FollowStatusSnapshot(
      completedAt: completedAt,
      statuses: statuses,
    );
  }

  static FollowStatusSnapshot? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return fromJson(decoded is Map<String, dynamic> ? decoded : null);
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());

  bool isFreshWithin(Duration window, {DateTime? now}) {
    final checkedAt = now ?? DateTime.now();
    if (completedAt.isAfter(checkedAt)) return false;
    return checkedAt.difference(completedAt) < window;
  }

  /// 快照是否覆盖全部关注（关注列表有增删时视为不完整）。
  bool coversAll(Iterable<FollowUser> items) {
    return items.every((item) => statuses.containsKey(item.id));
  }
}

/// All sites refresh visible live-room metadata instead of allowing historical
/// follow data to remain authoritative indefinitely.
bool shouldRefreshFollowMetadata(String _) => true;

/// Follow previews are display caches, not long-lived room metadata. Keep the
/// same short freshness window for every site so a platform cannot remain
/// stuck on an old title, cover, anchor name, or avatar.
Duration followPreviewCacheTtl(String _) => const Duration(minutes: 2);

bool isFollowPreviewMetadataStale(
  FollowUser item, {
  DateTime? now,
}) {
  if (item.roomTitle.trim().isEmpty ||
      item.roomCover.trim().isEmpty ||
      item.userName.trim().isEmpty ||
      item.face.trim().isEmpty) {
    return true;
  }
  final updatedAt = item.previewUpdatedAt;
  if (updatedAt == null) {
    return true;
  }
  final checkedAt = now ?? DateTime.now();
  if (updatedAt.isAfter(checkedAt)) {
    return true;
  }
  return checkedAt.difference(updatedAt) >= followPreviewCacheTtl(item.siteId);
}

bool applyFollowPreviewDetail(
  FollowUser item,
  LiveRoomDetail detail, {
  DateTime? updatedAt,
}) {
  final title = detail.title.trim();
  final cover = detail.cover.trim();
  final userName = detail.userName.trim();
  final avatar = detail.userAvatar.trim();
  final hasMetadata = title.isNotEmpty ||
      cover.isNotEmpty ||
      userName.isNotEmpty ||
      avatar.isNotEmpty;
  if (!hasMetadata) return false;

  if (title.isNotEmpty) item.roomTitle = title;
  if (cover.isNotEmpty) item.roomCover = cover;
  if (userName.isNotEmpty) item.userName = userName;
  if (avatar.isNotEmpty) item.face = avatar;
  item.previewUpdatedAt = updatedAt ?? DateTime.now();
  return true;
}

class FollowService extends GetxService {
  static const Duration updateStatusCooldown = Duration(seconds: 30);
  static const Duration enterRefreshReuseWindow = Duration(minutes: 2);
  static const Duration refreshProgressCompletionHold = Duration(seconds: 2);
  static const int kDouyinLimitedAutoResumeMaxAttempts = 2;
  static const Duration kDouyinLimitedAutoResumeBaseDelay = Duration(
    seconds: 45,
  );
  static const int kFollowProgressUiBurstThreshold = 500;
  static const String _refreshTaskStateStorageKey =
      LocalStorageService.kFollowRefreshTaskState;
  static const String _refreshTaskTargetsStorageKey =
      LocalStorageService.kFollowRefreshTaskTargets;
  static const String _statusSnapshotStorageKey =
      LocalStorageService.kFollowStatusSnapshot;
  StreamSubscription<dynamic>? subscription;
  static FollowService get instance => Get.find<FollowService>();
  Timer? _eventReloadTimer;

  final StreamController _updatedListController = StreamController.broadcast();
  Stream get updatedListStream => _updatedListController.stream;
  final Set<String> _previewRefreshingKeys = <String>{};

  /// 关注用户列表
  RxList<FollowUser> followList = RxList<FollowUser>();

  /// 直播中的用户列表
  RxList<FollowUser> liveList = RxList<FollowUser>();

  /// 未直播的用户列表
  RxList<FollowUser> notLiveList = RxList<FollowUser>();

  /// 本轮未取得明确状态（含刷新中/受限）的用户。
  RxList<FollowUser> unknownList = RxList<FollowUser>();

  /// 用户自定义的tag
  RxList<FollowUserTag> followTagList = RxList<FollowUserTag>();

  /// 当前tag的用户列表
  RxList<FollowUser> curTagFollowList = RxList<FollowUser>();

  /// 是否正在更新
  var updating = false.obs;
  var refreshProgress = const FollowRefreshProgress.idle().obs;

  Timer? updateTimer;
  Timer? _refreshProgressResetTimer;
  final Set<String> _liveNotifySentIds = <String>{};
  final Set<String> _liveNotifyReadyIds = <String>{};
  int _updateGeneration = 0;
  DateTime? _lastUpdateStatusStartedAt;

  @override
  void onInit() {
    subscription = EventBus.instance.listen(Constant.kUpdateFollow, (p0) {
      _eventReloadTimer?.cancel();
      _eventReloadTimer = Timer(const Duration(milliseconds: 150), () {
        loadData(updateStatus: false);
      });
    });
    _initializeLiveNotificationBaselines();
    if ((Platform.isAndroid || Platform.isIOS) &&
        DBService.instance
            .getFollowList()
            .any((item) => item.isSpecialFollow)) {
      unawaited(LiveNotificationService.requestPermissionIfNeeded());
    }
    initTimer();
    super.onInit();
  }

  void _initializeLiveNotificationBaselines() {
    for (final item in DBService.instance.getFollowList()) {
      if (!item.isSpecialFollow) {
        continue;
      }
      _liveNotifyReadyIds.add(item.id);
      if (item.liveStatus.value == 2) {
        _liveNotifySentIds.add(item.id);
      }
    }
  }

  // 添加标签
  Future<void> addFollowUserTag(String tag) async {
    // 判断待添加tag是否已存在，存在则return
    if (followTagList.any((item) => item.tag == tag)) {
      SmartDialog.showToast("标签名重复，修改失败");
      return;
    }
    FollowUserTag item = await DBService.instance.addFollowTag(tag);
    followTagList.add(item);
  }

  // 删除标签
  Future<void> delFollowUserTag(FollowUserTag tag) async {
    followTagList.remove(tag);
    await DBService.instance.deleteFollowTag(tag.id);
  }

  // 获取用户自定义标签列表
  void getAllTagList() {
    var list = DBService.instance.getFollowTagList();
    followTagList.assignAll(list);
  }

  // 修改标签
  void updateFollowUserTag(FollowUserTag tag) {
    DBService.instance.updateFollowTag(tag);
    // 查找并修改
    var index = followTagList.indexWhere((oTag) => oTag.id == tag.id);
    followTagList[index] = tag;
  }

  // 根据标签筛选数据
  void filterDataByTag(FollowUserTag tag) {
    curTagFollowList.clear();
    // 用一个新的列表来存储需要删除的 userId
    List<String> toRemove = [];
    for (var id in tag.userId) {
      if (followList.any((x) => x.id == id)) {
        // 找到对应的 followUser 添加到 curTagFollowList
        curTagFollowList.add(followList.firstWhere((x) => x.id == id));
      } else {
        // 标记要删除的 id
        toRemove.add(id);
      }
    }
    // 双向确认用户取消关注后标签内是否还有该用户
    // 在遍历结束后统一移除不在 followList 中的 id
    tag.userId.removeWhere((id) => toRemove.contains(id));
    // 更新数据库
    if (toRemove.isNotEmpty) {
      DBService.instance.updateFollowTag(tag);
    }
    curTagFollowList.assignAll(sortFollowUsers(curTagFollowList));
  }

  // 添加关注
  Future<void> addFollow(FollowUser follow) async {
    await DBService.instance.addFollow(follow);
  }

  Future<void> updateSpecialFollow(FollowUser follow, bool value) async {
    follow.isSpecialFollow = value;
    if (value) {
      await LiveNotificationService.requestPermissionIfNeeded();
      if (follow.liveStatus.value != 0) {
        _liveNotifyReadyIds.add(follow.id);
      }
      if (follow.liveStatus.value == 2) {
        _liveNotifySentIds.add(follow.id);
      }
    } else {
      _liveNotifySentIds.remove(follow.id);
    }
    await DBService.instance.addFollow(follow);
    filterData();
  }

  void initTimer() {
    if (AppSettingsController.instance.autoUpdateFollowEnable.value) {
      updateTimer?.cancel();
      updateTimer = Timer.periodic(
        Duration(
            minutes:
                AppSettingsController.instance.autoUpdateFollowDuration.value),
        (timer) {
          Log.logPrint("Update Follow Timer");
          loadData();
        },
      );
    } else {
      updateTimer?.cancel();
    }
  }

  Future<void> loadData({
    bool updateStatus = true,
    bool forceUpdateStatus = false,
  }) async {
    var list = DBService.instance.getFollowList();
    getAllTagList();
    if (list.isEmpty) {
      updating.value = false;
      _resetRefreshProgress();
      followList.assignAll(list);
      return;
    }
    followList.assignAll(list);
    _restoreStatusSnapshotIfFresh();
    if (updateStatus) {
      unawaited(startUpdateStatus(force: forceUpdateStatus));
    }
  }

  /// 快照仍新鲜且覆盖全部关注时，恢复上次刷新出的直播状态，
  /// 让进页复用窗口跨进程生效（快速重开 App 不再重复刷新）。
  void _restoreStatusSnapshotIfFresh() {
    final snapshot = _loadStatusSnapshot();
    if (snapshot == null) return;
    _statusSnapshot = snapshot;
    if (!snapshot.isFreshWithin(enterRefreshReuseWindow)) return;
    if (!snapshot.coversAll(followList)) {
      Log.logPrint("关注列表与状态快照不一致，放弃复用并照常刷新");
      return;
    }
    for (final item in followList) {
      final status = snapshot.statuses[item.id];
      if (status != null && item.liveStatus.value == 0) {
        item.liveStatus.value = status;
      }
    }
    Log.logPrint("已恢复 ${snapshot.statuses.length} 条关注状态快照");
  }

  /// 当前快照是否可用于跳过一次进页全量状态刷新。
  bool hasFreshStatusSnapshotFor(Iterable<FollowUser> items) {
    final snapshot = _statusSnapshot ??= _loadStatusSnapshot();
    if (snapshot == null) return false;
    if (!snapshot.isFreshWithin(enterRefreshReuseWindow)) return false;
    return snapshot.coversAll(items);
  }

  FollowStatusSnapshot? _statusSnapshot;

  void _persistStatusSnapshot() {
    try {
      final snapshot = FollowStatusSnapshot(
        completedAt: DateTime.now(),
        statuses: {
          for (final item in followList) item.id: item.liveStatus.value,
        },
      );
      _statusSnapshot = snapshot;
      unawaited(
        LocalStorageService.instance
            .setValue(_statusSnapshotStorageKey, snapshot.encode()),
      );
    } catch (e) {
      Log.logPrint("保存关注状态快照失败: $e");
    }
  }

  FollowStatusSnapshot? _loadStatusSnapshot() {
    try {
      final raw = LocalStorageService.instance
          .getValue<String>(_statusSnapshotStorageKey, "");
      return FollowStatusSnapshot.decode(raw);
    } catch (e) {
      Log.logPrint("读取关注状态快照失败: $e");
      return null;
    }
  }

  /// 获取关注刷新并发数。
  /// 0 = 自动，自动最多 4；手动 1-8 直接生效。
  int getOptimalConcurrency({
    int? totalCount,
  }) {
    final count = totalCount ?? followList.length;
    if (count <= 0) {
      return 1;
    }
    final manual =
        AppSettingsController.instance.effectiveUpdateFollowThreadCount;
    if (manual > 0) {
      return manual.clamp(1, count).toInt();
    }
    // Status requests are lightweight and no longer wait for room metadata.
    // Four workers keep the common 50-item page responsive without creating
    // the larger bursts allowed by the manual 5-8 settings.
    final concurrency = count < 4 ? count : 4;
    return concurrency.clamp(1, count).toInt();
  }

  String _getConcurrencyMode() {
    final manual =
        AppSettingsController.instance.effectiveUpdateFollowThreadCount;
    return manual > 0 ? "手动($manual)" : "自动";
  }

  /// 按平台交错排列，避免单一平台阻塞
  List<FollowUser> interleaveByPlatform(List<FollowUser> list) {
    // 按平台分组
    var grouped = <String, Queue<FollowUser>>{};
    for (var item in list) {
      grouped.putIfAbsent(item.siteId, () => Queue<FollowUser>()).add(item);
    }

    // 交错处理
    var result = <FollowUser>[];
    while (grouped.values.any((queue) => queue.isNotEmpty)) {
      for (var queue in grouped.values) {
        if (queue.isNotEmpty) {
          result.add(queue.removeFirst());
        }
      }
    }

    return result;
  }

  List<FollowUser> deprioritizeCurrentRoom(List<FollowUser> items) {
    final currentKey = CurrentRoomService.instance.currentKey;
    if (currentKey.isEmpty) {
      return items;
    }
    final currentItems = <FollowUser>[];
    final others = <FollowUser>[];
    for (final item in items) {
      final itemKey = "${item.siteId}_${item.roomId}";
      if (itemKey == currentKey) {
        currentItems.add(item);
      } else {
        others.add(item);
      }
    }
    return [...others, ...currentItems];
  }

  List<String> _orderedRefreshSiteIds(Iterable<String> siteIds) {
    const preferredOrder = <String>[
      Constant.kBiliBili,
      Constant.kHuya,
      Constant.kDouyu,
      Constant.kDouyin,
      Constant.kKuaishou,
    ];
    final seen = <String>{};
    final result = <String>[];
    for (final siteId in preferredOrder) {
      if (siteIds.contains(siteId) && seen.add(siteId)) {
        result.add(siteId);
      }
    }
    final remaining = siteIds.where((siteId) => seen.add(siteId)).toList()
      ..sort();
    result.addAll(remaining);
    return result;
  }

  List<FollowUser> _orderRefreshBucketBySite(
    List<FollowUser> items, {
    bool moveCurrentRoomToEnd = false,
  }) {
    final grouped = <String, List<FollowUser>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.siteId, () => <FollowUser>[]).add(item);
    }
    final ordered = <FollowUser>[];
    for (final siteId in _orderedRefreshSiteIds(grouped.keys)) {
      var bucket = sortFollowUsers(grouped[siteId] ?? const <FollowUser>[]);
      if (moveCurrentRoomToEnd) {
        bucket = deprioritizeCurrentRoom(bucket);
      }
      ordered.addAll(bucket);
    }
    return ordered;
  }

  List<FollowUser> _buildOrderedRefreshTargets(Iterable<FollowUser> items) {
    final uniqueItems = _distinctFollowUsers(items);
    final specials = uniqueItems.where((item) => item.isSpecialFollow).toList();
    final normals = uniqueItems.where((item) => !item.isSpecialFollow).toList();
    final orderedSpecials = interleaveByPlatform(
      _orderRefreshBucketBySite(specials),
    );
    final orderedNormals = interleaveByPlatform(
      _orderRefreshBucketBySite(
        normals,
        moveCurrentRoomToEnd: true,
      ),
    );
    return [...orderedSpecials, ...orderedNormals];
  }

  Duration _douyinLimitedAutoResumeDelay(int attempt) {
    return Duration(
      seconds: kDouyinLimitedAutoResumeBaseDelay.inSeconds * attempt,
    );
  }

  Future<void> startUpdateStatus({bool force = false}) async {
    return refreshSelectedStatus(
      followList,
      includeAllNormals: true,
      force: force,
      scope: FollowRefreshScope.all(automatic: !force),
      allowDetailRefresh: force,
    );
  }

  void cancelFollowPageRefresh() {
    _updateGeneration++;
    (Sites.allSites[Constant.kKuaishou]?.liveSite as KuaishouSite?)
        ?.cancelScope('kuaishou:follow-refresh');
  }

  Future<_FollowRefreshItemResult> _updateLiveStatus(
    FollowUser item, {
    int? generation,
    DouyinFollowRefreshLimiter? douyinLimiter,
    KuaishouFollowRefreshLimiter? kuaishouLimiter,
    int workerIndex = 0,
    bool pauseRemainingOnLimited = false,
  }) async {
    final previousStatus = item.liveStatus.value;
    final notifyReady = _liveNotifyReadyIds.contains(item.id);
    var kuaishouAcquired = false;
    String? attemptedKuaishouSession;
    item.liveCheckState.value = FollowLiveCheckState.refreshing;
    try {
      if (item.siteId == Constant.kDouyin && douyinLimiter != null) {
        await douyinLimiter.beforeRequest(workerIndex);
      }
      var site = Sites.allSites[item.siteId]!;
      if (item.siteId == Constant.kKuaishou && kuaishouLimiter != null) {
        await kuaishouLimiter.beforeRequest();
        kuaishouAcquired = true;
        if (Get.isRegistered<KuaishouAccountService>()) {
          // A persisted anonymous mode may become eligible for recovery while
          // the app is running. Synchronize the site transport before
          // recording which account owns this batch attempt.
          KuaishouAccountService.instance.refreshAvailability();
        }
        attemptedKuaishouSession =
            (site.liveSite as KuaishouSite).activeAccountSessionKey;
      }
      // Status is the latency-sensitive path. Metadata is refreshed in a
      // separate bounded stage after every visible status has been updated.
      final liveState = item.siteId == Constant.kKuaishou
          ? await KuaishouRequestTrace.run(
              KuaishouRequestSource.followStatus,
              () => (site.liveSite as KuaishouSite)
                  .getFollowLiveStatusState(roomId: item.roomId),
              scopeId: 'kuaishou:follow-refresh',
              forceNetwork: true,
            )
          : await site.liveSite.getLiveStatusState(roomId: item.roomId);
      final nextStatus = followStatusForLiveState(liveState);
      if (nextStatus == null) {
        item.liveCheckState.value = FollowLiveCheckState.unknown;
        return const _FollowRefreshItemResult(
          _FollowRefreshItemOutcome.deferred,
        );
      }
      final isLiving = nextStatus == 2;
      if (generation != null && generation != _updateGeneration) {
        return const _FollowRefreshItemResult(
            _FollowRefreshItemOutcome.deferred);
      }
      if (item.siteId == Constant.kDouyin && douyinLimiter != null) {
        douyinLimiter.onSuccess();
      }
      item.liveStatus.value = nextStatus;
      item.liveCheckState.value = FollowLiveCheckState.fresh;
      if (!isLiving) {
        item.liveStartTime = null;
        _liveNotifySentIds.remove(item.id);
      }
      if (item.isSpecialFollow &&
          notifyReady &&
          previousStatus != 2 &&
          item.liveStatus.value == 2 &&
          !_liveNotifySentIds.contains(item.id)) {
        _liveNotifySentIds.add(item.id);
        unawaited(LiveNotificationService.showLiveStart(item));
      }
      _liveNotifyReadyIds.add(item.id);
      return const _FollowRefreshItemResult(_FollowRefreshItemOutcome.success);
    } catch (e) {
      if (generation != null && generation != _updateGeneration) {
        return const _FollowRefreshItemResult(
            _FollowRefreshItemOutcome.deferred);
      }
      var limited = false;
      if (_isDouyinLimited(item, e)) {
        limited = true;
        if (douyinLimiter != null) {
          douyinLimiter.onLimited();
          _handleDouyinLimited(
            pauseRemainingOnLimited: pauseRemainingOnLimited,
          );
        } else {
          _handleDouyinLimited(
            pauseRemainingOnLimited: pauseRemainingOnLimited,
          );
        }
      }
      final kuaishouFailureStatus = _kuaishouBatchFailureStatus(item, e);
      if (kuaishouFailureStatus != null) {
        limited = true;
        var switched = false;
        if (Get.isRegistered<KuaishouAccountService>() &&
            attemptedKuaishouSession != null) {
          final accounts = KuaishouAccountService.instance;
          if (kuaishouFailureStatus == 0) {
            switched =
                accounts.activeSession?.slot.name != attemptedKuaishouSession;
          } else {
            switched = accounts.failoverFollowBatch(
              attemptedSessionKey: attemptedKuaishouSession,
              statusCode: kuaishouFailureStatus,
            );
          }
        }
        item.liveCheckState.value = FollowLiveCheckState.limited;
        if (kuaishouFailureStatus == 403) {
          SmartDialog.showToast("快手返回安全验证页面，请稍后重试");
        }
        return _FollowRefreshItemResult(
          _FollowRefreshItemOutcome.deferred,
          limited: true,
          keepPending: true,
          pauseRemaining: true,
          restartWithFallback: switched,
          stopBatch: !switched,
        );
      }
      Log.logPrint(e);
      if (limited) {
        item.liveCheckState.value = FollowLiveCheckState.limited;
        if (pauseRemainingOnLimited) {
          return const _FollowRefreshItemResult(
            _FollowRefreshItemOutcome.deferred,
            limited: true,
            keepPending: true,
            pauseRemaining: true,
          );
        }
        return const _FollowRefreshItemResult(
          _FollowRefreshItemOutcome.deferred,
          limited: true,
          keepPending: true,
        );
      }
      item.liveCheckState.value = FollowLiveCheckState.unknown;
      if (item.siteId != Constant.kKuaishou) {
        item.liveStatus.value = 0;
        item.liveStartTime = null;
      }
      return _FollowRefreshItemResult(
        _FollowRefreshItemOutcome.failed,
        limited: limited,
      );
    } finally {
      if (kuaishouAcquired) {
        kuaishouLimiter?.afterRequest();
      }
    }
  }

  Future<void> _reconcileDouyinFollowIdentity(
    FollowUser item,
    dynamic liveSite, {
    required bool isLiving,
    required int? generation,
    LiveRoomDetail? detail,
  }) async {
    final resolvedDetail =
        detail ?? await liveSite.getRoomDetail(roomId: item.roomId);
    if (generation != null && generation != _updateGeneration) {
      return;
    }
    final resolvedRoomId = resolvedDetail.roomId.trim();
    if (resolvedRoomId.isNotEmpty && resolvedRoomId != item.roomId) {
      final oldId = item.id;
      final newId = "${item.siteId}_$resolvedRoomId";
      await DBService.instance.deleteFollow(oldId);
      item.id = newId;
      item.roomId = resolvedRoomId;
      await DBService.instance.addFollow(item);
      await _migrateFollowTagReferences(oldId, newId);
    }
    applyFollowPreviewDetail(item, resolvedDetail);
    item.liveStatus.value = resolvedDetail.status ? 2 : 1;
    item.liveStartTime =
        resolvedDetail.status && isLiving ? resolvedDetail.showTime : null;
    if (item.liveStatus.value != 2) {
      _liveNotifySentIds.remove(item.id);
    }
    await DBService.instance.addFollow(item);
  }

  Future<void> syncFollowStatusFromRoomDetail(
    LiveRoomDetail detail, {
    required String siteId,
  }) async {
    final followId = '${siteId}_${detail.roomId}';
    if (!DBService.instance.getFollowExist(followId)) {
      return;
    }
    final item = DBService.instance.followBox.get(followId);
    if (item == null) {
      return;
    }

    item.liveStatus.value = detail.status ? 2 : 1;
    item.liveCheckState.value = FollowLiveCheckState.fresh;
    if (!detail.status) {
      item.liveStartTime = null;
      _liveNotifySentIds.remove(item.id);
    } else if (item.liveStartTime != detail.showTime) {
      item.liveStartTime = detail.showTime;
    }
    await DBService.instance.addFollow(item);
  }

  Future<void> _migrateFollowTagReferences(String oldId, String newId) async {
    if (oldId == newId) {
      return;
    }
    for (final tag in followTagList) {
      final index = tag.userId.indexOf(oldId);
      if (index < 0) {
        continue;
      }
      tag.userId[index] = newId;
      final deduplicated = <String>{};
      tag.userId.removeWhere((id) => !deduplicated.add(id));
      await DBService.instance.updateFollowTag(tag);
    }
  }

  bool _isDouyinLimited(FollowUser item, Object error) {
    return item.siteId == Constant.kDouyin &&
        error is CoreError &&
        error.statusCode == 444;
  }

  /// Returns 0 when another in-flight request already switched the account.
  int? _kuaishouBatchFailureStatus(FollowUser item, Object error) {
    if (item.siteId != Constant.kKuaishou) return null;
    if (error is KuaishouCooldownError) return 0;
    if (error is! CoreError) return null;
    return switch (error.statusCode) {
      401 || 403 || 429 => error.statusCode,
      _ => null,
    };
  }

  void _handleDouyinLimited({required bool pauseRemainingOnLimited}) {
    if (pauseRemainingOnLimited) {
      Log.w("抖音访问受限，已自动降速并保留剩余任务供后续继续");
      return;
    }
    Log.w("抖音访问受限，已自动降速并继续处理剩余任务");
  }

  int compareFollowUsers(FollowUser a, FollowUser b) {
    final aBucket = _sortBucket(a);
    final bBucket = _sortBucket(b);
    final liveCompare = aBucket.compareTo(bBucket);
    if (liveCompare != 0) {
      return liveCompare;
    }
    return b.addTime.compareTo(a.addTime);
  }

  int _sortBucket(FollowUser item) {
    final isLiving = item.liveStatus.value == 2;
    if (item.isSpecialFollow) {
      return isLiving ? 0 : 1;
    }
    return isLiving ? 2 : 3;
  }

  List<FollowUser> sortFollowUsers(Iterable<FollowUser> items) {
    return items.toList()..sort(compareFollowUsers);
  }

  List<FollowUser> _distinctFollowUsers(Iterable<FollowUser> items) {
    final result = <FollowUser>[];
    final seenIds = <String>{};
    for (final item in items) {
      final uniqueId = item.id.trim().isNotEmpty
          ? item.id.trim()
          : "${item.siteId}_${item.roomId}";
      if (seenIds.add(uniqueId)) {
        result.add(item);
      }
    }
    return result;
  }

  List<FollowUser> _buildRefreshTargets(
    Iterable<FollowUser> normalTargets, {
    bool includeAllNormals = false,
  }) {
    final specials = followList.where((item) => item.isSpecialFollow).toList();
    final normals = includeAllNormals
        ? followList.where((item) => !item.isSpecialFollow).toList()
        : normalTargets.where((item) => !item.isSpecialFollow).toList();
    return _distinctFollowUsers([
      ...sortFollowUsers(specials),
      ...sortFollowUsers(normals),
    ]);
  }

  List<FollowUser> buildPageFrontTargets(Iterable<FollowUser> pageItems) {
    return _distinctFollowUsers(sortFollowUsers(pageItems));
  }

  String buildPageRefreshScopeKey(String pageKey) => "page:$pageKey";

  String _refreshTargetKey(FollowUser item) {
    final uniqueId = item.id.trim().isNotEmpty
        ? item.id.trim()
        : "${item.siteId}_${item.roomId}";
    return "${item.siteId}|${item.roomId}|$uniqueId";
  }

  bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  _PersistedFollowRefreshTaskState? _loadPersistedRefreshTask(String scopeKey) {
    try {
      final rawState = LocalStorageService.instance.getValue(
        _refreshTaskStateStorageKey,
        "",
      );
      final rawTargets = LocalStorageService.instance.getValue(
        _refreshTaskTargetsStorageKey,
        "",
      );
      if (rawState.isEmpty || rawTargets.isEmpty) {
        return null;
      }
      final stateMap = jsonDecode(rawState);
      final targetsMap = jsonDecode(rawTargets);
      if (stateMap is! Map || targetsMap is! Map) {
        return null;
      }
      final state = _PersistedFollowRefreshTaskState.fromMaps(
        stateMap.cast<String, dynamic>(),
        targetsMap.cast<String, dynamic>(),
      );
      if (state.scopeKey != scopeKey) {
        return null;
      }
      return state;
    } catch (e) {
      Log.w("读取关注刷新续跑状态失败: $e");
      return null;
    }
  }

  Future<void> _persistRefreshTask({
    required FollowRefreshScope scope,
    required int total,
    required List<String> orderedKeys,
    required List<String> pendingKeys,
    required int successCount,
    required int failedCount,
    required int deferredCount,
  }) async {
    if (!scope.includeAllNormals) {
      return;
    }
    final statePayload = {
      "scopeKey": scope.scopeKey,
      "total": total,
      "successCount": successCount,
      "failedCount": failedCount,
      "deferredCount": deferredCount,
      "updatedAt": DateTime.now().toIso8601String(),
    };
    final targetPayload = {
      "orderedKeys": orderedKeys,
      "pendingKeys": pendingKeys,
    };
    await LocalStorageService.instance.setValue(
      _refreshTaskStateStorageKey,
      jsonEncode(statePayload),
    );
    await LocalStorageService.instance.setValue(
      _refreshTaskTargetsStorageKey,
      jsonEncode(targetPayload),
    );
    // Fix Windows crash on exit: 频繁写入导致localstorage.hive膨胀到2GB，
    // 应用退出时写入LastLiveRoom触发STATUS_STACK_BUFFER_OVERRUN(0xC0000409)
    // 每次persist后尝试compact，失败则忽略，不阻塞刷新流程
    try {
      await LocalStorageService.instance.settingsBox.compact();
    } catch (e) {
      // compact失败不影响刷新，静默忽略
    }
  }

  Future<void> _clearPersistedRefreshTask() async {
    await LocalStorageService.instance.removeValue(_refreshTaskStateStorageKey);
    await LocalStorageService.instance
        .removeValue(_refreshTaskTargetsStorageKey);
  }

  List<FollowUser> _buildManualDetailTargets(List<FollowUser> items) {
    final candidates = _distinctFollowUsers(
      items.where(
        (item) => item.siteId == Constant.kDouyin || item.liveStatus.value == 2,
      ),
    );
    return _orderRefreshBucketBySite(candidates);
  }

  List<FollowUser> _buildPreviewTargets(
    Iterable<FollowUser> items, {
    bool force = false,
  }) {
    return _orderRefreshBucketBySite(
      _distinctFollowUsers(
        items.where((item) {
          if (item.liveStatus.value != 2) {
            return false;
          }
          final targetKey = _refreshTargetKey(item);
          if (_previewRefreshingKeys.contains(targetKey)) {
            return false;
          }
          if (force) {
            return true;
          }
          return isFollowPreviewMetadataStale(item);
        }),
      ),
    );
  }

  Future<void> refreshVisiblePreviews(
    Iterable<FollowUser> pageItems, {
    bool force = false,
  }) async {
    final targets = _buildPreviewTargets(pageItems, force: force);
    if (targets.isEmpty) {
      return;
    }
    final keys = targets.map(_refreshTargetKey).toList(growable: false);
    _previewRefreshingKeys.addAll(keys);
    try {
      await _refreshMetadataTargets(
        targets,
        scope: const FollowRefreshScope(
          scopeKey: "preview",
          includeAllNormals: false,
          automatic: true,
          allowBackgroundSpecials: false,
          stage: "正在补齐封面与标题",
          backgroundStage: "",
        ),
        stage: "正在补齐封面与标题",
        refreshProgressUi: false,
        reconcileDouyinIdentity: true,
      );
    } finally {
      _previewRefreshingKeys.removeAll(keys);
    }
  }

  Future<FollowUser> resolveFollowBeforeEnter(FollowUser item) async {
    if (item.siteId != Constant.kDouyin) {
      return item;
    }
    await _refreshMetadataTargets(
      [item],
      scope: const FollowRefreshScope(
        scopeKey: "room-enter",
        includeAllNormals: false,
        automatic: false,
        allowBackgroundSpecials: false,
        stage: "正在校正直播间",
        backgroundStage: "",
      ),
      stage: "正在校正直播间",
      refreshProgressUi: false,
      reconcileDouyinIdentity: true,
    );
    return item;
  }

  Future<void> _refreshMetadataTargets(
    List<FollowUser> targets, {
    required FollowRefreshScope scope,
    required String stage,
    required bool refreshProgressUi,
    required bool reconcileDouyinIdentity,
  }) async {
    final metadataTargets =
        targets.where((item) => shouldRefreshFollowMetadata(item.siteId));
    if (metadataTargets.isEmpty) {
      return;
    }
    final orderedTargets = _orderRefreshBucketBySite(
      _distinctFollowUsers(metadataTargets.toList(growable: false)),
    );
    final generation = _updateGeneration;
    var completed = 0;
    var successCount = 0;
    var failedCount = 0;
    var changed = false;

    void updateProgress({required bool done}) {
      if (!refreshProgressUi) {
        return;
      }
      final detail = [
        "成功 $successCount",
        if (failedCount > 0) "失败 $failedCount",
      ].join("  ");
      _setRefreshProgress(
        active: !done,
        automatic: scope.automatic,
        scopeKey: scope.scopeKey,
        stage: stage,
        current: completed,
        total: orderedTargets.length,
        successCount: successCount,
        failedCount: failedCount,
        detail: detail,
        completed: done,
      );
    }

    Future<void> worker(
      Queue<FollowUser> queue, {
      required bool isDouyinQueue,
    }) async {
      while (queue.isNotEmpty) {
        if (generation != _updateGeneration) {
          return;
        }
        final item = queue.removeFirst();
        try {
          final site = Sites.allSites[item.siteId]!;
          final detail = await site.liveSite.getRoomDetail(roomId: item.roomId);
          if (generation != _updateGeneration) {
            return;
          }
          if (reconcileDouyinIdentity && isDouyinQueue) {
            await _reconcileDouyinFollowIdentity(
              item,
              site.liveSite,
              isLiving: item.liveStatus.value == 2 || detail.status,
              generation: generation,
              detail: detail,
            );
          } else {
            changed = applyFollowPreviewDetail(item, detail) || changed;
            if (detail.status && item.liveStartTime != detail.showTime) {
              item.liveStartTime = detail.showTime;
              changed = true;
            }
            await DBService.instance.addFollow(item);
          }
          changed = true;
          successCount++;
        } catch (e) {
          if (generation != _updateGeneration) {
            return;
          }
          failedCount++;
          Log.logPrint("关注详情补齐失败(${item.siteId}/${item.roomId}): $e");
        } finally {
          completed++;
          updateProgress(done: false);
        }
      }
    }

    if (refreshProgressUi) {
      _cancelRefreshProgressReset();
      updating.value = true;
      _setRefreshProgress(
        active: true,
        automatic: scope.automatic,
        scopeKey: scope.scopeKey,
        stage: stage,
        current: 0,
        total: orderedTargets.length,
      );
      Log.logPrint(
        "关注详情补齐阶段开始，目标数: ${orderedTargets.length}，scope=${scope.scopeKey}",
      );
    }

    try {
      final douyinTargets = orderedTargets
          .where((item) => item.siteId == Constant.kDouyin)
          .toList(growable: false);
      final otherTargets = orderedTargets
          .where((item) => item.siteId != Constant.kDouyin)
          .toList(growable: false);
      for (final group in [douyinTargets, otherTargets]) {
        if (group.isEmpty) {
          continue;
        }
        final queue = Queue<FollowUser>.from(group);
        final isDouyinQueue = group.first.siteId == Constant.kDouyin;
        final workerCount =
            isDouyinQueue ? 1 : group.length.clamp(1, 2).toInt();
        final workers = <Future<void>>[];
        for (var i = 0; i < workerCount; i++) {
          workers.add(worker(queue, isDouyinQueue: isDouyinQueue));
        }
        await Future.wait(workers);
        if (generation != _updateGeneration) {
          return;
        }
      }
      if (changed) {
        filterData();
      }
      updateProgress(done: true);
      if (refreshProgressUi) {
        Log.logPrint(
          "关注详情补齐阶段完成，成功: $successCount，失败: $failedCount，scope=${scope.scopeKey}",
        );
      }
    } finally {
      if (refreshProgressUi && generation == _updateGeneration) {
        updating.value = false;
        _finishRefreshProgressLifecycle(generation);
      }
    }
  }

  _RefreshTargetPolicyResult _applyDouyinRefreshPolicy(
    List<FollowUser> orderedTargets, {
    required FollowRefreshScope scope,
    required bool hasFullDouyinCookie,
  }) {
    return _RefreshTargetPolicyResult(
      allowedTargets: orderedTargets,
      deferredTargets: const [],
      toastMessage:
          hasFullDouyinCookie ? "" : "抖音未登录时将自动降速刷新；若出现 444，会暂停并保留剩余任务供后续继续。",
    );
  }

  Future<void> refreshSelectedStatus(
    Iterable<FollowUser> normalTargets, {
    bool includeAllNormals = false,
    bool force = true,
    FollowRefreshScope? scope,
    bool allowDetailRefresh = true,
  }) async {
    final resolvedScope = scope ??
        FollowRefreshScope.all(
          automatic: !force,
        );
    final targets = resolvedScope.includeAllNormals
        ? _buildRefreshTargets(
            normalTargets,
            includeAllNormals: includeAllNormals,
          )
        : buildPageFrontTargets(normalTargets);
    await _refreshStatusTargets(
      targets,
      force: force,
      scope: resolvedScope,
    );
    if (!allowDetailRefresh || resolvedScope.automatic || targets.isEmpty) {
      return;
    }
    final detailTargets = _buildManualDetailTargets(targets);
    await _refreshMetadataTargets(
      detailTargets,
      scope: resolvedScope,
      stage: "正在补齐封面与标题",
      refreshProgressUi: true,
      reconcileDouyinIdentity: true,
    );
  }

  Future<void> _refreshStatusTargets(
    List<FollowUser> targets, {
    bool force = false,
    required FollowRefreshScope scope,
  }) async {
    final now = DateTime.now();
    final lastStartedAt = _lastUpdateStatusStartedAt;
    if (!force &&
        lastStartedAt != null &&
        now.difference(lastStartedAt) < updateStatusCooldown) {
      Log.logPrint("关注状态刷新仍在冷却中，跳过本次自动刷新");
      updating.value = false;
      _resetRefreshProgress();
      filterData();
      return;
    }
    if (updating.value &&
        refreshProgress.value.active &&
        refreshProgress.value.scopeKey == scope.scopeKey &&
        !refreshProgress.value.completed) {
      Log.logPrint("同一刷新任务仍在进行，复用当前进度: ${scope.scopeKey}");
      return;
    }
    _lastUpdateStatusStartedAt = now;
    final generation = ++_updateGeneration;
    final automatic = scope.automatic;
    _cancelRefreshProgressReset();
    if (updating.value) {
      Log.logPrint("新的关注刷新任务已启动，旧任务将按 generation 自动退出: ${scope.scopeKey}");
    }
    updating.value = true;
    _setRefreshProgress(
      active: true,
      automatic: automatic,
      scopeKey: scope.scopeKey,
      stage: scope.stage,
      current: 0,
      total: targets.length,
    );

    if (targets.isEmpty) {
      updating.value = false;
      _resetRefreshProgress();
      filterData();
      return;
    }

    try {
      var concurrency = getOptimalConcurrency(
        totalCount: targets.length,
      );
      final policy = BulkDataImportService.policyForCount(targets.length);
      final hasFullDouyinCookie = DouyinCookieHelper.hasFullCookie(
        (Sites.allSites[Constant.kDouyin]?.liveSite as DouyinSite?)?.cookie ??
            "",
      );

      Log.logPrint(
        "关注状态阶段开始，并发数: $concurrency，模式: ${_getConcurrencyMode()}，目标数: ${targets.length}，策略: ${policy.label}，"
        "scope=${scope.scopeKey} fullDouyinCookie=$hasFullDouyinCookie",
      );

      final orderedTargets = _buildOrderedRefreshTargets(targets);
      final filteredTargets = _applyDouyinRefreshPolicy(
        orderedTargets,
        scope: scope,
        hasFullDouyinCookie: hasFullDouyinCookie,
      );
      final allowedTargets = filteredTargets.allowedTargets;
      final orderedAllowedKeys = allowedTargets.map(_refreshTargetKey).toList();
      final targetByKey = <String, FollowUser>{
        for (final item in allowedTargets) _refreshTargetKey(item): item,
      };
      final persistedTask = _loadPersistedRefreshTask(scope.scopeKey);
      final resumeTask = scope.includeAllNormals &&
          persistedTask != null &&
          _sameStringList(persistedTask.orderedKeys, orderedAllowedKeys) &&
          persistedTask.pendingKeys.isNotEmpty;
      final pendingKeys = resumeTask
          ? persistedTask.pendingKeys
              .where(targetByKey.containsKey)
              .toList(growable: true)
          : orderedAllowedKeys.toList(growable: true);
      final isHugeTask = targets.length >= kFollowProgressUiBurstThreshold;
      final douyinTargetCount = filteredTargets.allowedTargets
          .where((item) => item.siteId == Constant.kDouyin)
          .length;
      final douyinLimiter = douyinTargetCount > 0
          ? DouyinFollowRefreshLimiter.forTargetCount(douyinTargetCount)
          : null;
      final kuaishouTargetCount = filteredTargets.allowedTargets
          .where((item) => item.siteId == Constant.kKuaishou)
          .length;
      final kuaishouLimiter = kuaishouTargetCount > 0
          ? KuaishouFollowRefreshLimiter(targetCount: kuaishouTargetCount)
          : null;
      final resumedSuccessCount = persistedTask?.successCount ?? 0;
      final resumedFailedCount = persistedTask?.failedCount ?? 0;
      var completed = resumeTask ? resumedSuccessCount + resumedFailedCount : 0;
      var successCount = resumeTask ? resumedSuccessCount : 0;
      var failedCount = resumeTask ? resumedFailedCount : 0;
      var deferredCount = filteredTargets.deferredTargets.length;
      var limitedCount = 0;
      var pausedForResume = false;
      var restartWithKuaishouFallback = false;
      var stopForKuaishouLimit = false;
      var autoResumeAttempt = 0;

      if (scope.includeAllNormals) {
        unawaited(
          _persistRefreshTask(
            scope: scope,
            total: targets.length,
            orderedKeys: orderedAllowedKeys,
            pendingKeys: pendingKeys,
            successCount: successCount,
            failedCount: failedCount,
            deferredCount: deferredCount,
          ),
        );
      }

      if (filteredTargets.deferredTargets.isNotEmpty) {
        Log.w(
          "抖音全量刷新受限：scope=${scope.scopeKey} deferred=$deferredCount "
          "allowedDouyin=$douyinTargetCount requiresFullCookie=true",
        );
        if (filteredTargets.toastMessage.isNotEmpty) {
          SmartDialog.showToast(filteredTargets.toastMessage);
        }
      }
      if (resumeTask) {
        Log.logPrint(
          "继续上次未完成的全量关注刷新：scope=${scope.scopeKey} remaining=$pendingKeys.length",
        );
      }

      void updateProgress({required bool active, required bool done}) {
        final detail = [
          "成功 $successCount",
          if (failedCount > 0) "失败 $failedCount",
          if (deferredCount > 0) "待续跑 $deferredCount",
        ].join("  ");
        _setRefreshProgress(
          active: active,
          automatic: automatic,
          scopeKey: scope.scopeKey,
          stage: scope.stage,
          current: completed,
          total: targets.length,
          successCount: successCount,
          failedCount: failedCount,
          deferredCount: deferredCount,
          detail: detail,
          completed: done,
        );
      }

      updateProgress(active: true, done: false);

      while (pendingKeys.isNotEmpty) {
        final taskQueue = Queue<FollowUser>.from(
          pendingKeys.map((key) => targetByKey[key]).whereType<FollowUser>(),
        );
        pausedForResume = false;
        restartWithKuaishouFallback = false;

        Future<void> worker(int workerId) async {
          while (taskQueue.isNotEmpty) {
            if (generation != _updateGeneration || pausedForResume) {
              return;
            }
            var item = taskQueue.removeFirst();
            final result = await _updateLiveStatus(
              item,
              generation: generation,
              douyinLimiter: douyinLimiter,
              kuaishouLimiter: kuaishouLimiter,
              workerIndex: workerId,
              pauseRemainingOnLimited: scope.includeAllNormals,
            );
            if (generation != _updateGeneration) {
              return;
            }
            if (result.limited) {
              limitedCount++;
            }
            final targetKey = _refreshTargetKey(item);
            if (!result.keepPending) {
              pendingKeys.remove(targetKey);
            }

            switch (result.outcome) {
              case _FollowRefreshItemOutcome.success:
                successCount++;
                completed++;
                break;
              case _FollowRefreshItemOutcome.failed:
                failedCount++;
                completed++;
                break;
              case _FollowRefreshItemOutcome.deferred:
              case _FollowRefreshItemOutcome.skipped:
                break;
            }
            if (result.pauseRemaining) {
              pausedForResume = true;
              restartWithKuaishouFallback =
                  restartWithKuaishouFallback || result.restartWithFallback;
              stopForKuaishouLimit = stopForKuaishouLimit || result.stopBatch;
              for (final key in pendingKeys) {
                final pendingItem = targetByKey[key];
                if (result.stopBatch &&
                    pendingItem?.siteId == Constant.kKuaishou) {
                  pendingItem!.liveCheckState.value =
                      FollowLiveCheckState.limited;
                }
              }
              deferredCount =
                  filteredTargets.deferredTargets.length + pendingKeys.length;
            }
            final shouldCheckpoint = completed % 10 == 0 ||
                pendingKeys.isEmpty ||
                result.pauseRemaining;
            if (scope.includeAllNormals && !isHugeTask && shouldCheckpoint) {
              unawaited(
                _persistRefreshTask(
                  scope: scope,
                  total: targets.length,
                  orderedKeys: orderedAllowedKeys,
                  pendingKeys: pendingKeys,
                  successCount: successCount,
                  failedCount: failedCount,
                  deferredCount: deferredCount,
                ),
              );
            }
            if (!isHugeTask || completed % 20 == 0 || pendingKeys.isEmpty) {
              updateProgress(active: true, done: false);
            }
          }
        }

        var workers = <Future>[];
        for (var i = 0; i < concurrency; i++) {
          workers.add(worker(i));
        }
        await Future.wait(workers);

        if (generation != _updateGeneration) {
          return;
        }
        if (stopForKuaishouLimit) {
          Log.w("快手主备账号均不可用，已停止本轮剩余关注刷新");
          SmartDialog.showToast("快手主备账号均受限，已停止本轮刷新");
          break;
        }
        if (restartWithKuaishouFallback) {
          Log.w("快手当前账号受限，已切换备用账号继续剩余任务");
          SmartDialog.showToast("快手账号受限，已切换备用账号继续刷新");
          deferredCount = filteredTargets.deferredTargets.length;
          continue;
        }
        if (!pausedForResume || pendingKeys.isEmpty) {
          break;
        }
        if (!scope.includeAllNormals ||
            autoResumeAttempt >= kDouyinLimitedAutoResumeMaxAttempts) {
          break;
        }
        autoResumeAttempt++;
        final resumeDelay = _douyinLimitedAutoResumeDelay(autoResumeAttempt);
        Log.w(
          "抖音刷新触发限流，${resumeDelay.inSeconds}s后自动续刷剩余${pendingKeys.length}项 "
          "scope=${scope.scopeKey} attempt=$autoResumeAttempt",
        );
        updateProgress(active: true, done: false);
        await Future.delayed(resumeDelay);
        if (generation != _updateGeneration) {
          return;
        }
        deferredCount = filteredTargets.deferredTargets.length;
      }

      if (generation != _updateGeneration) {
        return;
      }
      if (douyinLimiter != null) {
        final summary = douyinLimiter.finish(douyinTargetCount);
        Log.logPrint(
          "抖音关注刷新总结 scope=${scope.scopeKey} target=${summary.targetCount} "
          "startConcurrency=${summary.initialConcurrency} "
          "startInterval=${summary.initialInterval.inMilliseconds}ms "
          "finalInterval=${summary.finalInterval.inMilliseconds}ms "
          "success=${summary.successCount} limited=${summary.limitedCount} "
          "cooldown=${summary.cooledDown} elapsed=${summary.elapsed.inMilliseconds}ms "
          "failed=$failedCount deferred=$deferredCount limitedObserved=$limitedCount",
        );
      }
      if (pendingKeys.isNotEmpty) {
        if (scope.includeAllNormals) {
          deferredCount =
              filteredTargets.deferredTargets.length + pendingKeys.length;
        } else {
          failedCount += pendingKeys.length;
          completed += pendingKeys.length;
          pendingKeys.clear();
          deferredCount = filteredTargets.deferredTargets.length;
        }
      }
      updateProgress(active: false, done: true);
      if (scope.includeAllNormals) {
        if (pendingKeys.isEmpty) {
          await _clearPersistedRefreshTask();
        } else {
          await _persistRefreshTask(
            scope: scope,
            total: targets.length,
            orderedKeys: orderedAllowedKeys,
            pendingKeys: pendingKeys,
            successCount: successCount,
            failedCount: failedCount,
            deferredCount: deferredCount,
          );
        }
      }
      filterData();

      Log.logPrint("关注状态阶段完成");
    } finally {
      if (generation == _updateGeneration) {
        updating.value = false;
        _finishRefreshProgressLifecycle(generation);
        // 仅全量刷新范围才落盘快照；单页刷新不能代表全部关注的状态。
        if (scope.includeAllNormals) {
          _persistStatusSnapshot();
        }
        // 刷新收尾后同步鸿蒙服务卡片快照（非鸿蒙平台内部短路）。
        unawaited(OhosFollowWidgetService.syncSnapshot(followList));
      }
    }
  }

  void _setRefreshProgress({
    required bool active,
    required bool automatic,
    required String scopeKey,
    required String stage,
    required int current,
    required int total,
    int successCount = 0,
    int failedCount = 0,
    int deferredCount = 0,
    int skippedCount = 0,
    bool completed = false,
    bool background = false,
    String detail = "",
  }) {
    refreshProgress.value = FollowRefreshProgress(
      active: active,
      automatic: automatic,
      scopeKey: scopeKey,
      stage: stage,
      current: current.clamp(0, total).toInt(),
      total: total,
      successCount: successCount,
      failedCount: failedCount,
      deferredCount: deferredCount,
      skippedCount: skippedCount,
      completed: completed,
      background: background,
      detail: detail,
    );
  }

  void _resetRefreshProgress() {
    _cancelRefreshProgressReset();
    refreshProgress.value = const FollowRefreshProgress.idle();
  }

  void _cancelRefreshProgressReset() {
    _refreshProgressResetTimer?.cancel();
    _refreshProgressResetTimer = null;
  }

  void _finishRefreshProgressLifecycle(int generation) {
    if (refreshProgress.value.completed) {
      _scheduleRefreshProgressReset(generation);
      return;
    }
    _resetRefreshProgress();
  }

  void _scheduleRefreshProgressReset(int generation) {
    _cancelRefreshProgressReset();
    _refreshProgressResetTimer = Timer(
      refreshProgressCompletionHold,
      () {
        if (generation != _updateGeneration) {
          return;
        }
        if (updating.value || !refreshProgress.value.completed) {
          return;
        }
        _resetRefreshProgress();
      },
    );
  }

  void filterData() {
    followList.assignAll(sortFollowUsers(followList));
    liveList.assignAll(
      sortFollowUsers(followList.where((x) => x.liveStatus.value == 2)),
    );
    notLiveList.assignAll(
      sortFollowUsers(followList.where((x) => x.liveStatus.value == 1)),
    );
    unknownList.assignAll(
      sortFollowUsers(followList.where((x) => x.liveStatus.value == 0)),
    );
    _updatedListController.add(0);
  }

  void exportFile() async {
    if (followList.isEmpty) {
      SmartDialog.showToast("列表为空");
      return;
    }

    try {
      var status = await Utils.checkStorgePermission();
      if (!status) {
        SmartDialog.showToast("无权限");
        return;
      }

      final fileName =
          'SimpleLive_${DateTime.now().millisecondsSinceEpoch ~/ 1000}.json';
      final jsonText = generateJson();
      if (Utils.isOhos) {
        final saved = await OhosDocumentService.saveText(
          fileName: fileName,
          extension: 'json',
          content: jsonText,
        );
        if (saved) {
          SmartDialog.showToast("已导出关注列表");
        }
        return;
      }

      var dir = "";
      if (Platform.isIOS) {
        dir = (await getApplicationDocumentsDirectory()).path;
      } else {
        dir = await FilePicker.platform.getDirectoryPath() ?? "";
      }

      if (dir.isEmpty) {
        return;
      }
      var jsonFile = File('$dir/$fileName');
      await jsonFile.writeAsString(jsonText);
      SmartDialog.showToast("已导出关注列表");
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("导出失败：$e");
    }
  }

  void inputFile() async {
    try {
      var status = await Utils.checkStorgePermission();
      if (!status) {
        SmartDialog.showToast("无权限");
        return;
      }
      var file = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) {
        return;
      }
      var jsonFile = File(file.files.single.path!);
      await inputJson(await jsonFile.readAsString());
      SmartDialog.showToast("导入成功");
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("导入失败:$e");
    } finally {
      loadData(updateStatus: false);
    }
  }

  void exportText() {
    if (followList.isEmpty) {
      SmartDialog.showToast("列表为空");
      return;
    }
    var content = generateJson();
    Utils.showDialogSafe<dynamic>(
      context: Get.context!,
      builder: (_) => AlertDialog(
        title: const Text("导出为文本"),
        content: TextField(
          controller: TextEditingController(text: content),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          minLines: 5,
          maxLines: 8,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
            },
            child: const Text("关闭"),
          ),
          TextButton(
            onPressed: () {
              Utils.copyToClipboard(content);
              Get.back();
            },
            child: const Text("复制"),
          ),
        ],
      ),
    );
  }

  void inputText() async {
    final TextEditingController textController = TextEditingController();
    await Utils.showDialogSafe<dynamic>(
      context: Get.context!,
      builder: (_) => AlertDialog(
        title: const Text("从文本导入"),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: "请输入内容",
          ),
          minLines: 5,
          maxLines: 8,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
            },
            child: const Text("关闭"),
          ),
          TextButton(
            onPressed: () async {
              var content = await Utils.getClipboard();
              if (content != null) {
                textController.text = content;
              }
            },
            child: const Text("粘贴"),
          ),
          TextButton(
            onPressed: () async {
              if (textController.text.isEmpty) {
                SmartDialog.showToast("内容为空");
                return;
              }
              try {
                await inputJson(textController.text);
                SmartDialog.showToast("导入成功");
                Get.back();
                loadData(updateStatus: false);
              } catch (e) {
                SmartDialog.showToast("导入失败，请检查内容是否正确");
              }
            },
            child: const Text("导入"),
          ),
        ],
      ),
    );
  }

  String generateJson() {
    var data = followList
        .map(
          (item) => {
            "siteId": item.siteId,
            "id": item.id,
            "roomId": item.roomId,
            "userName": item.userName,
            "face": item.face,
            "addTime": item.addTime.toString(),
            "tag": item.tag,
            "isSpecialFollow": item.isSpecialFollow
          },
        )
        .toList();
    return jsonEncode(data);
  }

  Future inputJson(String content) async {
    var data = jsonDecode(content);
    if (data is! List) {
      throw const FormatException("关注列表格式不是数组");
    }
    final stopwatch = Stopwatch()..start();
    final result = await BulkDataImportService.importFollowUsers(
      data,
      syncTagsFromUserField: true,
    );
    stopwatch.stop();
    Log.i(
      "文本/文件关注导入完成：${result.logSummary} elapsed=${stopwatch.elapsedMilliseconds}ms",
    );
  }

  @override
  void onClose() {
    cancelFollowPageRefresh();
    updating.value = false;
    _cancelRefreshProgressReset();
    _resetRefreshProgress();
    updateTimer?.cancel();
    _eventReloadTimer?.cancel();
    subscription?.cancel();
    super.onClose();
  }
}

enum _FollowRefreshItemOutcome {
  success,
  failed,
  deferred,
  skipped,
}

class _FollowRefreshItemResult {
  final _FollowRefreshItemOutcome outcome;
  final bool limited;
  final bool keepPending;
  final bool pauseRemaining;
  final bool restartWithFallback;
  final bool stopBatch;

  const _FollowRefreshItemResult(
    this.outcome, {
    this.limited = false,
    this.keepPending = false,
    this.pauseRemaining = false,
    this.restartWithFallback = false,
    this.stopBatch = false,
  });
}

class _RefreshTargetPolicyResult {
  final List<FollowUser> allowedTargets;
  final List<FollowUser> deferredTargets;
  final String toastMessage;

  const _RefreshTargetPolicyResult({
    required this.allowedTargets,
    required this.deferredTargets,
    this.toastMessage = "",
  });
}

class _PersistedFollowRefreshTaskState {
  final String scopeKey;
  final int total;
  final int successCount;
  final int failedCount;
  final int deferredCount;
  final List<String> orderedKeys;
  final List<String> pendingKeys;

  const _PersistedFollowRefreshTaskState({
    required this.scopeKey,
    required this.total,
    required this.successCount,
    required this.failedCount,
    required this.deferredCount,
    required this.orderedKeys,
    required this.pendingKeys,
  });

  factory _PersistedFollowRefreshTaskState.fromMaps(
    Map<String, dynamic> state,
    Map<String, dynamic> targets,
  ) {
    List<String> readList(dynamic value) {
      if (value is! List) {
        return const [];
      }
      return value.map((item) => item.toString()).toList();
    }

    return _PersistedFollowRefreshTaskState(
      scopeKey: state["scopeKey"]?.toString() ?? "",
      total: (state["total"] as num?)?.toInt() ?? 0,
      successCount: (state["successCount"] as num?)?.toInt() ?? 0,
      failedCount: (state["failedCount"] as num?)?.toInt() ?? 0,
      deferredCount: (state["deferredCount"] as num?)?.toInt() ?? 0,
      orderedKeys: readList(targets["orderedKeys"]),
      pendingKeys: readList(targets["pendingKeys"]),
    );
  }
}

/// Allows up to four Kuaishou room-detail flows to enter the core coordinator.
/// The coordinator still serializes sensitive physical requests and applies
/// its global interval, cooldown, and priority policy.
class KuaishouFollowRefreshLimiter {
  KuaishouFollowRefreshLimiter({
    required int targetCount,
    this.maxConcurrency = 4,
  }) : _currentConcurrency = targetCount.clamp(1, maxConcurrency).toInt();

  final int maxConcurrency;
  final int _currentConcurrency;
  int _inFlight = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  int get currentConcurrency => _currentConcurrency;
  int get inFlight => _inFlight;

  Future<void> beforeRequest() async {
    while (_inFlight >= _currentConcurrency) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _inFlight++;
  }

  void afterRequest() {
    if (_inFlight > 0) {
      _inFlight--;
    }
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }
}

class DouyinFollowRefreshLimiter {
  final int initialConcurrency;
  final Duration initialInterval;
  Duration _currentInterval;
  final Stopwatch _stopwatch = Stopwatch()..start();
  Future<void> _gate = Future.value();
  DateTime? _lastRequestAt;
  int _successCount = 0;
  int _limitedCount = 0;
  bool _cooledDown = false;

  DouyinFollowRefreshLimiter._({
    required this.initialConcurrency,
    required this.initialInterval,
  }) : _currentInterval = initialInterval;

  factory DouyinFollowRefreshLimiter.forTargetCount(int targetCount) {
    if (targetCount <= 20) {
      return DouyinFollowRefreshLimiter._(
        initialConcurrency: targetCount.clamp(1, 4).toInt(),
        initialInterval: const Duration(milliseconds: 220),
      );
    }
    if (targetCount <= 100) {
      return DouyinFollowRefreshLimiter._(
        initialConcurrency: 4,
        initialInterval: const Duration(milliseconds: 360),
      );
    }
    return DouyinFollowRefreshLimiter._(
      initialConcurrency: 4,
      initialInterval: const Duration(milliseconds: 520),
    );
  }

  Future<void> beforeRequest(int workerIndex) {
    final next = _gate.then((_) async {
      final lastRequestAt = _lastRequestAt;
      if (lastRequestAt != null) {
        final elapsed = DateTime.now().difference(lastRequestAt);
        if (elapsed < _currentInterval) {
          await Future.delayed(_currentInterval - elapsed);
        }
      }
      _lastRequestAt = DateTime.now();
    });
    _gate = next.catchError((_) {});
    return next;
  }

  void onSuccess() {
    _successCount++;
  }

  void onLimited() {
    _limitedCount++;
    _cooledDown = true;
    final nextMs = (_currentInterval.inMilliseconds * 1.8).round();
    _currentInterval = Duration(
      milliseconds: nextMs.clamp(600, 2600).toInt(),
    );
  }

  DouyinFollowRefreshSummary finish(int targetCount) {
    _stopwatch.stop();
    return DouyinFollowRefreshSummary(
      targetCount: targetCount,
      initialConcurrency: initialConcurrency,
      initialInterval: initialInterval,
      finalInterval: _currentInterval,
      successCount: _successCount,
      limitedCount: _limitedCount,
      cooledDown: _cooledDown,
      elapsed: _stopwatch.elapsed,
    );
  }
}

class DouyinFollowRefreshSummary {
  final int targetCount;
  final int initialConcurrency;
  final Duration initialInterval;
  final Duration finalInterval;
  final int successCount;
  final int limitedCount;
  final bool cooledDown;
  final Duration elapsed;

  const DouyinFollowRefreshSummary({
    required this.targetCount,
    required this.initialConcurrency,
    required this.initialInterval,
    required this.finalInterval,
    required this.successCount,
    required this.limitedCount,
    required this.cooledDown,
    required this.elapsed,
  });
}
