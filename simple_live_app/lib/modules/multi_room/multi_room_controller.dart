import 'dart:async';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_controller.dart';

class MultiRoomController extends GetxController {
  final List<MultiRoomItem> initialRooms;

  MultiRoomController(this.initialRooms);

  final rooms = <MultiRoomItem>[].obs;

  /// 顶部工具栏的显示状态。点击画面切换，8 秒自动隐藏。
  var showOverlay = true.obs;

  Timer? _autoHideTimer;

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
    rooms.assignAll(_distinct(initialRooms));
    _resetAutoHideTimer();
  }

  @override
  void onClose() {
    _autoHideTimer?.cancel();
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

  /// 从关注的直播中添加房间。已在多开中的忽略。
  void addRoomFromFollow(FollowUser item) {
    final room = MultiRoomItem.fromFollow(item);
    if (rooms.any((r) => r.key == room.key)) {
      SmartDialog.showToast("${item.userName}已在多开中");
      return;
    }
    rooms.add(room);
    SmartDialog.showToast("已加入 ${item.userName}");
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
  }
}
