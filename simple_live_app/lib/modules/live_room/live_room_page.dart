import 'dart:io';

import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/platform_utils.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_controls.dart';
import 'package:simple_live_app/modules/live_room/player/ohos_video_player.dart';
import 'package:simple_live_app/modules/live_room/widgets/live_contribution_rank_panel.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/live_link_health_presentation.dart';
import 'package:simple_live_app/widgets/chat_message_item.dart';
import 'package:simple_live_app/widgets/keep_alive_wrapper.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_app/widgets/settings/settings_action.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_number.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';
import 'package:simple_live_app/widgets/status/app_empty_widget.dart';
import 'package:simple_live_app/widgets/superchat_card.dart';
import 'package:simple_live_core/simple_live_core.dart';

class LiveRoomPage extends GetView<LiveRoomController> {
  static const double _desktopSidePanelWidth = 300.0;
  static const double _desktopSidePanelCollapsedWidth = 48.0;
  static const double _ohosFullscreenHorizontalInset = 28.0;

  const LiveRoomPage({Key? key}) : super(key: key);

  /// 打开网络诊断弹窗：测试当前播放端点的 TCP 连接耗时与可达性。
  void showNetworkDiagnose(LiveRoomController controller) {
    Utils.showModalBottomSheetSafe(
      context: Get.context!,
      constraints: const BoxConstraints(
        maxWidth: 600,
      ),
      builder: (context) => SingleChildScrollView(
        child: _NetworkDiagnosePanel(controller: controller),
      ),
    );
  }

  double _bottomSafeInset(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final viewPadding = mediaQuery.viewPadding.bottom;
    final padding = mediaQuery.padding.bottom;
    return viewPadding > padding ? viewPadding : padding;
  }

  double _bottomActionInset(BuildContext context) {
    if (Platform.isIOS &&
        MediaQuery.of(context).orientation == Orientation.landscape) {
      return 0;
    }
    final safeInset = _bottomSafeInset(context);
    if (!Platform.isIOS) {
      return safeInset;
    }
    return safeInset.clamp(0.0, 16.0).toDouble();
  }

  bool get _isDesktop {
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  double _landscapeSideWidth(double maxWidth) {
    if (maxWidth <= _desktopSidePanelWidth) {
      return 0.0;
    }
    if (_isDesktop && controller.desktopSidePanelCollapsed.value) {
      return _desktopSidePanelCollapsedWidth;
    }
    return _desktopSidePanelWidth;
  }

  Widget _buildRoomTitleText() {
    return Obx(
      () => Text(
        controller.detail.value?.title ?? "直播间",
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildMobileAppBarTitle(BuildContext context) {
    return SizedBox(
      height: kToolbarHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: kToolbarHeight),
              child: Center(
                child: _buildRoomTitleText(),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => _handleBack(context),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: showMore,
              icon: const Icon(Icons.more_horiz),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeAppBarTitle(BuildContext context) {
    if (_isDesktop) {
      return Obx(() => _buildLandscapeAppBarTitleContent(context));
    }
    return _buildLandscapeAppBarTitleContent(context);
  }

  Widget _buildLandscapeAppBarTitleContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sidePanelWidth = _landscapeSideWidth(constraints.maxWidth);
        final playerWidth = constraints.maxWidth - sidePanelWidth;
        return SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              SizedBox(
                width: playerWidth,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: kToolbarHeight,
                          right: 16,
                        ),
                        child: Center(
                          child: _buildRoomTitleText(),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => _handleBack(context),
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: sidePanelWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: showMore,
                    icon: const Icon(Icons.more_horiz),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopOverlayIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withAlpha(120),
        borderRadius: AppStyle.radius24,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          color: Colors.white,
        ),
      ),
    );
  }

  List<Widget> _buildDesktopOverlayButtons(BuildContext context) {
    return [
      Obx(() {
        if (!controller.showControlsState.value) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            Positioned(
              left: 8,
              top: 8,
              child: _buildDesktopOverlayIconButton(
                tooltip: "返回",
                icon: Icons.arrow_back,
                onPressed: () => _handleBack(context),
              ),
            ),
            Positioned(
              right: 8,
              top: controller.desktopSidePanelCollapsed.value ? 56 : 8,
              child: _buildDesktopOverlayIconButton(
                tooltip: "更多",
                icon: Icons.more_horiz,
                onPressed: showMore,
              ),
            ),
            if (Platform.isWindows &&
                controller.desktopSidePanelCollapsed.value)
              Positioned(
                right: 8,
                top: 8,
                child: _buildDesktopOverlayIconButton(
                  tooltip: "关闭",
                  icon: Icons.close,
                  onPressed: () => _handleBack(context),
                ),
              ),
            if (_isDesktop && controller.desktopSidePanelCollapsed.value)
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildDesktopOverlayIconButton(
                    tooltip: "展开聊天区",
                    icon: Icons.chevron_left,
                    onPressed: controller.toggleDesktopSidePanel,
                  ),
                ),
              ),
          ],
        );
      }),
    ];
  }

  bool _allowsNativePopGesture() {
    return Platform.isIOS &&
        !controller.fullScreenState.value &&
        !controller.smallWindowState.value;
  }

  @override
  Widget build(BuildContext context) {
    final page = Obx(() {
      if (controller.loadError.value) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("直播间加载失败"),
          ),
          body: Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LottieBuilder.asset(
                  'assets/lotties/error.json',
                  height: 140,
                  repeat: false,
                ),
                const Text(
                  "直播间加载失败",
                  textAlign: TextAlign.center,
                ),
                AppStyle.vGap4,
                Text(
                  controller.error?.toString() ?? "未知错误",
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                AppStyle.vGap4,
                Text(
                  "${controller.rxSite.value.id} - ${controller.rxRoomId.value}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: controller.copyErrorDetail,
                      icon: const Icon(Remix.file_copy_line),
                      label: const Text("复制信息"),
                    ),
                    TextButton.icon(
                      onPressed: controller.refreshRoom,
                      icon: const Icon(Remix.refresh_line),
                      label: const Text("刷新"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
      if (controller.fullScreenState.value) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            controller.exitPlayerWindowMode();
          },
          child: Scaffold(
            body: buildMediaPlayer(),
          ),
        );
      }
      return buildPageUI();
    });
    return page;
  }

  Widget buildPageUI() {
    return OrientationBuilder(
      builder: (context, orientation) {
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final isCompactMobile = shortestSide < 600;
        final usePortraitLayout = PlatformUtils.isMobileApp &&
            isCompactMobile &&
            !controller.fullScreenState.value &&
            !controller.smallWindowState.value;
        final effectiveOrientation =
            usePortraitLayout ? Orientation.portrait : orientation;
        final hasLandscapeActionPanel =
            effectiveOrientation == Orientation.landscape;
        if (_isDesktop) {
          final body = effectiveOrientation == Orientation.portrait
              ? buildPhoneUI(context)
              : buildTabletUI(context);
          return PopScope(
            canPop: _allowsNativePopGesture(),
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) {
                await controller.cancelAutoPipOnLeave();
                return;
              }
              await _handleBack(context);
            },
            child: Scaffold(
              body: MouseRegion(
                onEnter: (_) => controller.showControls(),
                onHover: (_) => controller.showControls(),
                child: Stack(
                  children: [
                    body,
                    ..._buildDesktopOverlayButtons(context),
                  ],
                ),
              ),
            ),
          );
        }
        final scaffold = Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            title: hasLandscapeActionPanel
                ? _buildLandscapeAppBarTitle(context)
                : _buildMobileAppBarTitle(context),
          ),
          body: effectiveOrientation == Orientation.portrait
              ? buildPhoneUI(context)
              : buildTabletUI(context),
        );
        return PopScope(
          canPop: _allowsNativePopGesture(),
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) {
              await controller.cancelAutoPipOnLeave();
              return;
            }
            await _handleBack(context);
          },
          child: scaffold,
        );
      },
    );
  }

  Future<void> _handleBack(BuildContext context) async {
    await controller.cancelAutoPipOnLeave();
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget buildPhoneUI(BuildContext context) {
    if (_isDesktop && controller.desktopSidePanelCollapsed.value) {
      return Column(
        children: [
          Expanded(
            child: buildMediaPlayer(),
          ),
          _buildCollapsedDesktopBottomPanel(context),
        ],
      );
    }
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: buildMediaPlayer(),
        ),
        buildUserProfile(context),
        buildMessageArea(),
        buildBottomActions(context),
      ],
    );
  }

  Widget buildTabletUI(BuildContext context) {
    return Obx(() {
      final collapsed =
          _isDesktop && controller.desktopSidePanelCollapsed.value;
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: buildMediaPlayer(),
                ),
                if (!collapsed) _buildExpandedSidePanel(context),
              ],
            ),
          ),
          if (!collapsed)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  top: BorderSide(
                    color: Colors.grey.withAlpha(25),
                  ),
                ),
              ),
              padding: AppStyle.edgeInsetsV4.copyWith(
                bottom: _bottomActionInset(context) + 4,
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 14),
                    ),
                    onPressed: controller.refreshRoom,
                    icon: const Icon(Remix.refresh_line),
                    label: const Text("刷新"),
                  ),
                  AppStyle.hGap4,
                  Obx(
                    () => controller.followed.value
                        ? TextButton.icon(
                            style: TextButton.styleFrom(
                              textStyle: const TextStyle(fontSize: 14),
                            ),
                            onPressed: controller.removeFollowUser,
                            icon: const Icon(Remix.heart_fill),
                            label: const Text("取消关注"),
                          )
                        : TextButton.icon(
                            style: TextButton.styleFrom(
                              textStyle: const TextStyle(fontSize: 14),
                            ),
                            onPressed: controller.followUser,
                            icon: const Icon(Remix.heart_line),
                            label: const Text("关注"),
                          ),
                  ),
                  const Expanded(child: Center()),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 14),
                    ),
                    onPressed: controller.share,
                    icon: const Icon(Remix.share_line),
                    label: const Text("分享"),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 14),
                    ),
                    onPressed: controller.copyUrl,
                    icon: const Icon(Remix.file_copy_line),
                    label: const Text("复制链接"),
                  ),
                  Obx(
                    () => AppSettingsController.instance.playerShowPlayUrl.value
                        ? TextButton.icon(
                            style: TextButton.styleFrom(
                              textStyle: const TextStyle(fontSize: 14),
                            ),
                            onPressed: controller.copyPlayUrl,
                            icon: const Icon(Remix.file_copy_line),
                            label: const Text("复制播放直链"),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  Widget _buildExpandedSidePanel(BuildContext context) {
    final showCollapseAction = _isDesktop;
    return SizedBox(
      width: _desktopSidePanelWidth,
      child: Column(
        children: [
          if (showCollapseAction)
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  left: BorderSide(
                    color: Colors.grey.withAlpha(25),
                  ),
                  bottom: BorderSide(
                    color: Colors.grey.withAlpha(25),
                  ),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: "折叠聊天区",
                child: IconButton(
                  onPressed: controller.toggleDesktopSidePanel,
                  icon: const Icon(Icons.chevron_right),
                ),
              ),
            ),
          Expanded(
            child: Column(
              children: [
                buildUserProfile(context),
                buildMessageArea(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedDesktopBottomPanel(BuildContext context) {
    return Container(
      height: 48 + _bottomActionInset(context),
      padding: EdgeInsets.only(bottom: _bottomActionInset(context)),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Colors.grey.withAlpha(25),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Tooltip(
              message: "展开聊天区",
              child: IconButton(
                onPressed: controller.toggleDesktopSidePanel,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: Icon(
                Icons.chat_bubble_outline,
                size: 18,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 56),
        ],
      ),
    );
  }

  Widget buildMediaPlayer() {
    if (Utils.isOhos) {
      return _buildOhosMediaPlayer();
    }
    final playerContent = _buildMediaPlayerContent();
    if (!Platform.isAndroid) {
      return playerContent;
    }
    return PiPSwitcher(
      floating: controller.pip,
      childWhenDisabled: playerContent,
      childWhenEnabled: playerContent,
    );
  }

  Widget _buildOhosMediaPlayer() {
    return Builder(
      builder: (context) => ColoredBox(
        color: Colors.black,
        child: Obx(() {
          final revision = controller.ohosPlayerRevision.value;
          controller.ohosScaleRevision.value;
          final fullScreen = controller.fullScreenState.value;
          final controlsVisible = controller.showControlsState.value &&
              !controller.lockControlsState.value;
          final mediaQuery = MediaQuery.of(context);
          final safePadding = EdgeInsets.fromLTRB(
            mediaQuery.viewPadding.left,
            mediaQuery.viewPadding.top,
            mediaQuery.viewPadding.right,
            mediaQuery.viewPadding.bottom,
          );
          if (controller.showOfflineOverlay) {
            return Stack(
              fit: StackFit.expand,
              children: [
                const Center(
                  child: Text(
                    "未开播",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                if (fullScreen)
                  _buildOhosTopBarOverlay(
                    context,
                    controlsVisible: controlsVisible,
                    safePadding: safePadding,
                  ),
              ],
            );
          }
          if (controller.currentLineIndex < 0 || controller.playUrls.isEmpty) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: controller.waitingForPlaybackUrl.value
                      ? const Text(
                          "正在获取播放地址",
                          style: TextStyle(color: Colors.white),
                        )
                      : const CircularProgressIndicator(),
                ),
                if (fullScreen)
                  _buildOhosTopBarOverlay(
                    context,
                    controlsVisible: controlsVisible,
                    safePadding: safePadding,
                  ),
              ],
            );
          }

          var url = controller.playUrls[controller.currentLineIndex];
          if (AppSettingsController.instance.playerForceHttps.value) {
            url = url.replaceAll("http://", "https://");
          }
          var fit = BoxFit.contain;
          double? forcedAspectRatio;
          switch (AppSettingsController.instance.scaleMode.value) {
            case 1:
              fit = BoxFit.fill;
              break;
            case 2:
              fit = BoxFit.cover;
              break;
            case 3:
              forcedAspectRatio = 16 / 9;
              break;
            case 4:
              forcedAspectRatio = 4 / 3;
              break;
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                key: controller.ohosScreenshotKey,
                child: OhosVideoPlayer(
                  key: controller.ohosPlayerWidgetKey,
                  url: url,
                  revision: revision,
                  headers: controller.playHeaders,
                  onError: controller.mediaError,
                  onControllerReady: controller.attachOhosVideoController,
                  onControllerDisposed: controller.detachOhosVideoController,
                  onGenerationValueChanged:
                      controller.updateOhosVideoStateForGeneration,
                  onFirstFrame: controller.updateOhosFirstFrameForGeneration,
                  onCompleted: controller.mediaEnd,
                  initialVolume: controller.ohosVolume.value,
                  fit: fit,
                  forcedAspectRatio: forcedAspectRatio,
                ),
              ),
              if (!controller.ohosScreenshotInProgress.value)
                buildDanmuView(context, controller),
              if (!controller.ohosScreenshotInProgress.value)
                buildPlayerSuperChatOverlay(controller),
              buildPlayerGestureLayer(
                controller,
                enableQuickAccessLongPress: fullScreen,
              ),
              if (controller.ohosBuffering.value &&
                  !controller.ohosScreenshotInProgress.value)
                const Center(child: CircularProgressIndicator()),
              if (fullScreen && !controller.ohosScreenshotInProgress.value)
                _buildOhosTopBarOverlay(
                  context,
                  controlsVisible: controlsVisible,
                  safePadding: safePadding,
                ),
              if (!controller.ohosScreenshotInProgress.value)
                AnimatedPositioned(
                  left: 0,
                  right: 0,
                  bottom: controlsVisible
                      ? 0
                      : -(fullScreen ? 80 : 48) - safePadding.bottom,
                  duration: const Duration(milliseconds: 200),
                  child: _buildOhosBottomBar(context),
                ),
              if (fullScreen)
                AnimatedPositioned(
                  left: controller.lockControlsState.value || controlsVisible
                      ? safePadding.left + _ohosFullscreenHorizontalInset
                      : -(64 + safePadding.left),
                  top: 0,
                  bottom: 0,
                  duration: const Duration(milliseconds: 200),
                  child: buildLockButton(controller),
                ),
              buildGestureTip(controller),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildOhosTopBarOverlay(
    BuildContext context, {
    required bool controlsVisible,
    required EdgeInsets safePadding,
  }) {
    return AnimatedPositioned(
      left: 0,
      right: 0,
      top: controlsVisible ? 0 : -(48 + safePadding.top),
      duration: const Duration(milliseconds: 200),
      child: _buildOhosTopBar(context),
    );
  }

  Widget _buildOhosTopBar(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final detail = controller.detail.value;
    final title = detail?.title ?? "直播间";
    final userName = detail?.userName ?? "";
    return Container(
      height: 48 + padding.top,
      padding: EdgeInsets.only(
        left: padding.left + _ohosFullscreenHorizontalInset,
        right: padding.right + _ohosFullscreenHorizontalInset,
        top: padding.top,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: "退出全屏",
            onPressed: controller.exitFull,
            icon: const Icon(
              Icons.arrow_back,
              color: Colors.white,
              size: 24,
            ),
          ),
          AppStyle.hGap12,
          Expanded(
            child: Text(
              userName.isEmpty ? title : "$title - $userName",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          AppStyle.hGap12,
          IconButton(
            tooltip: "快捷入口",
            onPressed: () => showQuickAccess(controller),
            icon: const Icon(
              Remix.play_list_2_line,
              color: Colors.white,
              size: 24,
            ),
          ),
          IconButton(
            tooltip: "播放器设置",
            onPressed: () => showPlayerSettings(controller),
            icon: const Icon(Icons.more_horiz, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildOhosBottomBar(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullScreen = controller.fullScreenState.value;
        final padding = fullScreen ? mediaQuery.viewPadding : EdgeInsets.zero;
        // 底栏在窄屏/横屏全屏时会把清晰度、线路、时长等全部撑开导致横向
        // overflow。compact 不再排除全屏：只要可用宽度不足就收起次要文本与
        // 弹幕设置按钮（"更多功能"菜单里仍可访问），避免 Row 溢出。
        final compact = constraints.maxWidth < 520;
        return Container(
          height: 48 + padding.bottom,
          padding: EdgeInsets.only(
            left:
                fullScreen ? padding.left + _ohosFullscreenHorizontalInset : 0,
            right:
                fullScreen ? padding.right + _ohosFullscreenHorizontalInset : 0,
            bottom: padding.bottom,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: "刷新直播间",
                onPressed: controller.refreshRoom,
                icon: const Icon(Remix.refresh_line, color: Colors.white),
              ),
              IconButton(
                tooltip: "弹幕开关",
                onPressed: controller.toggleDanmakuByShortcut,
                icon: ImageIcon(
                  AssetImage(
                    controller.showDanmakuState.value
                        ? 'assets/icons/icon_danmaku_close.png'
                        : 'assets/icons/icon_danmaku_open.png',
                  ),
                  size: 24,
                  color: Colors.white,
                ),
              ),
              if (!compact)
                IconButton(
                  tooltip: "弹幕设置",
                  onPressed: () => showDanmakuSettings(controller),
                  icon: const ImageIcon(
                    AssetImage('assets/icons/icon_danmaku_setting.png'),
                    size: 24,
                    color: Colors.white,
                  ),
                ),
              if (!compact)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    controller.liveDuration.value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              const Spacer(),
              if (!compact || fullScreen)
                IconButton(
                  tooltip: controller.mutedState.value ? "恢复声音" : "静音",
                  onPressed: controller.toggleMute,
                  icon: Icon(
                    controller.mutedState.value
                        ? Icons.volume_off
                        : Icons.volume_up,
                    color: Colors.white,
                  ),
                ),
              if (fullScreen && !compact && controller.qualites.isNotEmpty)
                TextButton(
                  onPressed: () => showQualitesInfo(controller),
                  child: Text(
                    controller.currentQualityInfo.value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ),
              if (fullScreen && !compact && controller.playUrls.isNotEmpty)
                TextButton(
                  onPressed: () => showLinesInfo(controller),
                  child: Text(
                    controller.currentLineInfo.value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ),
              if (compact)
                IconButton(
                  tooltip: "更多功能",
                  onPressed: _showOhosPlayerMenu,
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                ),
              IconButton(
                tooltip: fullScreen ? "退出全屏" : "全屏",
                onPressed: fullScreen
                    ? controller.exitFull
                    : controller.enterFullScreen,
                icon: Icon(
                  fullScreen
                      ? Remix.fullscreen_exit_fill
                      : Remix.fullscreen_line,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showOhosPlayerMenu() {
    Utils.showBottomSheet(
      title: "播放器功能",
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: Icon(
              controller.mutedState.value ? Icons.volume_off : Icons.volume_up,
            ),
            title: Text(controller.mutedState.value ? "恢复声音" : "静音"),
            onTap: () {
              Get.back();
              controller.toggleMute();
            },
          ),
          ListTile(
            leading: const Icon(Icons.subtitles_outlined),
            title: const Text("弹幕设置"),
            onTap: () {
              Get.back();
              showDanmakuSettings(controller);
            },
          ),
          ListTile(
            leading: const Icon(Icons.aspect_ratio),
            title: const Text("画面尺寸"),
            onTap: () {
              Get.back();
              showPlayerSettings(controller);
            },
          ),
          if (controller.qualites.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.high_quality_outlined),
              title: const Text("画质"),
              subtitle: Text(controller.currentQualityInfo.value),
              onTap: () {
                Get.back();
                showQualitesInfo(controller);
              },
            ),
          if (controller.playUrls.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.route),
              title: const Text("播放线路"),
              subtitle: Text(controller.currentLineInfo.value),
              onTap: () {
                Get.back();
                showLinesInfo(controller);
              },
            ),
          ListTile(
            leading: const Icon(Icons.playlist_play),
            title: const Text("快捷入口"),
            onTap: () {
              Get.back();
              showQuickAccess(controller);
            },
          ),
          if (controller.fullScreenState.value)
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text("锁定控制"),
              onTap: () {
                Get.back();
                controller.setLockState();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMediaPlayerContent() {
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
        const Positioned.fill(
          child: ColoredBox(color: Colors.black),
        ),
        Video(
          key: controller.globalPlayerKey,
          controller: controller.videoController,
          pauseUponEnteringBackgroundMode:
              !AppSettingsController.instance.allowBackgroundPlayback.value,
          resumeUponEnteringForegroundMode:
              !AppSettingsController.instance.allowBackgroundPlayback.value,
          controls: (state) {
            return playerControls(state, controller);
          },
          aspectRatio: aspectRatio,
          fit: boxFit,
          // 自己实现
          wakelock: false,
        ),
        Obx(
          () => Visibility(
            visible: controller.showOfflineOverlay,
            child: const Center(
              child: Text(
                "未开播",
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
        ),
        Obx(
          () => Visibility(
            visible: controller.waitingForPlaybackUrl.value &&
                !controller.showOfflineOverlay,
            child: const Center(
              child: Text(
                "正在获取播放地址",
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
        ),
        // 自动网络诊断提示（缓冲 2 次以上触发）
        Obx(
          () => controller.networkHint.value.isEmpty
              ? const SizedBox.shrink()
              : Positioned(
                  left: 12,
                  top: 12,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 340),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(180),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      controller.networkHint.value,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget buildUserProfile(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Colors.grey.withAlpha(25),
          ),
          bottom: BorderSide(
            color: Colors.grey.withAlpha(25),
          ),
        ),
      ),
      padding: AppStyle.edgeInsetsA8.copyWith(
        left: 12,
        right: 12,
      ),
      child: Obx(
        () => Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withAlpha(50)),
                borderRadius: AppStyle.radius24,
              ),
              child: NetImage(
                controller.detail.value?.userAvatar ?? "",
                width: 48,
                height: 48,
                borderRadius: 24,
              ),
            ),
            AppStyle.hGap12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.detail.value?.userName ?? "",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  AppStyle.vGap4,
                  Row(
                    children: [
                      Image.asset(
                        controller.site.logo,
                        width: 20,
                      ),
                      AppStyle.hGap4,
                      Text(
                        controller.site.name,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AppStyle.hGap12,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Remix.fire_fill,
                  size: 20,
                  color: Colors.orange,
                ),
                AppStyle.hGap4,
                Text(
                  Utils.onlineToString(
                    controller.online.value,
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildBottomActions(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Colors.grey.withAlpha(25),
          ),
        ),
      ),
      padding: EdgeInsets.only(bottom: _bottomActionInset(context)),
      child: Row(
        children: [
          Expanded(
            child: Obx(
              () => controller.followed.value
                  ? TextButton.icon(
                      style: TextButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      onPressed: controller.removeFollowUser,
                      icon: const Icon(Remix.heart_fill),
                      label: const Text("取消关注"),
                    )
                  : TextButton.icon(
                      style: TextButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      onPressed: controller.followUser,
                      icon: const Icon(Remix.heart_line),
                      label: const Text("关注"),
                    ),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 14),
              ),
              onPressed: controller.refreshRoom,
              icon: const Icon(Remix.refresh_line),
              label: const Text("刷新"),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 14),
              ),
              onPressed: controller.share,
              icon: const Icon(Remix.share_line),
              label: const Text("分享"),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildMessageArea() {
    return Obx(() {
      final hasSuperChatTab = controller.site.id == Constant.kBiliBili ||
          controller.site.id == Constant.kHuya;
      final tabs = <Widget>[];
      final pages = <Widget>[];
      final keys = <String>[];
      void addTab(String key) {
        switch (key) {
          case "chat":
            keys.add(key);
            tabs.add(const Tab(text: "聊天"));
            pages.add(buildChatList());
            break;
          case "super_chat":
            if (!hasSuperChatTab) return;
            keys.add(key);
            tabs.add(
              Tab(
                child: Text(
                  controller.superChats.isNotEmpty
                      ? "${controller.site.id == Constant.kHuya ? "头条" : "SC"}(${controller.superChats.length})"
                      : controller.site.id == Constant.kHuya
                          ? "头条"
                          : "SC",
                ),
              ),
            );
            pages.add(buildSuperChats());
            break;
          case "follow":
            keys.add(key);
            tabs.add(const Tab(text: "关注"));
            pages.add(buildFollowList());
            break;
          case "contribution_rank":
            if (!controller.supportsContributionRank ||
                !AppSettingsController.instance.contributionRankEnable.value) {
              return;
            }
            keys.add(key);
            tabs.add(
              Tab(
                text: controller.site.id == Constant.kDouyu ? "亲密榜" : "贡献榜",
              ),
            );
            pages.add(
              KeepAliveWrapper(
                child: LiveContributionRankPanel(controller: controller),
              ),
            );
            break;
          case "event_flow":
            if (!AppSettingsController.instance.liveEventFlowEnable.value) {
              return;
            }
            keys.add(key);
            tabs.add(
              Tab(
                child: Text(
                  controller.liveEventFlows.isNotEmpty
                      ? "动态(${controller.liveEventFlows.length})"
                      : "动态",
                ),
              ),
            );
            pages.add(buildLiveEventFlow());
            break;
          case "settings":
            keys.add(key);
            tabs.add(const Tab(text: "设置"));
            pages.add(buildSettings());
            break;
        }
      }

      for (final key in AppSettingsController.instance.liveRoomTabSort) {
        addTab(key);
      }
      if (tabs.isEmpty) {
        keys.add("chat");
        tabs.add(const Tab(text: "聊天"));
        pages.add(buildChatList());
      }
      final selectedKey = controller.liveRoomSelectedPanelKey.value;
      final initialIndex =
          keys.contains(selectedKey) ? keys.indexOf(selectedKey) : 0;
      return Expanded(
        child: DefaultTabController(
          key: ValueKey(keys.join("|")),
          length: tabs.length,
          initialIndex: initialIndex,
          child: Column(
            children: [
              TabBar(
                indicatorSize: TabBarIndicatorSize.tab,
                labelPadding: EdgeInsets.zero,
                indicatorWeight: 1.0,
                onTap: (index) {
                  if (index >= 0 && index < keys.length) {
                    controller.liveRoomSelectedPanelKey.value = keys[index];
                  }
                },
                tabs: tabs,
              ),
              Expanded(
                child: TabBarView(
                  children: pages,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget buildChatList() {
    return Stack(
      children: [
        ListView.separated(
          controller: controller.scrollController,
          reverse: false,
          separatorBuilder: (_, i) => SizedBox(
            // *2与原来的EdgeInsets.symmetric(vertical: )做兼容
            height: AppSettingsController.instance.chatTextGap.value * 2,
          ),
          padding: AppStyle.edgeInsetsA12,
          itemCount: controller.messages.length,
          itemBuilder: (_, i) {
            var item = controller.messages[i];
            return buildMessageItem(item);
          },
        ),
        Visibility(
          visible: controller.disableAutoScroll.value,
          child: Positioned(
            right: 12,
            bottom: 12,
            child: ElevatedButton.icon(
              onPressed: () {
                controller.forceChatScrollToBottom();
              },
              icon: const Icon(Icons.expand_more),
              label: const Text("最新"),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildLiveEventFlow() {
    return KeepAliveWrapper(
      child: Obx(() {
        if (!AppSettingsController.instance.liveEventFlowEnable.value) {
          return const AppEmptyWidget(message: "重点动态已关闭");
        }
        if (controller.liveEventFlows.isEmpty) {
          return const AppEmptyWidget(message: "暂未捕捉到重复动态");
        }
        return ListView.separated(
          padding: AppStyle.edgeInsetsA12,
          itemCount: controller.liveEventFlows.length,
          separatorBuilder: (_, i) => AppStyle.vGap8,
          itemBuilder: (_, i) {
            final item = controller.liveEventFlows[i];
            return ListTile(
              visualDensity: VisualDensity.compact,
              contentPadding: AppStyle.edgeInsetsL16.copyWith(right: 12),
              leading: const Icon(Remix.pulse_line),
              title: Text(
                item.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                "x${item.count}",
                style: Get.textTheme.titleMedium,
              ),
            );
          },
        );
      }),
    );
  }

  Widget buildMessageItem(LiveMessage message) {
    final remark = controller.getUserRemark(message.userName);
    return ChatMessageItem(
      message: message,
      remark: remark,
      onUserTap: () => controller.showUserActions(
        message.userName,
        messageContent: message.message,
      ),
      onUserLongPress: () => controller.copyUserName(message.userName),
    );
  }

  Widget buildSuperChats() {
    return KeepAliveWrapper(
      child: Obx(
        () => controller.superChats.isEmpty
            ? AppEmptyWidget(
                message: controller.site.id == Constant.kHuya
                    ? "当前直播间无头条内容"
                    : "当前直播间无 SC 内容",
              )
            : ListView.separated(
                padding: AppStyle.edgeInsetsA12,
                itemCount: controller.superChats.length,
                separatorBuilder: (_, i) => AppStyle.vGap12,
                itemBuilder: (_, i) {
                  var item = controller.sortedSuperChats[i];
                  return SuperChatCard(
                    item,
                    remark: controller.getUserRemark(item.userName),
                    key: ValueKey(
                      item.id ??
                          "${item.userName}|${item.message}|${item.price}|${item.startTime.millisecondsSinceEpoch}",
                    ),
                    onExpire: () {
                      controller.removeSuperChats();
                    },
                    onUserTap: () => controller.showUserActions(
                      item.userName,
                      messageContent: item.message,
                    ),
                    onUserLongPress: () =>
                        controller.copyUserName(item.userName),
                  );
                },
              ),
      ),
    );
  }

  Widget buildSettings() {
    return ListView(
      padding: AppStyle.edgeInsetsA12,
      children: [
        Obx(
          () => Visibility(
            visible: controller.autoExitEnable.value,
            child: ListTile(
              leading: const Icon(Icons.timer_outlined),
              visualDensity: VisualDensity.compact,
              title: Text("${parseDuration(controller.countdown.value)}后自动关闭"),
            ),
          ),
        ),
        Padding(
          padding: AppStyle.edgeInsetsA12,
          child: Text(
            "当前直播间",
            style: Get.textTheme.titleSmall,
          ),
        ),
        SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Obx(
                () => SettingsNumber(
                  title: "文字大小",
                  value:
                      AppSettingsController.instance.chatTextSize.value.toInt(),
                  min: 8,
                  max: 36,
                  onChanged: (e) {
                    AppSettingsController.instance
                        .setChatTextSize(e.toDouble());
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsSwitch(
                  title: "气泡样式",
                  value: AppSettingsController.instance.chatBubbleStyle.value,
                  onChanged: (e) {
                    AppSettingsController.instance.setChatBubbleStyle(e);
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsSwitch(
                  title: "重复弹幕过滤",
                  subtitle: "过滤短时间内重复出现的弹幕",
                  value: AppSettingsController.instance.danmuDedupeEnable.value,
                  onChanged: (e) {
                    AppSettingsController.instance.setDanmuDedupeEnable(e);
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: AppStyle.edgeInsetsA12,
          child: Text(
            "更多设置",
            style: Get.textTheme.titleSmall,
          ),
        ),
        SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsAction(
                title: "网络诊断与播放信息",
                onTap: _showDiagnosticsMenu,
              ),
              AppStyle.divider,
              SettingsAction(
                title: "关键词屏蔽",
                onTap: controller.showDanmuShield,
              ),
              AppStyle.divider,
              SettingsAction(
                title: "完整弹幕设置",
                onTap: () => Get.toNamed(RoutePath.kSettingsDanmu),
              ),
              AppStyle.divider,
              SettingsAction(
                title: "完整播放设置",
                onTap: () => Get.toNamed(RoutePath.kSettingsPlay),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildFollowList() {
    return KeepAliveWrapper(
      child: controller.buildFollowUserSelection(
        onClose: () {},
        scrollController: controller.liveRoomFollowScrollController,
      ),
    );
  }

  void showMore() {
    Utils.showModalBottomSheetSafe(
      context: Get.context!,
      constraints: const BoxConstraints(
        maxWidth: 600,
      ),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Utils.bottomSheetSafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text("播放调整"),
              subtitle: Text(
                "${controller.currentQualityInfo.value} · ${controller.currentLineInfo.value}",
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                _showPlaybackActions();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text("截图"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                controller.saveScreenshot();
              },
            ),
            Visibility(
              visible: Platform.isAndroid || Utils.isOhos,
              child: ListTile(
                leading: const Icon(Icons.picture_in_picture),
                title: const Text("小窗播放"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Get.back();
                  controller.enablePIP();
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text("定时关闭"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                controller.showAutoExitSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_outlined),
              title: const Text("分享与链接"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                _showShareActions();
              },
            ),
            ListTile(
              leading: const Icon(Icons.monitor_heart_outlined),
              title: const Text("网络诊断与播放信息"),
              subtitle: const Text("检查当前播放线路或查看播放器状态"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                _showDiagnosticsMenu();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaybackActions() {
    Utils.showBottomSheet(
      title: "播放调整",
      child: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text("切换清晰度"),
            subtitle: Text(controller.currentQualityInfo.value),
            onTap: () {
              Get.back();
              controller.showQualitySheet();
            },
          ),
          ListTile(
            leading: const Icon(Icons.switch_video_outlined),
            title: const Text("切换线路"),
            subtitle: Text(controller.currentLineInfo.value),
            onTap: () {
              Get.back();
              controller.showPlayUrlsSheet();
            },
          ),
          ListTile(
            leading: const Icon(Icons.aspect_ratio_outlined),
            title: const Text("画面尺寸"),
            onTap: () {
              Get.back();
              controller.showPlayerSettingsSheet();
            },
          ),
        ],
      ),
    );
  }

  void _showShareActions() {
    Utils.showBottomSheet(
      title: "分享与链接",
      child: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text("分享直播间"),
            onTap: () {
              Get.back();
              controller.share();
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text("复制直播链接"),
            onTap: () {
              Get.back();
              controller.copyUrl();
            },
          ),
          Obx(
            () => AppSettingsController.instance.playerShowPlayUrl.value
                ? ListTile(
                    leading: const Icon(Icons.link),
                    title: const Text("复制播放直链"),
                    subtitle: const Text("复制当前清晰度和播放线路"),
                    onTap: () {
                      Get.back();
                      controller.copyPlayUrl();
                    },
                  )
                : const SizedBox.shrink(),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text("在官方 APP 中打开"),
            onTap: () {
              Get.back();
              controller.openNaviteAPP();
            },
          ),
        ],
      ),
    );
  }

  void _showDiagnosticsMenu() {
    Utils.showBottomSheet(
      title: "网络诊断与播放信息",
      maxHeightFactor: 0.5,
      child: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.network_check_outlined),
            title: const Text("网络诊断"),
            subtitle: const Text("检查当前播放线路和公共 DNS 的连接"),
            onTap: () {
              Get.back();
              showNetworkDiagnose(controller);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text("播放信息"),
            subtitle: const Text("查看当前清晰度、线路和播放器状态"),
            onTap: () {
              Get.back();
              controller.showDebugInfo();
            },
          ),
        ],
      ),
    );
  }

  String parseDuration(int sec) {
    // 转为时分秒
    var h = sec ~/ 3600;
    var m = (sec % 3600) ~/ 60;
    var s = sec % 60;
    if (h > 0) {
      return "${h.toString().padLeft(2, '0')}小时${m.toString().padLeft(2, '0')}分钟${s.toString().padLeft(2, '0')}秒";
    }
    if (m > 0) {
      return "${m.toString().padLeft(2, '0')}分钟${s.toString().padLeft(2, '0')}秒";
    }
    return "${s.toString().padLeft(2, '0')}秒";
  }
}

/// 网络诊断面板：测试当前播放端点的 TCP 连接耗时与可达性。
class _NetworkDiagnosePanel extends StatefulWidget {
  final LiveRoomController controller;

  const _NetworkDiagnosePanel({required this.controller});

  @override
  State<_NetworkDiagnosePanel> createState() => _NetworkDiagnosePanelState();
}

class _NetworkDiagnosePanelState extends State<_NetworkDiagnosePanel> {
  final List<NetworkDiagnosisResult> _results = [];
  LiveLinkHealthPresentation? _healthPresentation;
  bool _running = true;
  String _summary = "";

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results.clear();
      _summary = "";
    });
    final playbackResult = await NetworkDiagnoseService.diagnosePlaybackUrl(
      widget.controller.currentNetworkDiagnosePlaybackUrl,
    );
    final results = [
      if (playbackResult != null) playbackResult,
    ];
    if (!mounted) return;
    final summary =
        NetworkDiagnoseService.summarizePlaybackEndpoint(playbackResult);
    final healthSnapshot = widget.controller.currentLiveLinkHealthSnapshot;
    setState(() {
      _results
        ..clear()
        ..addAll(results);
      _healthPresentation = healthSnapshot == null
          ? null
          : presentLiveLinkHealthSnapshot(
              healthSnapshot,
              currentBuffering:
                  widget.controller.currentLiveLinkHealthBuffering,
            );
      _summary = summary;
      _running = false;
    });
  }

  Widget _buildHealthSection() {
    final presentation = _healthPresentation;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "直播链路健康度",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                presentation?.levelLabel ?? liveLinkHealthDataUnavailableLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                presentation?.scoreLabel ?? liveLinkHealthDataUnavailableLabel,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "主要原因：${presentation?.primaryCauseLabel ?? liveLinkHealthDataUnavailableLabel}",
            style: const TextStyle(fontSize: 12),
          ),
          if (presentation != null) ...[
            const SizedBox(height: 8),
            for (final row in presentation.rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        row.label,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        row.value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text("网络诊断",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: "重新测试",
                  onPressed: _running ? null : _run,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  onPressed: Get.back,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (_running)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else ...[
              _buildHealthSection(),
              const SizedBox(height: 8),
              for (final r in _results)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.host,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        r.lost == r.samples
                            ? "不可达"
                            : "${r.avgMs.toStringAsFixed(0)}ms",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: r.lost == r.samples
                              ? Colors.red
                              : r.lost > 0 || r.avgMs > 250
                                  ? Colors.orange
                                  : Colors.green,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        r.lost > 0 ? "连接失败 ${r.lost}/${r.samples}" : "连接正常",
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        r.lost == r.samples ? "不可达" : r.latencyLabel,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _summary,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
