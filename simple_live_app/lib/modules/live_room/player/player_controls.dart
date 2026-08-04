import 'dart:async';
import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/platform_utils.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/services/live_subtitle_service.dart';
import 'package:simple_live_app/widgets/superchat_card.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:window_manager/window_manager.dart';

Widget playerControls(
  VideoState videoState,
  LiveRoomController controller,
) {
  return Obx(() {
    if (controller.fullScreenState.value) {
      return buildFullControls(
        videoState,
        controller,
      );
    }
    return buildControls(
      videoState.context.orientation == Orientation.portrait,
      videoState,
      controller,
    );
  });
}

EdgeInsets _fullScreenControlPadding(BuildContext context) {
  final mediaQuery = MediaQuery.of(context);
  if (Utils.isOhos) {
    return mediaQuery.viewPadding;
  }
  if (Platform.isIOS && mediaQuery.orientation == Orientation.landscape) {
    final padding = mediaQuery.viewPadding;
    // iOS 横屏时 viewPadding.top 通常为 0（状态栏在侧边），
    // 但底部需要保留 home indicator 安全区，顶部至少 8pt 呼吸感。
    return EdgeInsets.only(
      left: padding.left,
      right: padding.right,
      top: padding.top > 0 ? padding.top : 8,
      bottom: padding.bottom > 0 ? padding.bottom : 8,
    );
  }
  return mediaQuery.padding;
}

Widget buildFullControls(
  VideoState videoState,
  LiveRoomController controller,
) {
  final padding = _fullScreenControlPadding(videoState.context);
  final volumeButtonKey = GlobalKey();
  final controls = _buildPlayerMouseRegion(
    videoState: videoState,
    controller: controller,
    child: Stack(
      children: [
        const SizedBox.expand(),
        buildDanmuView(videoState.context, controller),
        buildPlayerSuperChatOverlay(controller),
        _buildBufferingIndicator(videoState),
        buildPlayerGestureLayer(
          controller,
          enableQuickAccessLongPress: true,
        ),
        buildLiveSubtitleOverlay(videoState.context, controller),
        _buildFullTopBar(
          controller,
          padding: padding,
        ),
        _buildFullBottomBar(
          controller,
          padding: padding,
          volumeButtonKey: volumeButtonKey,
        ),
        _buildSideLockButton(
          controller,
          padding: padding,
          alignLeft: false,
        ),
        _buildSideLockButton(
          controller,
          padding: padding,
          alignLeft: true,
        ),
        buildGestureTip(controller),
      ],
    ),
  );

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return DragToMoveArea(child: controls);
  }
  return controls;
}

Widget buildLockButton(LiveRoomController controller) {
  return Obx(
    () => Center(
      child: InkWell(
        onTap: controller.setLockState,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: AppStyle.radius8,
          ),
          width: 40,
          height: 40,
          child: Center(
            child: Icon(
              controller.lockControlsState.value
                  ? Icons.lock_outline_rounded
                  : Icons.lock_open_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget buildControls(
  bool isPortrait,
  VideoState videoState,
  LiveRoomController controller,
) {
  final volumeButtonKey = GlobalKey();
  return _buildPlayerMouseRegion(
    videoState: videoState,
    controller: controller,
    child: Stack(
      children: [
        const SizedBox.expand(),
        buildDanmuView(videoState.context, controller),
        buildPlayerSuperChatOverlay(controller),
        _buildBufferingIndicator(videoState),
        buildPlayerGestureLayer(controller),
        buildLiveSubtitleOverlay(videoState.context, controller),
        _buildNormalBottomBar(
          controller,
          isPortrait: isPortrait,
          volumeButtonKey: volumeButtonKey,
        ),
        buildGestureTip(controller),
      ],
    ),
  );
}

Widget _buildPlayerMouseRegion({
  required VideoState videoState,
  required LiveRoomController controller,
  required Widget child,
}) {
  return Obx(
    () => MouseRegion(
      cursor: controller.hideMouseCursorState.value
          ? SystemMouseCursors.none
          : SystemMouseCursors.basic,
      onEnter: controller.onEnter,
      onExit: controller.onExit,
      onHover: (event) {
        controller.resetHideMouseCursorTimer();
        controller.showMouseCursor();
        controller.onHover(event, videoState.context);
      },
      child: child,
    ),
  );
}

Widget buildPlayerSuperChatOverlay(LiveRoomController controller) {
  return Obx(() {
    if (!AppSettingsController.instance.playershowSuperChat.value) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 24,
      bottom: 24,
      child: PlayerSuperChatOverlay(controller: controller),
    );
  });
}

Widget buildLiveSubtitleOverlay(
  BuildContext _,
  LiveRoomController controller,
) =>
    _LiveSubtitleOverlay(controller: controller);

class _LiveSubtitleOverlay extends StatefulWidget {
  final LiveRoomController controller;

  const _LiveSubtitleOverlay({
    required this.controller,
  });

  @override
  State<_LiveSubtitleOverlay> createState() => _LiveSubtitleOverlayState();
}

class _LiveSubtitleOverlayState extends State<_LiveSubtitleOverlay> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    if (!LiveSubtitleService.instance.uiEnabled) {
      return const SizedBox.shrink();
    }
    return Obx(() {
      final controller = widget.controller;
      final settings = AppSettingsController.instance;
      if (!settings.liveSubtitleEnable.value ||
          settings.liveSubtitleModelPath.value.trim().isEmpty ||
          LiveSubtitleService.instance.subtitleText.value.trim().isEmpty) {
        return const SizedBox.shrink();
      }

      final mediaQuery = MediaQuery.of(context);
      final padding = controller.fullScreenState.value
          ? _fullScreenControlPadding(context)
          : mediaQuery.padding;
      final alignment = Alignment(
        settings.liveSubtitleOffsetX.value * 2 - 1,
        settings.liveSubtitleOffsetY.value * 2 - 1,
      );
      final positionedPadding = EdgeInsets.only(
        left: padding.left + 24,
        right: padding.right + 24,
        top: padding.top + 24,
        bottom: padding.bottom + 24,
      );
      final subtitleColor = Color(settings.liveSubtitleColor.value);
      final locked = settings.liveSubtitlePositionLocked.value;
      final showUnlockButton = locked && _hovering;

      return Positioned.fill(
        child: Padding(
          padding: positionedPadding,
          child: Align(
            alignment: alignment,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovering = true),
              onExit: (_) => setState(() => _hovering = false),
              child: GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onLongPress: locked
                    ? () {
                        settings.setLiveSubtitlePositionLocked(false);
                        SmartDialog.showToast("字幕位置已解锁");
                      }
                    : null,
                onPanUpdate: locked
                    ? null
                    : (details) {
                        final size = mediaQuery.size;
                        if (size.width <= 0 || size.height <= 0) {
                          return;
                        }
                        settings.setLiveSubtitleOffset(
                          x: settings.liveSubtitleOffsetX.value +
                              details.delta.dx / size.width,
                          y: settings.liveSubtitleOffsetY.value +
                              details.delta.dy / size.height,
                        );
                      },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: settings.liveSubtitleBackgroundEnable.value
                              ? Colors.black.withAlpha(140)
                              : Colors.transparent,
                          borderRadius: AppStyle.radius8,
                        ),
                        child: Padding(
                          padding: AppStyle.edgeInsetsA8,
                          child: Text(
                            LiveSubtitleService.instance.subtitleText.value,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: settings.liveSubtitleFontSize.value,
                              fontWeight:
                                  settings.liveSubtitleResolvedFontWeight,
                              shadows: const [
                                Shadow(
                                  color: Colors.black,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (showUnlockButton)
                      Positioned(
                        right: -12,
                        top: -12,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              settings.setLiveSubtitlePositionLocked(false);
                              SmartDialog.showToast("字幕位置已解锁");
                            },
                            child: const SizedBox(
                              width: 32,
                              height: 32,
                              child: Icon(
                                Icons.lock_open_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

Widget _buildBufferingIndicator(VideoState videoState) {
  return Center(
    child: StreamBuilder<bool>(
      stream: videoState.widget.controller.player.stream.buffering,
      initialData: videoState.widget.controller.player.state.buffering,
      builder: (_, snapshot) {
        if (!(snapshot.data ?? false)) {
          return const SizedBox.shrink();
        }
        return const CircularProgressIndicator();
      },
    ),
  );
}

Widget buildPlayerGestureLayer(
  LiveRoomController controller, {
  bool enableQuickAccessLongPress = false,
}) {
  final useDesktopPan = Platform.isWindows || Platform.isLinux;
  return Positioned.fill(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: controller.onTap,
      onDoubleTapDown: controller.onDoubleTap,
      onPanStart: !useDesktopPan
          ? null
          : (details) {
              if (!_canUseDesktopVolumeDrag(
                  controller, details.localPosition)) {
                controller.desktopVolumeDragging = false;
                return;
              }
              controller.desktopVolumeDragging = true;
              controller.onVerticalDragStart(
                DragStartDetails(
                  globalPosition: details.globalPosition,
                  localPosition: details.localPosition,
                ),
              );
            },
      onPanUpdate: !useDesktopPan
          ? null
          : (details) {
              if (!controller.desktopVolumeDragging) {
                return;
              }
              controller.onVerticalDragUpdate(
                DragUpdateDetails(
                  globalPosition: details.globalPosition,
                  localPosition: details.localPosition,
                  delta: details.delta,
                  primaryDelta: details.delta.dy,
                ),
              );
            },
      onPanEnd: !useDesktopPan
          ? null
          : (details) {
              if (!controller.desktopVolumeDragging) {
                return;
              }
              controller.desktopVolumeDragging = false;
              controller.onVerticalDragEnd(
                DragEndDetails(
                  primaryVelocity: details.velocity.pixelsPerSecond.dy,
                  velocity: details.velocity,
                ),
              );
            },
      onPanCancel: !useDesktopPan
          ? null
          : () {
              if (!controller.desktopVolumeDragging) {
                return;
              }
              controller.desktopVolumeDragging = false;
              controller.onVerticalDragEnd(DragEndDetails());
            },
      onLongPress: !enableQuickAccessLongPress
          ? null
          : () {
              if (controller.lockControlsState.value) {
                return;
              }
              showQuickAccess(controller);
            },
      onVerticalDragStart:
          useDesktopPan ? null : controller.onVerticalDragStart,
      onVerticalDragUpdate:
          useDesktopPan ? null : controller.onVerticalDragUpdate,
      onVerticalDragEnd: useDesktopPan ? null : controller.onVerticalDragEnd,
      child: const SizedBox.expand(),
    ),
  );
}

bool _canUseDesktopVolumeDrag(
  LiveRoomController controller,
  Offset localPosition,
) {
  if (!(Platform.isWindows || Platform.isLinux)) {
    return false;
  }
  if (controller.lockControlsState.value && controller.fullScreenState.value) {
    return false;
  }
  if (!controller.showControlsState.value) {
    return false;
  }
  final width = Get.width;
  final height = Get.height;
  if (width <= 0 || height <= 0) {
    return false;
  }
  final inRightZone = localPosition.dx >= width * 0.72;
  final inMiddleZone =
      localPosition.dy >= height * 0.2 && localPosition.dy <= height * 0.8;
  return inRightZone && inMiddleZone;
}

Widget _buildFullTopBar(
  LiveRoomController controller, {
  required EdgeInsets padding,
}) {
  return Obx(() {
    final visible = controller.showControlsState.value &&
        !controller.lockControlsState.value;
    final detail = controller.detail.value;
    final title = detail?.title ?? "直播间";
    final userName = detail?.userName ?? "";
    final displayTitle = userName.isEmpty ? title : "$title - $userName";

    return AnimatedPositioned(
      left: 0,
      right: 0,
      top: visible ? 0 : -(48 + padding.top),
      duration: const Duration(milliseconds: 200),
      // 拦截点击冒泡：避免点按钮时同一次 tap 冒泡到 gesture layer 的
      // onTap(controller.onTap) 触发控件显隐/rebuild，导致刚打开的弹窗被 pop。
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
        height: 48 + padding.top,
        padding: EdgeInsets.only(
          left: padding.left + 32,
          right: padding.right + 32,
          top: padding.top,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.transparent,
              Colors.black87,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                if (controller.smallWindowState.value) {
                  controller.exitSmallWindow();
                } else {
                  controller.exitFull();
                }
              },
              icon: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 24,
              ),
            ),
            AppStyle.hGap12,
            Expanded(
              child: Text(
                displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
            AppStyle.hGap12,
            IconButton(
              onPressed: controller.saveScreenshot,
              icon: const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white,
                size: 24,
              ),
            ),
            IconButton(
              onPressed: () => showQuickAccess(controller),
              icon: const Icon(
                Remix.play_list_2_line,
                color: Colors.white,
                size: 24,
              ),
            ),
            if (controller.canStartInlineMultiRoom)
              IconButton(
                tooltip: "添加直播间并进入多开",
                onPressed: controller.showAddToMultiRoomPanel,
                icon: const Icon(
                  Remix.play_list_add_line,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            if (Platform.isAndroid || Utils.isOhos)
              IconButton(
                onPressed: controller.enablePIP,
                icon: const Icon(
                  Icons.picture_in_picture,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            IconButton(
              onPressed: () => showPlayerSettings(controller),
              icon: const Icon(
                Icons.more_horiz,
                color: Colors.white,
                size: 24,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  });
}

Widget _buildFullBottomBar(
  LiveRoomController controller, {
  required EdgeInsets padding,
  required GlobalKey volumeButtonKey,
}) {
  return Obx(() {
    final visible = controller.showControlsState.value &&
        !controller.lockControlsState.value;
    final showDanmaku = controller.showDanmakuState.value;

    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom: visible ? 0 : -(80 + padding.bottom),
      duration: const Duration(milliseconds: 200),
      // 拦截点击冒泡，避免按钮 tap 触发 gesture layer 的 onTap 导致弹窗被 pop。
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black87,
            ],
          ),
        ),
        padding: EdgeInsets.only(
          left: padding.left + 32,
          right: padding.right + 32,
          bottom: padding.bottom,
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: controller.refreshRoom,
              icon: const Icon(
                Remix.refresh_line,
                color: Colors.white,
              ),
            ),
            IconButton(
              onPressed: () {
                controller.showDanmakuState.value =
                    !controller.showDanmakuState.value;
              },
              icon: ImageIcon(
                AssetImage(
                  showDanmaku
                      ? 'assets/icons/icon_danmaku_close.png'
                      : 'assets/icons/icon_danmaku_open.png',
                ),
                size: 24,
                color: Colors.white,
              ),
            ),
            IconButton(
              onPressed: () => showDanmakuSettings(controller),
              icon: const ImageIcon(
                AssetImage('assets/icons/icon_danmaku_setting.png'),
                size: 24,
                color: Colors.white,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                controller.liveDuration.value,
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
            ),
            const Expanded(child: SizedBox()),
            if (!Platform.isAndroid && !Platform.isIOS && !Utils.isOhos)
              IconButton(
                key: volumeButtonKey,
                onPressed: () {
                  final context = volumeButtonKey.currentContext;
                  if (context == null) {
                    return;
                  }
                  controller.showVolumeSlider(
                    context,
                    keepAlive: true,
                  );
                },
                icon: Icon(
                  controller.mutedState.value
                      ? Icons.volume_off
                      : Icons.volume_down,
                  size: 24,
                  color: Colors.white,
                ),
              ),
            IconButton(
              onPressed: controller.toggleMute,
              icon: Icon(
                controller.mutedState.value
                    ? Icons.volume_off
                    : Icons.volume_up,
                size: 24,
                color: Colors.white,
              ),
            ),
            TextButton(
              onPressed: () => showQualitesInfo(controller),
              child: Text(
                controller.currentQualityInfo.value,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            TextButton(
              onPressed: () => showLinesInfo(controller),
              child: Text(
                controller.currentLineInfo.value,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            IconButton(
              onPressed: () {
                if (controller.smallWindowState.value) {
                  controller.exitSmallWindow();
                } else {
                  controller.exitFull();
                }
              },
              icon: const Icon(
                Remix.fullscreen_exit_fill,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  });
}

Widget _buildNormalBottomBar(
  LiveRoomController controller, {
  required bool isPortrait,
  required GlobalKey volumeButtonKey,
}) {
  return Obx(() {
    final showDanmaku = controller.showDanmakuState.value;
    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom: controller.showControlsState.value ? 0 : -48,
      duration: const Duration(milliseconds: 200),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black87,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: controller.refreshRoom,
              icon: const Icon(
                Remix.refresh_line,
                color: Colors.white,
              ),
            ),
            IconButton(
              onPressed: () {
                controller.showDanmakuState.value =
                    !controller.showDanmakuState.value;
              },
              icon: ImageIcon(
                AssetImage(
                  showDanmaku
                      ? 'assets/icons/icon_danmaku_close.png'
                      : 'assets/icons/icon_danmaku_open.png',
                ),
                size: 24,
                color: Colors.white,
              ),
            ),
            IconButton(
              onPressed: () => showDanmakuSettings(controller),
              icon: const ImageIcon(
                AssetImage('assets/icons/icon_danmaku_setting.png'),
                size: 24,
                color: Colors.white,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                controller.liveDuration.value,
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
            ),
            const Expanded(child: SizedBox()),
            if (!Platform.isAndroid && !Platform.isIOS && !Utils.isOhos)
              IconButton(
                key: volumeButtonKey,
                onPressed: () {
                  final context = volumeButtonKey.currentContext;
                  if (context == null) {
                    return;
                  }
                  controller.showVolumeSlider(
                    context,
                    keepAlive: true,
                  );
                },
                icon: Icon(
                  controller.mutedState.value
                      ? Icons.volume_off
                      : Icons.volume_down,
                  size: 24,
                  color: Colors.white,
                ),
              ),
            IconButton(
              onPressed: controller.toggleMute,
              icon: Icon(
                controller.mutedState.value
                    ? Icons.volume_off
                    : Icons.volume_up,
                size: 24,
                color: Colors.white,
              ),
            ),
            if (!isPortrait)
              TextButton(
                onPressed: () => showQualitesInfo(controller),
                child: Text(
                  controller.currentQualityInfo.value,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            if (!isPortrait)
              TextButton(
                onPressed: () => showLinesInfo(controller),
                child: Text(
                  controller.currentLineInfo.value,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            if (!Platform.isAndroid && !Platform.isIOS && !Utils.isOhos)
              IconButton(
                onPressed: controller.enterSmallWindow,
                icon: const Icon(
                  Icons.picture_in_picture,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            IconButton(
              onPressed: controller.enterFullScreen,
              icon: const Icon(
                Remix.fullscreen_line,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  });
}

Widget _buildSideLockButton(
  LiveRoomController controller, {
  required EdgeInsets padding,
  required bool alignLeft,
}) {
  return Obx(() {
    final visible = controller.lockControlsState.value
        ? controller.showLockEdgeState.value
        : controller.showControlsState.value;
    final offset = -(64 + (alignLeft ? padding.left : padding.right));
    return AnimatedPositioned(
      top: 0,
      bottom: 0,
      left: alignLeft ? (visible ? padding.left + 32 : offset) : null,
      right: alignLeft ? null : (visible ? padding.right + 32 : offset),
      duration: const Duration(milliseconds: 200),
      child: buildLockButton(controller),
    );
  });
}

Widget buildGestureTip(LiveRoomController controller) {
  return Obx(() {
    // 文案为空时不画：竖向手势按下的瞬间 showGestureTip 就为 true，而
    // gestureTipText 要等第一次 drag update 才有值；音量还有 5 档取整的
    // lastVolume 早退，落在同一档时整段手势都不会写文案。此时若照画，
    // 就是一个只有 padding 的深色圆角块悬在画面正中。
    if (!controller.showGestureTip.value ||
        controller.gestureTipText.value.isEmpty) {
      return const SizedBox.shrink();
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          controller.gestureTipText.value,
          style: const TextStyle(fontSize: 18, color: Colors.white),
        ),
      ),
    );
  });
}

Widget buildDanmuView(BuildContext context, LiveRoomController controller) {
  var padding = controller.fullScreenState.value
      ? _fullScreenControlPadding(context)
      : Utils.isOhos
              ? EdgeInsets.zero
              : MediaQuery.of(context).padding;
  // 平板（短边 ≥ 600）横屏全屏时顶部有系统栏，弹幕整体往下移固定距离，
  // 避开状态栏、视觉上往屏幕中间靠。手机/竖屏不受影响。
  final tabletLandscapeFullscreen = controller.fullScreenState.value &&
      MediaQuery.orientationOf(context) == Orientation.landscape &&
      MediaQuery.sizeOf(context).shortestSide >=
          PlatformUtils.multiRoomMinShortestSide;
  final extraTopInset = tabletLandscapeFullscreen ? 32.0 : 0.0;
  return Positioned.fill(
    top: padding.top + extraTopInset,
    bottom: padding.bottom,
    child: Obx(
      () {
        controller.danmakuViewVersion.value;
        return Offstage(
          offstage: !controller.showDanmakuState.value,
          child: Padding(
            padding: controller.fullScreenState.value
                ? EdgeInsets.only(
                    top: AppSettingsController.instance.danmuTopMargin.value,
                    bottom:
                        AppSettingsController.instance.danmuBottomMargin.value,
                  )
                : EdgeInsets.zero,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewportHeight = constraints.maxHeight > 0
                    ? constraints.maxHeight
                    : MediaQuery.sizeOf(context).height;
                controller.updateDanmakuViewportHeight(viewportHeight);
                final settings = AppSettingsController.instance;
                final resolvedLineCount = settings.resolveDanmuTargetLineCount(
                  viewportHeight: viewportHeight,
                  area: settings.danmuArea.value,
                  fontSize: settings.danmuSize.value,
                  lineCount: settings.danmuLineCount.value,
                );
                final hideDanmu = resolvedLineCount <= 0;
                return DanmakuScreen(
                  key: controller.globalDanmuKey,
                  createdController: controller.initDanmakuController,
                  option: DanmakuOption(
                    fontSize: settings.danmuSize.value,
                    fontFamily: Platform.isWindows ? "Microsoft YaHei" : null,
                    area: settings.resolveDanmuEffectiveArea(
                      viewportHeight: viewportHeight,
                      area: settings.danmuArea.value,
                      fontSize: settings.danmuSize.value,
                      lineCount: settings.danmuLineCount.value,
                    ),
                    lineHeight: settings.resolveDanmuLineHeight(
                      viewportHeight: viewportHeight,
                      area: settings.danmuArea.value,
                      fontSize: settings.danmuSize.value,
                      lineCount: settings.danmuLineCount.value,
                    ),
                    duration: settings.danmuSpeed.value.toInt(),
                    opacity: settings.danmuOpacity.value,
                    fontWeight: settings.danmuFontWeight.value,
                    hideTop: hideDanmu,
                    hideBottom: hideDanmu,
                    hideScroll: hideDanmu,
                    hideSpecial: hideDanmu,
                  ),
                );
              },
            ),
          ),
        );
      },
    ),
  );
}

void showLinesInfo(LiveRoomController controller) {
  if (controller.useBottomSheetPlayerMenus) {
    controller.showPlayUrlsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "线路选择",
    useSystem: false,
    child: ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: controller.playUrls.length,
      itemBuilder: (_, i) {
        return ListTile(
          selected: controller.currentLineIndex == i,
          title: Text.rich(
            TextSpan(
              text: "线路${i + 1}",
              children: [
                WidgetSpan(
                    child: Container(
                  decoration: BoxDecoration(
                    borderRadius: AppStyle.radius4,
                    border: Border.all(
                      color: Colors.grey,
                    ),
                  ),
                  padding: AppStyle.edgeInsetsH4,
                  margin: AppStyle.edgeInsetsL8,
                  child: Text(
                    controller.playUrls[i].contains(".flv") ? "FLV" : "HLS",
                    style: const TextStyle(
                      fontSize: 12,
                    ),
                  ),
                )),
              ],
            ),
            style: const TextStyle(fontSize: 14),
          ),
          minLeadingWidth: 16,
          onTap: () {
            Utils.hideRightDialog();
            //controller.currentLineIndex = i;
            //controller.setPlayer();
            controller.changePlayLine(i);
          },
        );
      },
    ),
  );
}

void showQualitesInfo(LiveRoomController controller) {
  if (controller.useBottomSheetPlayerMenus) {
    controller.showQualitySheet();
    return;
  }
  Utils.showRightDialog(
    title: "清晰度",
    useSystem: false,
    child: ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: controller.qualites.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return ListTile(
            selected: !controller.qualityLocked.value,
            title: const Text("自动", style: TextStyle(fontSize: 14)),
            subtitle: const Text("根据网络与设备情况自动调整"),
            minLeadingWidth: 16,
            onTap: () {
              Utils.hideRightDialog();
              unawaited(controller.useAutomaticQuality());
            },
          );
        }
        var item = controller.qualites[i - 1];
        return ListTile(
          selected: controller.qualityLocked.value &&
              controller.currentQuality == i - 1,
          title: Text(
            item.quality,
            style: const TextStyle(fontSize: 14),
          ),
          minLeadingWidth: 16,
          onTap: () {
            Utils.hideRightDialog();
            controller.qualityLocked.value = true;
            controller.currentQuality = i - 1;
            controller.saveQualityMemory();
            controller.getPlayUrl();
          },
        );
      },
    ),
  );
}

void showDanmakuSettings(LiveRoomController controller) {
  if (controller.useBottomSheetPlayerMenus) {
    controller.showDanmuSettingsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "弹幕设置",
    width: 400,
    useSystem: false,
    child: ListView(
      padding: AppStyle.edgeInsetsA12,
      children: [
        DanmuSettingsView(
          danmakuController: controller.danmakuController,
          siteId: controller.site.id,
          previewViewportHeight: controller.danmakuViewportHeight.value,
        ),
      ],
    ),
  );
}

void showPlayerSettings(LiveRoomController controller) {
  if (controller.useBottomSheetPlayerMenus) {
    controller.showPlayerSettingsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "设置",
    width: 320,
    useSystem: false,
    child: Obx(
      () => ListView(
        padding: AppStyle.edgeInsetsV12,
        children: [
          Padding(
            padding: AppStyle.edgeInsetsH16,
            child: Text(
              "画面尺寸",
              style: Get.textTheme.titleMedium,
            ),
          ),
          RadioGroup<int>(
            groupValue: AppSettingsController.instance.scaleMode.value,
            onChanged: (e) {
              AppSettingsController.instance.setScaleMode(e ?? 0);
              controller.updateScaleMode();
            },
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile(
                  value: 0,
                  contentPadding: AppStyle.edgeInsetsH4,
                  title: Text("适应"),
                  visualDensity: VisualDensity.compact,
                ),
                RadioListTile(
                  value: 1,
                  contentPadding: AppStyle.edgeInsetsH4,
                  title: Text("拉伸"),
                  visualDensity: VisualDensity.compact,
                ),
                RadioListTile(
                  value: 2,
                  contentPadding: AppStyle.edgeInsetsH4,
                  title: Text("铺满"),
                  visualDensity: VisualDensity.compact,
                ),
                RadioListTile(
                  value: 3,
                  contentPadding: AppStyle.edgeInsetsH4,
                  title: Text("16:9"),
                  visualDensity: VisualDensity.compact,
                ),
                RadioListTile(
                  value: 4,
                  contentPadding: AppStyle.edgeInsetsH4,
                  title: Text("4:3"),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          AppStyle.divider,
          SwitchListTile(
            value: AppSettingsController
                .instance.autoSelectFastestLine.value,
            onChanged: (e) {
              AppSettingsController.instance.setAutoSelectFastestLine(e);
            },
            title: const Text("自动选择最快线路"),
            subtitle: const Text("多线路时测延迟选最快的播放"),
            contentPadding: AppStyle.edgeInsetsH16,
            secondary: const Icon(Icons.speed),
          ),
          SwitchListTile(
            value: AppSettingsController
                .instance.fullScreenForceLandscape.value,
            onChanged: (e) {
              AppSettingsController.instance.setFullScreenForceLandscape(e);
            },
            title: const Text("全屏自动横屏"),
            subtitle: const Text("竖屏进全屏时自动转横屏，状态栏才能隐藏；关闭则保持当前方向"),
            contentPadding: AppStyle.edgeInsetsH16,
            secondary: const Icon(Icons.screen_rotation),
          ),
        ],
      ),
    ),
  );
}

void showQuickAccess(LiveRoomController controller) {
  final keys = controller.enabledQuickAccessKeys;
  if (keys.isEmpty) {
    SmartDialog.showToast("没有东西可展示");
    return;
  }
  if (keys.length == 1) {
    _openQuickAccessItem(controller, keys.single);
    return;
  }
  if (controller.useBottomSheetPlayerMenus) {
    controller.showQuickAccessSheet();
    return;
  }

  Utils.showRightDialog(
    title: "快捷入口",
    width: 320,
    useSystem: false,
    child: ListView(
      padding: AppStyle.edgeInsetsV12,
      children:
          keys.map((key) => _buildQuickAccessTile(controller, key)).toList(),
    ),
  );
}

Widget _buildQuickAccessTile(LiveRoomController controller, String key) {
  final item = Constant.allLiveRoomQuickAccess[key]!;
  final enabled =
      key != "recommendation" || controller.hasCategoryRecommendation;
  return ListTile(
    leading: Icon(item.iconData),
    title: Text(controller.quickAccessTitle(key)),
    subtitle: Text(controller.quickAccessSubtitle(key)),
    enabled: enabled,
    onTap: !enabled
        ? null
        : () async {
            await Utils.switchRightDialog(() async {
              _openQuickAccessItem(controller, key);
            });
          },
  );
}

void _openQuickAccessItem(LiveRoomController controller, String key) {
  switch (key) {
    case "follow":
      showFollowUser(controller);
      break;
    case "history":
      controller.openHistoryPage();
      break;
    case "recommendation":
      controller.openCategoryRecommendation();
      break;
    case "contribution_rank":
      controller.showContributionRankSheet();
      break;
  }
}

void showFollowUser(LiveRoomController controller) {
  if (controller.useBottomSheetPlayerMenus) {
    controller.showFollowUserSheet();
    return;
  }

  Utils.showRightDialog(
    title: "关注列表",
    width: 400,
    useSystem: false,
    child: controller.buildFollowUserSelection(
      onClose: Utils.hideRightDialog,
      scrollController: controller.liveRoomFollowDialogScrollController,
    ),
  );
}

class PlayerSuperChatCard extends StatefulWidget {
  final LiveSuperChatMessage message;
  final VoidCallback onExpire;
  final int duration;
  final VoidCallback? onUserTap;
  final VoidCallback? onUserLongPress;
  const PlayerSuperChatCard(
      {required this.message,
      required this.onExpire,
      required this.duration,
      this.onUserTap,
      this.onUserLongPress,
      Key? key})
      : super(key: key);
  @override
  State<PlayerSuperChatCard> createState() => _PlayerSuperChatCardState();
}

class _PlayerSuperChatCardState extends State<PlayerSuperChatCard> {
  Timer? timer;
  late int countdown;
  @override
  void initState() {
    super.initState();
    _restartCountdown();
  }

  void _restartCountdown() {
    timer?.cancel();
    countdown = widget.duration;
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (countdown <= 1) {
        widget.onExpire();
        timer?.cancel();
        return;
      }
      setState(() {
        countdown = (countdown - 1).clamp(0, 1 << 30).toInt();
      });
    });
  }

  @override
  void didUpdateWidget(covariant PlayerSuperChatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        oldWidget.duration != widget.duration) {
      _restartCountdown();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.65,
      child: SuperChatCard(
        widget.message,
        onExpire: () {},
        customCountdown: countdown,
        onUserTap: widget.onUserTap,
        onUserLongPress: widget.onUserLongPress,
      ),
    );
  }
}

class LocalDisplaySC {
  LiveSuperChatMessage sc;
  final DateTime expireAt;
  final int duration;
  LocalDisplaySC(this.sc, this.expireAt, this.duration);

  String get fingerprint {
    final id = sc.id?.trim();
    if (id != null && id.isNotEmpty) {
      return "id:$id";
    }
    return "${sc.userName}|${sc.message}|${sc.price}|${sc.startTime.millisecondsSinceEpoch}";
  }
}

class PlayerSuperChatOverlay extends StatefulWidget {
  final LiveRoomController controller;
  const PlayerSuperChatOverlay({required this.controller, Key? key})
      : super(key: key);
  @override
  State<PlayerSuperChatOverlay> createState() => _PlayerSuperChatOverlayState();
}

class _PlayerSuperChatOverlayState extends State<PlayerSuperChatOverlay> {
  final List<LocalDisplaySC> _displayed = [];
  final Map<LocalDisplaySC, Timer> _timers = {};
  late Worker _worker;

  String _fingerprintOf(LiveSuperChatMessage sc) {
    final id = sc.id?.trim();
    if (id != null && id.isNotEmpty) {
      return "id:$id";
    }
    return "${sc.userName}|${sc.message}|${sc.price}|${sc.startTime.millisecondsSinceEpoch}";
  }

  void _removeLocalSC(LocalDisplaySC localSC) {
    _displayed.remove(localSC);
    _timers.remove(localSC)?.cancel();
  }

  void _addSC(LiveSuperChatMessage sc, {int? customSeconds}) {
    final fingerprint = _fingerprintOf(sc);
    int showSeconds = (customSeconds ?? 15).clamp(1, 1 << 30).toInt();
    final currentIndex = _displayed.indexWhere(
      (e) => e.fingerprint == fingerprint,
    );
    if (currentIndex >= 0) {
      final current = _displayed[currentIndex];
      current.sc = sc;
      setState(() {});
      return;
    }
    final expireAt = DateTime.now().add(Duration(seconds: showSeconds));
    final localSC = LocalDisplaySC(sc, expireAt, showSeconds);
    _displayed.add(localSC);
    _timers[localSC] = Timer(Duration(seconds: showSeconds), () {
      setState(() {
        _removeLocalSC(localSC);
      });
    });
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // 初始化时先把仍在有效期内的头条恢复到播放器悬浮层里。
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var sc in widget.controller.superChats) {
      int remain = (sc.endTime.millisecondsSinceEpoch - now) ~/ 1000;
      if (remain > 0) {
        _addSC(sc, customSeconds: remain < 15 ? remain : 15);
      }
    }
    // 监听头条列表变化，同步更新悬浮展示队列。
    _worker =
        ever<List<LiveSuperChatMessage>>(widget.controller.superChats, (list) {
      for (var sc in list) {
        final remain = sc.endTime.difference(DateTime.now()).inSeconds;
        _addSC(sc, customSeconds: remain > 0 && remain < 15 ? remain : 15);
      }
      final latestFingerprints = list.map(_fingerprintOf).toSet();
      for (final localSC in _displayed.toList()) {
        if (!latestFingerprints.contains(localSC.fingerprint)) {
          _removeLocalSC(localSC);
        }
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _worker.dispose();
    for (var t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _displayed.toList()
      ..sort((a, b) => a.sc.endTime.compareTo(b.sc.endTime));
    if (AppSettingsController.instance.superChatSortDesc.value) {
      sorted.replaceRange(0, sorted.length, sorted.reversed);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var localSC in sorted)
          Padding(
            key: ValueKey(localSC.fingerprint),
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: 240,
              child: PlayerSuperChatCard(
                key: ValueKey(localSC.fingerprint),
                message: localSC.sc,
                onExpire: () {
                  setState(() {
                    _removeLocalSC(localSC);
                  });
                },
                duration: localSC.duration,
                onUserTap: () => widget.controller.showUserActions(
                  localSC.sc.userName,
                  messageContent: localSC.sc.message,
                ),
                onUserLongPress: () =>
                    widget.controller.copyUserName(localSC.sc.userName),
              ),
            ),
          ),
      ],
    );
  }
}
