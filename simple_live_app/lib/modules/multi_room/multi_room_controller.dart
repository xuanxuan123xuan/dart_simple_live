import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

class MultiRoomController extends GetxController
    with WidgetsBindingObserver {
  final List<MultiRoomItem> initialRooms;

  MultiRoomController(this.initialRooms);

  final rooms = <MultiRoomItem>[].obs;

  /// 顶部工具栏的显示状态。点击画面切换，8 秒自动隐藏。
  var showOverlay = true.obs;

  /// 聊天区面板当前展示的直播间索引（对应 rooms 列表）。
  var chatTargetIndex = 0.obs;

  /// 双击聚焦的单格 key；null = 正常网格。
  final focusedRoomKey = Rxn<String>();

  Timer? _autoHideTimer;
  Timer? _resumeTimer;

  /// 上次多开的布局（恢复用）。
  Map<String, double> _pendingVolumes = {};
  Map<String, bool> _pendingDanmaku = {};
  int _pendingChatTarget = 0;

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
        () => showOverlay.value = false,
      );
    }
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    rooms.assignAll(_distinct(initialRooms));
    _restoreLayout(rooms);
    _resetAutoHideTimer();
    // 多开同屏进入沉浸模式，隐藏 iPad/Android 顶部状态栏。
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoHideTimer?.cancel();
    _resumeTimer?.cancel();
    _saveLayout();
    // 恢复系统栏。
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
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
    final controller = Get.isRegistered<MultiRoomPlayerController>(tag: tag)
        ? Get.find<MultiRoomPlayerController>(tag: tag)
        : Get.put(MultiRoomPlayerController(item), tag: tag);
    // 恢复上次的每格音量/弹幕开关。
    final volume = _pendingVolumes[item.key];
    if (volume != null) {
      controller.volume.value = volume;
    }
    final danmaku = _pendingDanmaku[item.key];
    if (danmaku != null) {
      controller.showDanmaku.value = danmaku;
    }
    return controller;
  }

  void removeRoom(MultiRoomItem item) {
    rooms.removeWhere((room) => room.key == item.key);
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
    final item = rooms.removeAt(oldIndex);
    rooms.insert(newIndex, item);
  }

  /// 恢复所有应播放但已暂停的播放器。
  ///
  /// iOS 上 media_kit/libmpv 多实例共享 audio session：新增 Player 的
  /// open() 会中断正在播放的旧 Player，延迟一段时间后把它拉回来。
  void _resumeAllPlayers() {
    for (final room in rooms) {
      final c = playerFor(room);
      if (c.liveStatus.value && !c.player.state.playing) {
        c.player.play();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeAllPlayers();
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
    SmartDialog.showToast("已加入 ${item.userName}");
    _scheduleResumePlayers();
  }

  /// 新房间的 Player.open() 会抢占 iOS 共享 audio session 中断旧播放器，
  /// 延迟到新 Player 初始化完成后再恢复全部播放器。
  void _scheduleResumePlayers() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(milliseconds: 800), () {
      _resumeTimer = null;
      _resumeAllPlayers();
    });
  }

  // ==================== 布局持久化 ====================

  void _saveLayout() {
    try {
      final data = <String, dynamic>{
        "roomKeys": rooms.map((r) => r.key).toList(),
        "chatTarget": chatTargetIndex.value,
        "volumes": {
          for (final r in rooms) r.key: playerFor(r).volume.value,
        },
        "danmaku": {
          for (final r in rooms) r.key: playerFor(r).showDanmaku.value,
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
    } catch (e) {
      Log.d("多开布局恢复失败: $e");
    }
  }
}
