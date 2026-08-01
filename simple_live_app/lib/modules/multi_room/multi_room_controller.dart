import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/memory_pressure_monitor.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class MultiRoomController extends GetxController with WidgetsBindingObserver {
  final List<MultiRoomItem> initialRooms;

  MultiRoomController(this.initialRooms);

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

  bool get canToggleMainSubLayout =>
      rooms.length >= 2 && rooms.length <= 4;

  bool get isMainSubLayoutActive =>
      canToggleMainSubLayout && mainSubLayout.value;

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
  bool _closing = false;
  bool _appActive = true;
  bool _danmakuSuspendedForLifecycle = false;

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

  /// 双击聚焦某格（单独放大）。
  void focusRoom(String key) {
    if (rooms.any((r) => r.key == key)) {
      focusedRoomKey.value = key;
      showOverlay.value = true;
      _resetAutoHideTimer();
    }
  }

  /// 退出聚焦，回到多开网格。
  void exitFocus() {
    focusedRoomKey.value = null;
    showOverlay.value = true;
    _resetAutoHideTimer();
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
    rooms.assignAll(_distinct(initialRooms));
    _restoreLayout(rooms);
    _normalizeChatTarget(null, chatTargetIndex.value);
    _normalizeLayoutAfterRoomChange();
    _resetAutoHideTimer();
    _setupMemoryMonitor();
    unawaited(WakelockPlus.enable());
    unawaited(_hideSystemUi());
  }

  @override
  void onClose() {
    _closing = true;
    _appActive = false;
    WidgetsBinding.instance.removeObserver(this);
    _autoHideTimer?.cancel();
    _resumeTimer?.cancel();
    _teardownMemoryMonitor();
    _saveLayout();
    unawaited(WakelockPlus.disable());
    unawaited(_restoreSystemUi());
    for (final item in rooms) {
      final tag = playerTag(item);
      if (Get.isRegistered<MultiRoomPlayerController>(tag: tag)) {
        Get.delete<MultiRoomPlayerController>(tag: tag);
      }
    }
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
    if (Get.isRegistered<MultiRoomPlayerController>(tag: tag)) {
      return Get.find<MultiRoomPlayerController>(tag: tag);
    }
    if (_closing || isClosed) {
      throw StateError("多开页面已关闭，不能再创建播放器");
    }
    // 持久化状态只在新 controller 构造前消费一次，后续 rebuild 不再覆盖用户操作。
    return Get.put(
      MultiRoomPlayerController(
        item,
        onPlayerOpened: _scheduleResumePlayers,
        initialVolume: _pendingVolumes.remove(item.key),
        initialShowDanmaku: _pendingDanmaku.remove(item.key),
        initialQualityIndex: _pendingQualities.remove(item.key),
        initialLineIndex: _pendingLines.remove(item.key),
      ),
      tag: tag,
    );
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
  }

  /// 恢复所有应播放但已暂停的播放器。
  ///
  /// iOS 上 media_kit/libmpv 多实例共享 audio session：新增 Player 的
  /// open() 会中断正在播放的旧 Player，延迟一段时间后把它拉回来。
  void _resumeAllPlayers() {
    if (_closing || isClosed || !_appActive) return;
    for (final room in rooms) {
      final controller = _existingPlayerFor(room);
      if (controller != null) {
        unawaited(controller.ensurePlaying());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_closing || isClosed) return;
      _appActive = true;
      unawaited(WakelockPlus.enable());
      unawaited(_hideSystemUi());
      _resumeAllPlayers();
      if (_danmakuSuspendedForLifecycle) {
        _danmakuSuspendedForLifecycle = false;
        _restoreDanmakuAll();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _appActive = false;
      _resumeTimer?.cancel();
      _resumeTimer = null;
      unawaited(WakelockPlus.disable());
      // 后台挂起：断开所有格子弹幕长连接，省心跳与流量，前台恢复。
      if (!_danmakuSuspendedForLifecycle) {
        _danmakuSuspendedForLifecycle = true;
        _suspendDanmakuAll();
      }
    }
  }

  Future<void> _hideSystemUi() async {
    // 等待多开页完成首帧，避免 iOS 路由切换恢复状态栏。
    await WidgetsBinding.instance.endOfFrame;
    if (_closing || isClosed) {
      return;
    }
    if (Platform.isIOS) {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: const [],
      );
    } else if (Platform.isAndroid) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _restoreSystemUi() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
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
    rooms.add(room);
    _normalizeLayoutAfterRoomChange();
    SmartDialog.showToast("已加入 ${item.userName}");
    _scheduleResumePlayers();
  }

  /// 任意一格的 Player.open() 会抢占 iOS 共享 audio session 中断其他格，
  /// 延迟到本次 Player 初始化完成后再恢复全部播放器。
  void _scheduleResumePlayers() {
    if (_closing || isClosed || !_appActive) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(milliseconds: 800), () {
      _resumeTimer = null;
      if (_closing || isClosed || !_appActive) return;
      // Wakelock 是全局开关，底层单直播间的延迟清理可能在路由切换后关闭它。
      unawaited(WakelockPlus.enable());
      _resumeAllPlayers();
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
    return focusedRoomKey.value == room.key || chatTargetIndex.value == index;
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
    if (_closing || isClosed) return;
    for (final key in _degradedKeys) {
      final room = rooms.firstWhereOrNull((r) => r.key == key);
      final controller = room == null ? null : _existingPlayerFor(room);
      if (controller != null &&
          _appActive &&
          !_danmakuSuspendedForLifecycle) {
        unawaited(controller.restoreDanmaku());
      }
    }
    _degradedKeys.clear();
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
            r.key: _existingPlayerFor(r)?.lineIndex ??
                _pendingLines[r.key] ??
                0,
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
