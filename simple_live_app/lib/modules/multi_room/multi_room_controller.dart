import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_controller.dart';

class MultiRoomController extends GetxController
    with WidgetsBindingObserver {
  final List<MultiRoomItem> initialRooms;

  MultiRoomController(this.initialRooms);

  final rooms = <MultiRoomItem>[].obs;

  /// 顶部工具栏的显示状态。点击画面切换，8 秒自动隐藏。
  var showOverlay = true.obs;

  /// 聊天区面板当前展示的直播间索引（对应 rooms 列表）。
  var chatTargetIndex = 0.obs;

  Timer? _autoHideTimer;
  Timer? _resumeTimer;

  void toggleOverlay() {
    showOverlay.value = !showOverlay.value;
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
    _resetAutoHideTimer();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoHideTimer?.cancel();
    _resumeTimer?.cancel();
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
    return Get.put(MultiRoomPlayerController(item), tag: tag);
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
}
