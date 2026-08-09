import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/platform_utils.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_adaptive_quality.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_controller.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_playback_recovery.dart';
import 'package:simple_live_app/modules/multi_room/player_mutation_queue.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/live_link_health_models.dart';
import 'package:simple_live_app/services/memory_pressure_monitor.dart';
import 'package:simple_live_app/services/playback_display_coordinator.dart';
import 'package:simple_live_core/simple_live_core.dart';

class MultiRoomController extends GetxController with WidgetsBindingObserver {
  final List<MultiRoomItem> initialRooms;
  final bool returnToLiveRoom;

  MultiRoomController(
    this.initialRooms, {
    this.returnToLiveRoom = false,
  });

  final rooms = <MultiRoomItem>[].obs;

  /// 顶部工具栏的显示状态。点击画面切换，8 秒自动隐藏。
  var showOverlay = true.obs;

  /// 聊天区面板当前展示的直播间索引（对应 rooms 列表）。
  var chatTargetIndex = 0.obs;

  /// 聊天区宽度占比（0.2-0.6），可拖动边框调整。
  var chatPanelRatio = 0.35.obs;

  /// 拖动聊天区边框调整宽度。
  void changeChatPanelRatio(double ratio) {
    chatPanelRatio.value = ratio.clamp(0.2, 0.6);
  }

  /// 2-4 路直播间的主次布局开关。
  var mainSubLayout = false.obs;

  bool get canToggleMainSubLayout => rooms.length >= 2 && rooms.length <= 4;

  bool get isMainSubLayoutActive =>
      canToggleMainSubLayout && mainSubLayout.value;

  bool get canAddRoom =>
      !PlatformUtils.isMobileApp ||
      rooms.length < PlatformUtils.mobileMultiRoomMax;

  void toggleMainSubLayout() {
    if (!canToggleMainSubLayout) {
      mainSubLayout.value = false;
      return;
    }
    // 布局切换必须先退出单格聚焦，否则底层布局虽已改变，
    // 画面仍会被聚焦分支覆盖，看起来像“按钮没反应”。
    focusedRoomKey.value = null;
    mainSubLayout.value = !mainSubLayout.value;
    showOverlay.value = true;
    _resetAutoHideTimer();
    _scheduleResumePlayers();
  }

  /// 将指定直播间稳定移动到主位，并立即切换为主次布局。
  bool setMainRoom(String roomKey) {
    final oldIndex = rooms.indexWhere((room) => room.key == roomKey);
    if (oldIndex < 0 || !canToggleMainSubLayout) {
      return false;
    }
    final chatTargetKey = _currentChatTargetKey();
    if (oldIndex > 0) {
      final room = rooms.removeAt(oldIndex);
      rooms.insert(0, room);
    }
    _normalizeChatTarget(chatTargetKey, 0);
    mainSubLayout.value = true;
    focusedRoomKey.value = null;
    showOverlay.value = true;
    _resetAutoHideTimer();
    _scheduleResumePlayers();
    return true;
  }

  void _normalizeLayoutAfterRoomChange() {
    if (!canToggleMainSubLayout) {
      mainSubLayout.value = false;
    }
    final focusKey = focusedRoomKey.value;
    if (focusKey != null && !rooms.any((room) => room.key == focusKey)) {
      focusedRoomKey.value = null;
    }
  }

  /// 双击聚焦的单格 key；null = 正常网格。
  final focusedRoomKey = Rxn<String>();

  Timer? _autoHideTimer;
  Timer? _resumeTimer;
  Timer? _adaptiveQualityTimer;
  bool _closing = false;
  bool _appActive = true;
  bool _danmakuSuspendedForLifecycle = false;
  bool _suppressPlayerOpenedResume = false;
  bool _adaptiveEvaluationRunning = false;
  final PlayerMutationQueue _playerMutationQueue = PlayerMutationQueue();
  final MultiRoomPlaybackRecoveryCoordinator _playbackRecovery =
      const MultiRoomPlaybackRecoveryCoordinator();
  int _playbackRecoveryGeneration = 0;
  final MultiRoomAdaptiveQualityController _adaptiveQuality =
      MultiRoomAdaptiveQualityController();
  late final PlaybackDisplayLease _displayLease;

  final allPaused = false.obs;
  final isRefreshingAll = false.obs;
  final refreshProgress = "".obs;
  final openingSingleRoom = false.obs;
  final adaptiveQualityStatus = "".obs;
  final totalBandwidthMbps = Rxn<double>();
  Future<void>? _refreshAllFuture;

  /// 上次多开的布局（恢复用）。
  Map<String, double> _pendingVolumes = {};
  Map<String, bool> _pendingDanmaku = {};
  Map<String, int> _pendingQualities = {};
  Map<String, int> _pendingLines = {};
  int _pendingChatTarget = 0;

  /// 低内存降级中已暂停弹幕的格子 key。
  final Set<String> _degradedKeys = {};

  void toggleOverlay() {
    showOverlay.value = !showOverlay.value;
    _resetAutoHideTimer();
  }

  /// 进入聚焦前的布局状态（退出聚焦时恢复，保证回到进入时的布局）。
  bool? _mainSubLayoutBeforeFocus;

  /// 双击聚焦某格（单独放大）；已聚焦该格时再双击退出聚焦。
  void focusRoom(String key) {
    if (!rooms.any((r) => r.key == key)) return;
    if (focusedRoomKey.value == key) {
      exitFocus();
      return;
    }
    _mainSubLayoutBeforeFocus = mainSubLayout.value;
    focusedRoomKey.value = key;
    showOverlay.value = true;
    _resetAutoHideTimer();
    _scheduleResumePlayers();
  }

  /// 退出聚焦，回到多开网格（恢复进入聚焦时的布局）。
  void exitFocus() {
    final restoreMainSub = _mainSubLayoutBeforeFocus;
    _mainSubLayoutBeforeFocus = null;
    focusedRoomKey.value = null;
    if (restoreMainSub != null) {
      mainSubLayout.value = restoreMainSub;
    }
    showOverlay.value = true;
    _resetAutoHideTimer();
    _scheduleResumePlayers();
  }

  void _resetAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    if (showOverlay.value) {
      _autoHideTimer = Timer(
        const Duration(seconds: 8),
        () {
          if (!_closing && !isClosed) {
            showOverlay.value = false;
          }
        },
      );
    }
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    final distinctRooms = _distinct(initialRooms);
    rooms.assignAll(
      PlatformUtils.isMobileApp &&
              distinctRooms.length > PlatformUtils.mobileMultiRoomMax
          ? distinctRooms.take(PlatformUtils.mobileMultiRoomMax)
          : distinctRooms,
    );
    _restoreLayout(rooms);
    _normalizeChatTarget(null, chatTargetIndex.value);
    _normalizeLayoutAfterRoomChange();
    _resetAutoHideTimer();
    _setupMemoryMonitor();
    _startAdaptiveQualityTimer();
    _displayLease = PlaybackDisplayCoordinator.instance.acquire(
      debugLabel: 'multi-room',
      keepScreenAwake: true,
      immersiveSystemUi: true,
    );
  }

  void _startAdaptiveQualityTimer() {
    _adaptiveQualityTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_evaluateAdaptiveQuality()),
    );
  }

  @override
  void onClose() {
    _closing = true;
    _appActive = false;
    WidgetsBinding.instance.removeObserver(this);
    _autoHideTimer?.cancel();
    _cancelPlaybackRecovery();
    _adaptiveQualityTimer?.cancel();
    _teardownMemoryMonitor();
    _saveLayout();
    _displayLease.dispose();
    for (final item in rooms) {
      final tag = playerTag(item);
      if (Get.isRegistered<MultiRoomPlayerController>(tag: tag)) {
        Get.delete<MultiRoomPlayerController>(tag: tag);
      }
    }
    unawaited(_playerMutationQueue.close());
    super.onClose();
  }

  List<MultiRoomItem> _distinct(Iterable<MultiRoomItem> items) {
    final result = <MultiRoomItem>[];
    final keys = <String>{};
    for (final item in items) {
      if (keys.add(item.key)) {
        result.add(item);
      }
    }
    return result;
  }

  String playerTag(MultiRoomItem item) => item.key;

  MultiRoomPlayerController playerFor(MultiRoomItem item) {
    final tag = playerTag(item);
    final MultiRoomPlayerController existing;
    if (Get.isRegistered<MultiRoomPlayerController>(tag: tag)) {
      existing = Get.find<MultiRoomPlayerController>(tag: tag);
      existing.onActivateAudio = _scheduleResumePlayers;
      return existing;
    }
    if (_closing || isClosed) {
      throw StateError("多开页面已关闭，不能再创建播放器");
    }
    // 持久化状态只在新 controller 构造前消费一次，后续 rebuild 不再覆盖用户操作。
    final playerController = Get.put(
      MultiRoomPlayerController(
        item,
        onPlayerOpened: _onPlayerOpened,
        initialVolume: _pendingVolumes.remove(item.key),
        initialShowDanmaku: _pendingDanmaku.remove(item.key),
        initialQualityIndex: _pendingQualities.remove(item.key),
        initialLineIndex: _pendingLines.remove(item.key),
        initialPaused: allPaused.value,
        mutationQueue: _playerMutationQueue,
      ),
      tag: tag,
    );
    if (AppSettingsController.instance.multiRoomSingleAudio.value &&
        rooms.any((room) {
          if (room.key == item.key) return false;
          final existing = _existingPlayerFor(room);
          return existing != null && !existing.muted.value;
        })) {
      unawaited(playerController.setMuted(true));
    }
    playerController.onActivateAudio = _scheduleResumePlayers;
    return playerController;
  }

  void _onPlayerOpened() {
    if (!_suppressPlayerOpenedResume) {
      _scheduleResumePlayers();
    }
  }

  MultiRoomPlayerController? _existingPlayerFor(MultiRoomItem item) {
    final tag = playerTag(item);
    return Get.isRegistered<MultiRoomPlayerController>(tag: tag)
        ? Get.find<MultiRoomPlayerController>(tag: tag)
        : null;
  }

  String? _currentChatTargetKey() {
    final index = chatTargetIndex.value;
    return index >= 0 && index < rooms.length ? rooms[index].key : null;
  }

  void _normalizeChatTarget([String? preferredKey, int fallbackIndex = 0]) {
    if (rooms.isEmpty) {
      chatTargetIndex.value = 0;
      return;
    }
    final preferredIndex = preferredKey == null
        ? -1
        : rooms.indexWhere((room) => room.key == preferredKey);
    chatTargetIndex.value = preferredIndex >= 0
        ? preferredIndex
        : fallbackIndex.clamp(0, rooms.length - 1).toInt();
  }

  void removeRoom(MultiRoomItem item) {
    final chatTargetKey = _currentChatTargetKey();
    final fallbackIndex = chatTargetIndex.value;
    rooms.removeWhere((room) => room.key == item.key);
    _normalizeChatTarget(chatTargetKey, fallbackIndex);
    _normalizeLayoutAfterRoomChange();
    _degradedKeys.remove(item.key);
    _syncAllPausedState();
    final tag = playerTag(item);
    if (Get.isRegistered<MultiRoomPlayerController>(tag: tag)) {
      Get.delete<MultiRoomPlayerController>(tag: tag);
    }
    if (rooms.isEmpty) {
      SmartDialog.showToast("已关闭全部多开直播间");
      Get.back();
    }
  }

  /// 交换两个房间的位置。
  void swapRooms(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= rooms.length) return;
    if (newIndex < 0 || newIndex >= rooms.length) return;
    final chatTargetKey = _currentChatTargetKey();
    final item = rooms.removeAt(oldIndex);
    rooms.insert(newIndex, item);
    _normalizeChatTarget(chatTargetKey, newIndex);
    _scheduleResumePlayers();
  }

  Future<void> toggleRoomPaused(MultiRoomItem room) async {
    final player = _existingPlayerFor(room) ?? playerFor(room);
    await player.togglePaused();
    _syncAllPausedState();
  }

  Future<void> toggleAllPaused() async {
    final pause = !allPaused.value;
    allPaused.value = pause;
    for (final room in rooms.toList()) {
      final player = _existingPlayerFor(room) ?? playerFor(room);
      await player.setPaused(pause);
    }
  }

  void _syncAllPausedState() {
    if (rooms.isEmpty) {
      allPaused.value = false;
      return;
    }
    allPaused.value = rooms.every((room) {
      final player = _existingPlayerFor(room);
      return player != null && player.paused.value;
    });
  }

  Future<void> toggleRoomAudio(MultiRoomItem room) async {
    final target = _existingPlayerFor(room) ?? playerFor(room);
    if (!target.muted.value) {
      await target.setMuted(true);
      return;
    }
    if (AppSettingsController.instance.multiRoomSingleAudio.value) {
      for (final other in rooms.toList()) {
        if (other.key == room.key) continue;
        final player = _existingPlayerFor(other);
        if (player != null && !player.muted.value) {
          await player.setMuted(true);
        }
      }
    }
    await target.setMuted(false);
  }

  Future<void> muteAll() async {
    for (final room in rooms.toList()) {
      final player = _existingPlayerFor(room);
      if (player != null && !player.muted.value) {
        await player.setMuted(true);
      }
    }
  }

  Future<void> refreshAllRooms() {
    final active = _refreshAllFuture;
    if (active != null) return active;
    final future = _runRefreshAllRooms();
    _refreshAllFuture = future;
    return future.whenComplete(() {
      if (identical(_refreshAllFuture, future)) {
        _refreshAllFuture = null;
      }
    });
  }

  Future<void> _runRefreshAllRooms() async {
    if (_closing || isClosed || isRefreshingAll.value) return;
    isRefreshingAll.value = true;
    _suppressPlayerOpenedResume = true;
    final snapshot = rooms.toList();
    var success = 0;
    var failed = 0;
    try {
      for (var i = 0; i < snapshot.length; i += 1) {
        if (_closing || isClosed || !_appActive) break;
        final room = snapshot[i];
        if (!rooms.any((current) => current.key == room.key)) continue;
        refreshProgress.value = "${i + 1}/${snapshot.length}";
        final result = await playerFor(room).refreshRoom(showToast: false);
        if (result.success) {
          success += 1;
        } else {
          failed += 1;
        }
      }
    } finally {
      _suppressPlayerOpenedResume = false;
      isRefreshingAll.value = false;
      refreshProgress.value = "";
      _scheduleResumePlayers();
    }
    if (!_closing && !isClosed) {
      SmartDialog.showToast(
        failed == 0 ? "已刷新 $success 个直播间" : "刷新完成：$success 成功，$failed 失败",
      );
    }
  }

  Future<void> openFocusedRoomAsSingle() async {
    if (openingSingleRoom.value || _closing || isClosed) return;
    final key = focusedRoomKey.value;
    final room =
        key == null ? null : rooms.firstWhereOrNull((r) => r.key == key);
    if (room == null) return;
    openingSingleRoom.value = true;
    _suppressPlayerOpenedResume = true;
    _resumeTimer?.cancel();
    _adaptiveQualityTimer?.cancel();
    try {
      await _playerMutationQueue.idle;
      for (final current in rooms.toList()) {
        final player = _existingPlayerFor(current);
        if (player != null) {
          await player.closeForRouteTransition();
        }
      }
      if (returnToLiveRoom) {
        Get.back(result: MultiRoomOpenSingleResult(room));
      } else {
        await AppNavigator.toLiveRoomDetail(
          site: room.site,
          roomId: room.roomId,
          replace: true,
        );
      }
    } catch (e, stackTrace) {
      Log.e("多开转单直播间失败: $e", stackTrace);
      SmartDialog.showToast("转到单直播间失败，请重试");
      openingSingleRoom.value = false;
      _suppressPlayerOpenedResume = false;
      // cancel 在 try 之前无条件执行，这里必须无条件重建自适应画质 timer。
      _startAdaptiveQualityTimer();
    }
  }

  Future<void> _evaluateAdaptiveQuality() async {
    if (_closing ||
        isClosed ||
        !_appActive ||
        _adaptiveEvaluationRunning ||
        isRefreshingAll.value ||
        openingSingleRoom.value) {
      return;
    }
    _adaptiveEvaluationRunning = true;
    try {
      final now = DateTime.now();
      final chatKey = _currentChatTargetKey();
      final focusKey = focusedRoomKey.value;
      final roomSnapshot = rooms.toList();
      final samples = <MultiRoomPlaybackTelemetry>[];
      for (var i = 0; i < roomSnapshot.length; i += 1) {
        if (_closing || isClosed || !_appActive) return;
        final room = roomSnapshot[i];
        final player = _existingPlayerFor(room);
        if (player == null) continue;
        final sample = await player.sampleTelemetry(
          sampledAt: now,
          isPrimary: i == 0 && isMainSubLayoutActive,
          isFocused: room.key == focusKey,
          isChatTarget: room.key == chatKey,
        );
        samples.add(sample);
        _logLiveLatencyTelemetry(room, player, sample);
      }
      if (_closing || isClosed || !_appActive) return;
      if (!AppSettingsController.instance.multiRoomAdaptiveQuality.value ||
          // 自动调节只在主次布局（有主画面保护概念）下生效；
          // 普通布局所有格子等大，不自动降级，避免干扰用户观看。
          !isMainSubLayoutActive) {
        return;
      }
      final bandwidthBudgetMbps = PlatformUtils.isMobileApp ? 24.0 : 48.0;
      final decision = _adaptiveQuality.evaluate(
        now: now,
        rooms: samples,
        logicalProcessorCount: Platform.numberOfProcessors,
        memoryEmergency: MemoryPressureMonitor.instance.isDegraded,
        rssBytes: ProcessInfo.currentRss.toDouble(),
        rssBudgetBytes: 1.2 * 1024 * 1024 * 1024,
        bandwidthBudgetBytesPerSecond: bandwidthBudgetMbps * 1000 * 1000 / 8,
      );
      totalBandwidthMbps.value = decision.totalBandwidthBytesPerSecond == null
          ? null
          : decision.totalBandwidthBytesPerSecond! * 8 / 1000 / 1000;
      final action = decision.action;
      adaptiveQualityStatus.value = action == null
          ? ""
          : action.reason == "memory"
              ? "内存保护"
              : "自动优化中";
      if (action == null) return;
      final room = rooms.firstWhereOrNull((item) => item.key == action.roomKey);
      final player = room == null ? null : _existingPlayerFor(room);
      if (player != null) {
        unawaited(
          player.changeQualityAutomatically(action.targetQualityIndex),
        );
      }
    } finally {
      _adaptiveEvaluationRunning = false;
    }
  }

  void _logLiveLatencyTelemetry(
    MultiRoomItem room,
    MultiRoomPlayerController player,
    MultiRoomPlaybackTelemetry sample,
  ) {
    final urls = player.playUrls;
    final lineIndex = player.lineIndex;
    final protocol = lineIndex >= 0 && lineIndex < urls.length
        ? classifyLiveStreamProtocol(urls[lineIndex])
        : LiveStreamProtocol.unknown;
    final cacheLabel = sample.demuxerCacheDurationSeconds == null
        ? 'unsupported'
        : '${sample.demuxerCacheDurationSeconds!.toStringAsFixed(3)}s';
    final openedAt = sample.lastOpenedAt;
    final elapsedLabel = openedAt == null
        ? 'unknown'
        : '${(sample.sampledAt.difference(openedAt).inMilliseconds / 1000).toStringAsFixed(1)}s';
    Log.writeLog(
      '[live-latency] mode=multi target=${room.site.id}/${room.roomId} '
      'line=${lineIndex + 1}/${urls.length} protocol=${protocol.label} '
      'elapsed=$elapsedLabel demuxerCache=$cacheLabel '
      'buffering=${sample.isBuffering} bufferCount=${sample.bufferingCount} '
      'bufferDuration=${(sample.bufferingDuration.inMilliseconds / 1000).toStringAsFixed(1)}s',
    );
  }

  Future<void> _recoverDesiredPlayers(int generation) async {
    if (_isPlaybackRecoveryCancelled(generation)) return;
    final targets = <MultiRoomPlaybackRecoveryTarget>[];
    for (final room in rooms.toList()) {
      final player = _existingPlayerFor(room);
      if (player == null) continue;
      targets.add(
        MultiRoomPlaybackRecoveryTarget(
          roomKey: room.key,
          shouldPlay: () => player.shouldRecoverPlayback,
          isPlaying: () => player.isActuallyPlaying,
          requestPlay: player.ensurePlaying,
          waitUntilPlaying: player.waitUntilActuallyPlaying,
        ),
      );
    }
    await _playbackRecovery.recover(
      targets: targets,
      isCancelled: () => _isPlaybackRecoveryCancelled(generation),
    );
  }

  bool _isPlaybackRecoveryCancelled(int generation) =>
      generation != _playbackRecoveryGeneration ||
      _closing ||
      isClosed ||
      !_appActive;

  void _cancelPlaybackRecovery() {
    _playbackRecoveryGeneration += 1;
    _resumeTimer?.cancel();
    _resumeTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_closing || isClosed) return;
      _appActive = true;
      _recordLiveLinkHealthEventForAll(
        LiveLinkEventType.appForegrounded,
      );
      _scheduleResumePlayers(delay: Duration.zero);
      if (_danmakuSuspendedForLifecycle) {
        _danmakuSuspendedForLifecycle = false;
        _restoreDanmakuAll();
      }
      if (_degradedKeys.isNotEmpty &&
          !MemoryPressureMonitor.instance.isDegraded) {
        unawaited(_recoverMemoryDegradedPlayers());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _appActive = false;
      _recordLiveLinkHealthEventForAll(
        LiveLinkEventType.appBackgrounded,
      );
      _cancelPlaybackRecovery();
      // 后台挂起：断开所有格子弹幕长连接，省心跳与流量，前台恢复。
      if (!_danmakuSuspendedForLifecycle) {
        _danmakuSuspendedForLifecycle = true;
        _suspendDanmakuAll();
      }
    }
  }

  void _recordLiveLinkHealthEventForAll(LiveLinkEventType type) {
    for (final room in rooms) {
      _existingPlayerFor(room)?.recordLiveLinkHealthEvent(type);
    }
  }

  /// 后台挂起：断开所有格子弹幕连接（含降级中的）。
  void _suspendDanmakuAll() {
    for (final room in rooms) {
      final controller = _existingPlayerFor(room);
      if (controller != null) {
        unawaited(controller.degradeDanmaku());
      }
    }
  }

  /// 前台恢复：重建所有格子弹幕连接。
  void _restoreDanmakuAll() {
    for (final room in rooms) {
      if (_degradedKeys.contains(room.key)) continue;
      final controller = _existingPlayerFor(room);
      if (controller != null) {
        unawaited(controller.restoreDanmaku());
      }
    }
  }

  /// 从关注的直播中添加房间。已在多开中的忽略。
  void addRoomFromFollow(FollowUser item) {
    final room = MultiRoomItem.fromFollow(item);
    if (rooms.any((r) => r.key == room.key)) {
      SmartDialog.showToast("${item.userName}已在多开中");
      return;
    }
    if (!canAddRoom) {
      SmartDialog.showToast("移动端最多支持4个直播间");
      return;
    }
    rooms.add(room);
    _normalizeLayoutAfterRoomChange();
    SmartDialog.showToast("已加入 ${item.userName}");
    _scheduleResumePlayers();
  }

  /// 从历史记录中添加房间。
  void addRoomFromHistory(History item) {
    final site = Sites.allSites[item.siteId];
    if (site == null) {
      SmartDialog.showToast("不支持的平台");
      return;
    }
    final room = MultiRoomItem(
      site: site,
      roomId: item.roomId,
      userName: item.userName,
      face: item.face,
    );
    if (rooms.any((r) => r.key == room.key)) {
      SmartDialog.showToast("${item.userName}已在多开中");
      return;
    }
    if (!canAddRoom) {
      SmartDialog.showToast("移动端最多支持4个直播间");
      return;
    }
    rooms.add(room);
    _normalizeLayoutAfterRoomChange();
    SmartDialog.showToast("已加入 ${item.userName}");
    _scheduleResumePlayers();
  }

  /// 任意一格的 Player.open() 会抢占 iOS 共享 audio session 中断其他格，
  /// 延迟到本次 Player 初始化完成后再恢复全部播放器。
  void _scheduleResumePlayers({
    Duration delay = const Duration(milliseconds: 800),
  }) {
    if (_closing || isClosed || !_appActive) return;
    _cancelPlaybackRecovery();
    final generation = _playbackRecoveryGeneration;
    _resumeTimer = Timer(delay, () {
      _resumeTimer = null;
      if (_isPlaybackRecoveryCancelled(generation)) return;
      unawaited(_recoverDesiredPlayers(generation));
    });
  }

  // ==================== 低内存降级 ====================

  void _setupMemoryMonitor() {
    if (!AppSettingsController.instance.multiRoomLowMemoryDegrade.value) {
      return;
    }
    MemoryPressureMonitor.instance.onDegrade = _onMemoryDegrade;
    MemoryPressureMonitor.instance.onRecover = _onMemoryRecover;
    MemoryPressureMonitor.instance.start();
  }

  void _teardownMemoryMonitor() {
    MemoryPressureMonitor.instance.onDegrade = null;
    MemoryPressureMonitor.instance.onRecover = null;
    MemoryPressureMonitor.instance.stop();
  }

  /// 判断某格是否"活跃"（用户正在看：被聚焦或聊天区目标）。
  bool _isActiveRoom(MultiRoomItem room, int index) {
    return focusedRoomKey.value == room.key ||
        (isMainSubLayoutActive && index == 0) ||
        chatTargetIndex.value == index;
  }

  /// 内存压力大：暂停非活跃格子的弹幕；房间数 ≥ 4 时额外降画质。
  void _onMemoryDegrade() {
    if (_closing ||
        isClosed ||
        !AppSettingsController.instance.multiRoomLowMemoryDegrade.value) {
      return;
    }
    _degradedKeys.clear();
    final heavy = rooms.length >= 4;
    for (var i = 0; i < rooms.length; i += 1) {
      final room = rooms[i];
      if (_isActiveRoom(room, i)) {
        continue;
      }
      final c = _existingPlayerFor(room);
      if (c == null) continue;
      _degradedKeys.add(room.key);
      unawaited(c.degradeDanmaku());
      if (heavy) {
        unawaited(c.degradeQuality());
      }
    }
    if (_degradedKeys.isNotEmpty) {
      SmartDialog.showToast(
        "内存占用较高，已暂停 ${_degradedKeys.length} 路非活跃弹幕"
        "${heavy ? '并降低画质' : ''}",
      );
    }
  }

  /// 内存回落：恢复被降级的格子弹幕。
  void _onMemoryRecover() {
    if (_closing || isClosed || !_appActive) return;
    unawaited(_recoverMemoryDegradedPlayers());
  }

  Future<void> _recoverMemoryDegradedPlayers() async {
    if (_closing || isClosed || !_appActive) return;
    for (final key in _degradedKeys.toList()) {
      final room = rooms.firstWhereOrNull((r) => r.key == key);
      final controller = room == null ? null : _existingPlayerFor(room);
      if (controller != null && _appActive && !_danmakuSuspendedForLifecycle) {
        await controller.restoreDanmaku();
        await controller.restoreQualityAfterMemoryPressure();
      }
    }
    _degradedKeys.clear();
    _scheduleResumePlayers();
  }

  // ==================== 布局持久化 ====================

  void _saveLayout() {
    try {
      final data = <String, dynamic>{
        "roomKeys": rooms.map((r) => r.key).toList(),
        "chatTarget": chatTargetIndex.value,
        "chatRatio": chatPanelRatio.value,
        "mainSub": mainSubLayout.value,
        "volumes": {
          for (final r in rooms)
            r.key: _existingPlayerFor(r)?.volume.value ??
                _pendingVolumes[r.key] ??
                100.0,
        },
        "danmaku": {
          for (final r in rooms)
            r.key: _existingPlayerFor(r)?.showDanmaku.value ??
                _pendingDanmaku[r.key] ??
                true,
        },
        "qualities": {
          for (final r in rooms)
            r.key: _existingPlayerFor(r)?.qualityIndex ??
                _pendingQualities[r.key] ??
                -1,
        },
        "lines": {
          for (final r in rooms)
            r.key:
                _existingPlayerFor(r)?.lineIndex ?? _pendingLines[r.key] ?? 0,
        },
      };
      LocalStorageService.instance.setValue(
        LocalStorageService.kMultiRoomLayout,
        jsonEncode(data),
      );
    } catch (e) {
      Log.d("多开布局保存失败: $e");
    }
  }

  void _restoreLayout(RxList<MultiRoomItem> rooms) {
    final raw = LocalStorageService.instance.getValue(
      LocalStorageService.kMultiRoomLayout,
      "",
    );
    if (raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final keys = (data["roomKeys"] as List? ?? const []).cast<String>();
      // 按上次顺序重排。
      if (keys.isNotEmpty) {
        final byKey = {for (final r in rooms) r.key: r};
        final ordered = <MultiRoomItem>[];
        final used = <String>{};
        for (final k in keys) {
          final r = byKey[k];
          if (r != null && used.add(k)) {
            ordered.add(r);
          }
        }
        for (final r in rooms) {
          if (used.add(r.key)) {
            ordered.add(r);
          }
        }
        rooms.assignAll(ordered);
      }
      _pendingChatTarget = (data["chatTarget"] as int?) ?? 0;
      chatTargetIndex.value = _pendingChatTarget;
      final chatRatio = data["chatRatio"];
      if (chatRatio is num) {
        chatPanelRatio.value = chatRatio.toDouble().clamp(0.2, 0.6);
      }
      final mainSub = data["mainSub"];
      if (mainSub is bool) {
        mainSubLayout.value = mainSub;
      }
      final volumes = data["volumes"] as Map? ?? const {};
      _pendingVolumes = {
        for (final e in volumes.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
      };
      final danmaku = data["danmaku"] as Map? ?? const {};
      _pendingDanmaku = {
        for (final e in danmaku.entries)
          if (e.value is bool) e.key.toString(): e.value as bool,
      };
      final qualities = data["qualities"] as Map? ?? const {};
      _pendingQualities = {
        for (final e in qualities.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toInt(),
      };
      final lines = data["lines"] as Map? ?? const {};
      _pendingLines = {
        for (final e in lines.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toInt(),
      };
    } catch (e) {
      Log.d("多开布局恢复失败: $e");
    }
  }
}
