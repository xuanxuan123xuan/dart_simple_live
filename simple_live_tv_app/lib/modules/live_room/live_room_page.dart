import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_core/simple_live_core.dart' show LiveStatusState;
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_tv_app/modules/live_room/player/player_controls.dart';

class LiveRoomPage extends GetView<LiveRoomController> {
  const LiveRoomPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          requestExitPlayer();
        }
      },
      child: Focus(
        focusNode: controller.focusNode,
        autofocus: true,
        onKeyEvent: (_, event) => onKeyEvent(event),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Obx(
            () => buildMediaPlayer(),
          ),
        ),
      ),
    );
  }

  KeyEventResult onKeyEvent(KeyEvent key) {
    if (key is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (key.logicalKey == LogicalKeyboardKey.escape ||
        key.logicalKey == LogicalKeyboardKey.backspace ||
        key.logicalKey == LogicalKeyboardKey.goBack ||
        key.logicalKey == LogicalKeyboardKey.browserBack) {
      requestExitPlayer();
      return KeyEventResult.handled;
    }
    final shortcut = resolveLiveRoomShortcut(key.logicalKey);
    if (shortcut == LiveRoomShortcut.multiRoom) {
      unawaited(showMultiRoomPicker(controller));
      return KeyEventResult.handled;
    }
    if (controller.showControlsState.value) {
      controller.resetHideControlsTimer();
      if (controller.handleKeyboardShortcut(key.logicalKey)) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key.logicalKey == LogicalKeyboardKey.select ||
        key.logicalKey == LogicalKeyboardKey.enter ||
        key.logicalKey == LogicalKeyboardKey.space) {
      controller.showControls();
      return KeyEventResult.handled;
    }

    if (controller.handleKeyboardShortcut(key.logicalKey)) {
      return KeyEventResult.handled;
    }

    // 右键打开设置
    if (shortcut == LiveRoomShortcut.settings) {
      showPlayerSettings(controller);
      return KeyEventResult.handled;
    }

    // 点击左键显示关注用户
    if (key.logicalKey == LogicalKeyboardKey.arrowLeft) {
      showFollowUser(controller);
      return KeyEventResult.handled;
    }

    // // 点击右键关注/取消关注
    // if (key.logicalKey == LogicalKeyboardKey.arrowRight) {
    //   if (controller.followed.value) {
    //     controller.removeFollowUser();
    //   } else {
    //     controller.followUser();
    //   }

    //   return;
    // }

    // 点击上键切换上一个直播
    if (key.logicalKey == LogicalKeyboardKey.arrowUp) {
      controller.prevChannel();
      return KeyEventResult.handled;
    }

    // 点击下键切换下一个直播
    if (key.logicalKey == LogicalKeyboardKey.arrowDown) {
      controller.nextChannel();
      return KeyEventResult.handled;
    }
    if (key.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
      unawaited(controller.togglePause());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void requestExitPlayer() {
    if (controller.showControlsState.value) {
      controller.hideControls();
      return;
    }
    // 双击返回键退出：第一次只提示，第二次才退出。
    if (controller.doubleClickExit) {
      controller.doubleClickTimer?.cancel();
      controller.doubleClickTimer = null;
      controller.doubleClickExit = false;
      SmartDialog.dismiss();
      Get.back();
      return;
    }
    controller.doubleClickExit = true;
    SmartDialog.dismiss();
    SmartDialog.showToast("再按一次退出播放器");
    controller.doubleClickTimer?.cancel();
    controller.doubleClickTimer = Timer(const Duration(seconds: 2), () {
      controller.doubleClickExit = false;
      controller.doubleClickTimer = null;
    });
  }

  Widget buildMediaPlayer() {
    var boxFit = BoxFit.contain;
    double? aspectRatio;
    if (AppSettingsController.instance.scaleMode.value == 0) {
      boxFit = BoxFit.contain;
    } else if (AppSettingsController.instance.scaleMode.value == 1) {
      boxFit = BoxFit.fill;
    } else if (AppSettingsController.instance.scaleMode.value == 2) {
      boxFit = BoxFit.cover;
    } else if (AppSettingsController.instance.scaleMode.value == 3) {
      boxFit = BoxFit.contain;
      aspectRatio = 16 / 9;
    } else if (AppSettingsController.instance.scaleMode.value == 4) {
      boxFit = BoxFit.contain;
      aspectRatio = 4 / 3;
    }
    return Stack(
      children: [
        Obx(() {
          // 渲染降级会重建 videoController，需重建 Video 组件才能生效。
          controller.playerRenderGeneration.value;
          return Video(
            key: controller.globalPlayerKey,
            controller: controller.videoController,
            pauseUponEnteringBackgroundMode: false,
            resumeUponEnteringForegroundMode: false,
            controls: (state) {
              return playerControls(state, controller);
            },
            aspectRatio: aspectRatio,
            fit: boxFit,
          );
        }),
        Obx(
          () => Visibility(
            visible:
                controller.roomLiveState.value == LiveStatusState.offline &&
                    !controller.pageLoadding.value,
            child: Center(
              child: Text(
                "未开播",
                style: AppStyle.textStyleWhite,
              ),
            ),
          ),
        ),
        if (controller.playbackLoadError.value.isNotEmpty)
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: AppStyle.edgeInsetsA24,
              color: Colors.black87,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    controller.playbackLoadError.value,
                    textAlign: TextAlign.center,
                    style: AppStyle.textStyleWhite,
                  ),
                  AppStyle.vGap16,
                  ElevatedButton.icon(
                    autofocus: true,
                    onPressed: controller.refreshRoom,
                    icon: const Icon(Icons.refresh),
                    label: const Text("重试"),
                  ),
                ],
              ),
            ),
          ),
        Obx(
          () => Visibility(
            visible: controller.autoExitEnable.value,
            child: Positioned(
              right: 24,
              top: 24,
              child: Text(
                "${parseDuration(controller.countdown.value)}后自动关闭",
                style: AppStyle.textStyleWhite,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String parseDuration(int duration) {
    int hours = duration ~/ 3600;
    int minutes = duration % 3600 ~/ 60;
    int seconds = duration % 60;

    return "${hours.toString().padLeft(2, '0')}:"
        "${minutes.toString().padLeft(2, '0')}:"
        "${seconds.toString().padLeft(2, '0')}";
  }
}

enum LiveRoomShortcut { none, multiRoom, settings }

LiveRoomShortcut resolveLiveRoomShortcut(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.contextMenu) {
    return LiveRoomShortcut.multiRoom;
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    return LiveRoomShortcut.settings;
  }
  return LiveRoomShortcut.none;
}
