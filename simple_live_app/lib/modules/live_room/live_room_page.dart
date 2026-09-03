import 'dart:io';
import 'dart:math' as math;

import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_glass_mode.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/app/platform_utils.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_controls.dart';
import 'package:simple_live_app/modules/live_room/player/mpv_ohos_player.dart';
import 'package:simple_live_app/modules/live_room/widgets/live_contribution_rank_panel.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/widgets/chat_message_item.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';
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

  Widget _buildGlassAppBarButton({
    required BuildContext context,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: _buildStaticGlassPanel(
        context,
        radius: 22,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
        ),
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
            child: Padding(
              padding: EdgeInsets.only(
                left: math.max(MediaQuery.paddingOf(context).left, 8),
              ),
              child: _buildGlassAppBarButton(
                context: context,
                tooltip: "返回",
                onPressed: () => _handleBack(context),
                icon: Icons.arrow_back,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(
                right: math.max(MediaQuery.paddingOf(context).right, 8),
              ),
              child: _buildGlassAppBarButton(
                context: context,
                tooltip: "更多",
                onPressed: showMore,
                icon: Icons.more_horiz,
              ),
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
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: math.max(MediaQuery.paddingOf(context).left, 8),
                        ),
                        child: _buildGlassAppBarButton(
                          context: context,
                          tooltip: "返回",
                          onPressed: () => _handleBack(context),
                          icon: Icons.arrow_back,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: sidePanelWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: math.max(MediaQuery.paddingOf(context).right, 8),
                    ),
                    child: _buildGlassAppBarButton(
                      context: context,
                      tooltip: "更多",
                      onPressed: showMore,
                      icon: Icons.more_horiz,
                    ),
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
    required BuildContext context,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: _buildStaticGlassPanel(
        context,
        radius: 24,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(
            icon,
            color: Theme.of(context).colorScheme.onSurface,
          ),
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
              left: 12,
              top: 12,
              child: _buildDesktopOverlayIconButton(
                context: context,
                tooltip: "返回",
                icon: Icons.arrow_back,
                onPressed: () => _handleBack(context),
              ),
            ),
            Positioned(
              right: 12,
              top: controller.desktopSidePanelCollapsed.value ? 56 : 12,
              child: _buildDesktopOverlayIconButton(
                context: context,
                tooltip: "更多",
                icon: Icons.more_horiz,
                onPressed: showMore,
              ),
            ),
            if (Platform.isWindows &&
                controller.desktopSidePanelCollapsed.value)
              Positioned(
                right: 12,
                top: 12,
                child: _buildDesktopOverlayIconButton(
                  context: context,
                  tooltip: "关闭",
                  icon: Icons.close,
                  onPressed: () => _handleBack(context),
                ),
              ),
            if (_isDesktop && controller.desktopSidePanelCollapsed.value)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildDesktopOverlayIconButton(
                    context: context,
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
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (controller.kuaishouRecoveryHint.isNotEmpty) ...[
                  AppStyle.vGap4,
                  Text(
                    controller.kuaishouRecoveryHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                AppStyle.vGap4,
                Text(
                  "${controller.rxSite.value.id} - ${controller.rxRoomId.value}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: controller.copyErrorDetail,
                      icon: const Icon(Remix.file_copy_line),
                      label: const Text("复制信息"),
                    ),
                    TextButton.icon(
                      onPressed: controller.kuaishouRefreshBlocked
                          ? null
                          : controller.refreshRoom,
                      icon: const Icon(Remix.refresh_line),
                      label: Text(
                        controller.kuaishouRefreshBlocked
                            ? "冷却中 ${formatKuaishouRecoveryCountdown(controller.kuaishouRecoveryRemainingSeconds.value)}"
                            : "刷新",
                      ),
                    ),
                    if (controller.showKuaishouDeviceRecovery)
                      TextButton.icon(
                        onPressed: controller
                                    .kuaishouDeviceRecoveryAvailable.value &&
                                !controller.kuaishouDeviceRecoveryArmed.value
                            ? controller.rebuildKuaishouDeviceSession
                            : null,
                        icon: const Icon(Remix.restart_line),
                        label: Text(
                          controller.kuaishouDeviceRecoveryArmed.value
                              ? "等待自动重试"
                              : "重建设备会话",
                        ),
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
    return Obx(() {
      final glassOff =
          AppSettingsController.instance.glassMode.value == AppGlassMode.off;
      final profile = buildUserProfile(
        context,
        useStaticSurface: glassOff,
        showDividers: !glassOff,
      );
      return Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: buildMediaPlayer(),
          ),
          if (glassOff) const SizedBox(height: 8),
          if (glassOff)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: profile,
            )
          else
            profile,
          buildMessageArea(),
          buildBottomActions(context),
        ],
      );
    });
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
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: _buildStaticGlassPanel(
                context,
                radius: 20,
                role: GlassSurfaceRole.content,
                padding: AppStyle.edgeInsetsV4.copyWith(
                  bottom: _bottomActionInset(context) + 4,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _buildGlassActionButton(
                        context,
                        label: "刷新",
                        icon: Remix.refresh_line,
                        onPressed: controller.refreshRoom,
                      ),
                      AppStyle.hGap4,
                      Obx(
                        () => controller.followed.value
                            ? _buildGlassActionButton(
                                context,
                                label: "取消关注",
                                icon: Remix.heart_fill,
                                onPressed: controller.removeFollowUser,
                              )
                            : _buildGlassActionButton(
                                context,
                                label: "关注",
                                icon: Remix.heart_line,
                                onPressed: controller.followUser,
                              ),
                      ),
                      const Expanded(child: Center()),
                      _buildGlassActionButton(
                        context,
                        label: "分享",
                        icon: Remix.share_line,
                        onPressed: controller.share,
                      ),
                      _buildGlassActionButton(
                        context,
                        label: "复制链接",
                        icon: Remix.file_copy_line,
                        onPressed: controller.copyUrl,
                      ),
                      Obx(
                        () => AppSettingsController
                                .instance.playerShowPlayUrl.value
                            ? _buildGlassActionButton(
                                context,
                                label: "复制播放直链",
                                icon: Remix.file_copy_line,
                                onPressed: controller.copyPlayUrl,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: _buildStaticGlassPanel(
          context,
          radius: 24,
          role: GlassSurfaceRole.content,
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              if (showCollapseAction)
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    border: Border(
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
              buildUserProfile(context, useStaticSurface: true),
              const SizedBox(height: 8),
              buildMessageArea(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedDesktopBottomPanel(BuildContext context) {
    return _buildStaticGlassPanel(
      context,
      radius: 0,
      role: GlassSurfaceRole.navigation,
      child: Container(
        height: 48 + _bottomActionInset(context),
        padding: EdgeInsets.only(bottom: _bottomActionInset(context)),
        decoration: BoxDecoration(
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
      ),
    );
  }

  Widget _buildGlassActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return _buildStaticGlassPanel(
      context,
      radius: 18,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontSize: 14),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }

  Widget _buildStaticGlassPanel(
    BuildContext context, {
    required Widget child,
    required double radius,
    EdgeInsetsGeometry? padding,
    GlassSurfaceRole role = GlassSurfaceRole.control,
  }) {
    // Stay linked to the app's liquid-glass setting, but avoid the live video
    // backdrop path: the latter mirrors moving frames inside the glass and is
    // the source of both the odd refraction and extra raster work.
    return GlassSurface(
      role: role,
      radius: radius,
      padding: padding,
      liveBackdrop: false,
      disablePlatformViewBackdrop: true,
      child: child,
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
                child: MpvOhosPlayer(
                  key: controller.ohosPlayerWidgetKey,
                  url: url,
                  revision: revision,
                  sessionGeneration: controller.ohosPlaybackSessionGeneration,
                  requestedPlaybackProfile:
                      AppSettingsController.instance.ohosPlaybackProfile.value,
                  headers: controller.playHeaders,
                  onError: controller.mediaError,
                  onControllerReady: controller.attachOhosVideoController,
                  onControllerDisposed: controller.detachOhosVideoController,
                  onGenerationValueChanged:
                      controller.updateOhosVideoStateForGeneration,
                  onTelemetry: controller.updateOhosTelemetryForGeneration,
                  onFirstFrame: controller.updateOhosFirstFrameForGeneration,
                  onPlaybackProfileChanged:
                      controller.updateOhosPlaybackProfileDecision,
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
              if (controller.ohosPlaybackStarted.value &&
                  controller.ohosBuffering.value &&
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

  Widget buildUserProfile(
    BuildContext context, {
    bool useStaticSurface = false,
    bool showDividers = true,
  }) {
    final content = Container(
      decoration: showDividers
          ? BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.grey.withAlpha(25),
                ),
                bottom: BorderSide(
                  color: Colors.grey.withAlpha(25),
                ),
              ),
            )
          : null,
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
    if (useStaticSurface) {
      return _buildStaticGlassPanel(
        context,
        radius: 16,
        role: GlassSurfaceRole.content,
        child: content,
      );
    }
    return _buildStaticGlassPanel(context, radius: 0, child: content);
  }

  Widget buildBottomActions(BuildContext context) {
    return Obx(() {
      final glassOff =
          AppSettingsController.instance.glassMode.value == AppGlassMode.off;
      Widget action(Widget child) => Expanded(
            child: Padding(
              padding: glassOff
                  ? const EdgeInsets.symmetric(horizontal: 4)
                  : EdgeInsets.zero,
              child: child,
            ),
          );
      final content = Container(
        // In the non-glass mode each action is its own surface. Keep the
        // navigation background flat so the surfaces do not merge into one
        // bordered strip or leave a distracting divider above it.
        color: glassOff ? Theme.of(context).colorScheme.surface : null,
        decoration: glassOff
            ? null
            : BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Colors.grey.withAlpha(25),
                  ),
                ),
              ),
        padding: glassOff
            ? EdgeInsets.fromLTRB(4, 8, 4, _bottomActionInset(context) + 8)
            : EdgeInsets.only(bottom: _bottomActionInset(context)),
        child: Row(
          children: [
            action(
              Obx(
                () => controller.followed.value
                    ? _buildGlassActionButton(
                        context,
                        label: "取消关注",
                        icon: Remix.heart_fill,
                        onPressed: controller.removeFollowUser,
                      )
                    : _buildGlassActionButton(
                        context,
                        label: "关注",
                        icon: Remix.heart_line,
                        onPressed: controller.followUser,
                      ),
              ),
            ),
            action(
              _buildGlassActionButton(
                context,
                label: "刷新",
                icon: Remix.refresh_line,
                onPressed: controller.refreshRoom,
              ),
            ),
            action(
              _buildGlassActionButton(
                context,
                label: "分享",
                icon: Remix.share_line,
                onPressed: controller.share,
              ),
            ),
          ],
        ),
      );
      if (glassOff) {
        return content;
      }
      return _buildStaticGlassPanel(
        context,
        radius: 0,
        role: GlassSurfaceRole.navigation,
        child: content,
      );
    });
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
      String tabLabel(String key) {
        switch (key) {
          case "chat":
            return "聊天";
          case "super_chat":
            return controller.superChats.isNotEmpty
                ? "${controller.site.id == Constant.kHuya ? "头条" : "SC"}(${controller.superChats.length})"
                : controller.site.id == Constant.kHuya
                    ? "头条"
                    : "SC";
          case "follow":
            return "关注";
          case "contribution_rank":
            return controller.site.id == Constant.kDouyu ? "亲密榜" : "贡献榜";
          case "event_flow":
            return controller.liveEventFlows.isNotEmpty
                ? "动态(${controller.liveEventFlows.length})"
                : "动态";
          case "settings":
            return "设置";
          default:
            return key;
        }
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
              Builder(
                builder: (context) {
                  final tabController = DefaultTabController.of(context);
                  return _buildLiveRoomTabBar(
                    context,
                    tabController,
                    keys.map(tabLabel).toList(growable: false),
                    keys,
                  );
                },
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

  Widget _buildLiveRoomTabBar(
    BuildContext context,
    TabController tabController,
    List<String> labels,
    List<String> keys,
  ) {
    return AnimatedBuilder(
      animation: tabController,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: tabController.index == i,
                      label: labels[i],
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () =>
                              _selectLiveRoomTab(tabController, keys, i),
                          borderRadius: BorderRadius.circular(18),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: tabController.index == i
                                  ? colors.primary.withAlpha(isDark ? 52 : 24)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _liveRoomTabIcon(
                                    keys[i],
                                    tabController.index == i,
                                  ),
                                  size: 18,
                                  color: tabController.index == i
                                      ? colors.onPrimaryContainer
                                      : colors.onSurfaceVariant,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  labels[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: tabController.index == i
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: tabController.index == i
                                        ? colors.onPrimaryContainer
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _selectLiveRoomTab(
    TabController tabController,
    List<String> keys,
    int index,
  ) {
    if (index < 0 || index >= keys.length) return;
    controller.liveRoomSelectedPanelKey.value = keys[index];
    if (tabController.index != index) tabController.animateTo(index);
  }

  IconData _liveRoomTabIcon(String key, bool active) {
    return switch (key) {
      'chat' => active ? Icons.chat_bubble : Icons.chat_bubble_outline,
      'super_chat' => active ? Icons.star : Icons.star_border,
      'follow' => active ? Icons.favorite : Icons.favorite_border,
      'contribution_rank' =>
        active ? Icons.leaderboard : Icons.leaderboard_outlined,
      'event_flow' => active ? Icons.bolt : Icons.bolt_outlined,
      'settings' => active ? Icons.settings : Icons.settings_outlined,
      _ => active ? Icons.circle : Icons.circle_outlined,
    };
  }

  Widget buildChatList() {
    return Builder(
      builder: (context) => Stack(
        children: [
          ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: RawScrollbar(
              controller: controller.scrollController,
              thumbVisibility: _isDesktop,
              thickness: 4,
              radius: const Radius.circular(4),
              mainAxisMargin: 8,
              crossAxisMargin: 6,
              child: ListView.separated(
                controller: controller.scrollController,
                reverse: false,
                separatorBuilder: (_, i) => SizedBox(
                  // *2与原来的EdgeInsets.symmetric(vertical: )做兼容
                  height: AppSettingsController.instance.chatTextGap.value * 2,
                ),
                padding: AppStyle.edgeInsetsA12.copyWith(right: 18),
                itemCount: controller.messages.length,
                itemBuilder: (_, i) {
                  var item = controller.messages[i];
                  return buildMessageItem(item);
                },
              ),
            ),
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
      ),
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
                onTap: () => showQuickAccess(
                  controller,
                  openDiagnostics: true,
                ),
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
        enableHoldPreview: true,
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
                showQuickAccess(controller, openDiagnostics: true);
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
        shrinkWrap: true,
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
        shrinkWrap: true,
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
