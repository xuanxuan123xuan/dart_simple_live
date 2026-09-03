import 'dart:io';

import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/ohos_pip_service.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_menu.dart';
import 'package:simple_live_app/widgets/settings/settings_number.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

class PlaySettingsPage extends GetView<AppSettingsController> {
  const PlaySettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("播放与网络"),
      ),
      body: ListView(
        padding: AppStyle.pagePadding(),
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
            child: Text(
              "播放器",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!Utils.isOhos)
                  Obx(
                    () => SettingsSwitch(
                      title: "硬件解码",
                      value: controller.hardwareDecode.value,
                      subtitle: "播放失败可尝试关闭此选项",
                      onChanged: (e) {
                        controller.setHardwareDecode(e);
                      },
                    ),
                  ),
                if (Platform.isIOS) AppStyle.divider,
                if (Platform.isIOS)
                  Obx(
                    () => SettingsSwitch(
                      title: "原画省电优化",
                      subtitle: "限制渲染纹理不超过屏幕实际像素，不降低直播源清晰度；异常时可关闭",
                      value: controller.iosOriginalQualityPowerSaving.value,
                      onChanged: controller.setIosOriginalQualityPowerSaving,
                    ),
                  ),
                if (Platform.isAndroid) AppStyle.divider,
                Obx(
                  () => Visibility(
                    visible: Platform.isAndroid,
                    child: SettingsSwitch(
                      title: "兼容模式",
                      subtitle: "若播放卡顿可尝试打开此选项",
                      value: controller.playerCompatMode.value,
                      onChanged: (e) {
                        controller.setPlayerCompatMode(e);
                      },
                    ),
                  ),
                ),
                // AppStyle.divider,
                // Obx(
                //   () => SettingsNumber(
                //     title: "缓冲区大小",
                //     subtitle: "若播放卡顿可尝试调高此选项",
                //     value: controller.playerBufferSize.value,
                //     min: 32,
                //     max: 1024,
                //     step: 4,
                //     unit: "MB",
                //     onChanged: (e) {
                //       controller.setPlayerBufferSize(e);
                //     },
                //   ),
                // ),
                if (!Utils.isOhos) AppStyle.divider,
                Obx(
                  () => SettingsMenu<int>(
                    title: "画面尺寸",
                    value: controller.scaleMode.value,
                    valueMap: const {
                      0: "适应",
                      1: "拉伸",
                      2: "铺满",
                      3: "16:9",
                      4: "4:3",
                    },
                    onChanged: (e) {
                      controller.setScaleMode(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "使用HTTPS链接",
                    subtitle: "将http链接替换为https",
                    value: controller.playerForceHttps.value,
                    onChanged: (e) {
                      controller.setPlayerForceHttps(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "滑动调节音量/亮度",
                    subtitle: "播放页左右两侧上下滑动调节亮度和音量",
                    value: controller.playerGestureControlEnable.value,
                    onChanged: (e) {
                      controller.setPlayerGestureControlEnable(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "允许后台继续播放",
                    subtitle: "移动端仍可能被系统省电策略关闭，返回前台时会尽量自动恢复",
                    value: controller.allowBackgroundPlayback.value,
                    onChanged: (e) {
                      controller.setAllowBackgroundPlayback(e);
                    },
                  ),
                ),
                if (Utils.isOhos) ...[
                  AppStyle.divider,
                  Obx(
                    () => SettingsSwitch(
                      title: "网络波动时自动降低清晰度",
                      subtitle: "仅在多次独立缓冲后降一档，切换房间后重新判断",
                      value: controller.ohosAutoQualityDegrade.value,
                      onChanged: controller.setOhosAutoQualityDegrade,
                    ),
                  ),
                  AppStyle.divider,
                  Obx(
                    () => SettingsSwitch(
                      title: "网络波动提示",
                      subtitle: "持续缓冲时检测当前播放端点并显示结果",
                      value: controller.ohosNetworkFluctuationNotice.value,
                      onChanged: controller.setOhosNetworkFluctuationNotice,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text(
              "直播间",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(
                  () => SettingsSwitch(
                    title: "进入直播间自动全屏",
                    value: controller.autoFullScreen.value,
                    onChanged: (e) {
                      controller.setAutoFullScreen(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "关播后自动换下一个直播间",
                    subtitle: "当前房间确认已下播后，自动切到关注列表里下一个正在直播的房间",
                    value: controller.autoSwitchNextOnLiveEnd.value,
                    onChanged: (e) {
                      controller.setAutoSwitchNextOnLiveEnd(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "播放失败后自动换下一个直播间",
                    subtitle: "当前房间重试和线路切换都失败后，自动切到下一个正在直播的房间",
                    value: controller.autoSwitchNextOnPlaybackFailure.value,
                    onChanged: (e) {
                      controller.setAutoSwitchNextOnPlaybackFailure(e);
                    },
                  ),
                ),
                _PipSettingsSection(controller: controller),
                Obx(
                  () => SettingsSwitch(
                    title: "播放器中显示SC",
                    value: controller.playershowSuperChat.value,
                    onChanged: (e) {
                      controller.setPlayerShowSuperChat(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "显示“复制播放直链”",
                    subtitle: "开启后在直播间更多功能中显示；复制当前实际清晰度和线路",
                    value: controller.playerShowPlayUrl.value,
                    onChanged: controller.setPlayerShowPlayUrl,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text(
              "清晰度",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Column(
              children: [
                Obx(
                  () => SettingsMenu<int>(
                    title: "默认清晰度",
                    value: controller.qualityLevel.value,
                    valueMap: const {
                      0: "最低",
                      1: "中等",
                      2: "最高",
                    },
                    onChanged: (e) {
                      controller.setQualityLevel(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsMenu<int>(
                    title: "数据网络清晰度",
                    value: controller.qualityLevelCellular.value,
                    valueMap: const {
                      0: "最低",
                      1: "中等",
                      2: "最高",
                    },
                    onChanged: (e) {
                      controller.setQualityLevelCellular(e);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text(
              "聊天区",
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
                    value: controller.chatTextSize.value.toInt(),
                    min: 8,
                    max: 36,
                    onChanged: (e) {
                      controller.setChatTextSize(e.toDouble());
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsNumber(
                    title: "上下间隔",
                    value: controller.chatTextGap.value.toInt(),
                    min: 0,
                    max: 12,
                    onChanged: (e) {
                      controller.setChatTextGap(e.toDouble());
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "气泡样式",
                    value: controller.chatBubbleStyle.value,
                    onChanged: (e) {
                      controller.setChatBubbleStyle(e);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PipSettingsSection extends StatefulWidget {
  const _PipSettingsSection({required this.controller});

  final AppSettingsController controller;

  @override
  State<_PipSettingsSection> createState() => _PipSettingsSectionState();
}

class _PipSettingsSectionState extends State<_PipSettingsSection> {
  late final Future<PipCapabilities> _capabilities = _loadCapabilities();

  Future<PipCapabilities> _loadCapabilities() async {
    if (Platform.isAndroid) {
      try {
        return await Floating().isPipAvailable
            ? PipCapabilities.supported
            : PipCapabilities.unsupported;
      } catch (_) {
        return PipCapabilities.unsupported;
      }
    }
    if (Utils.isOhos) {
      return OhosPipService.instance.getCapabilities(refresh: true);
    }
    return PipCapabilities.unsupported;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PipCapabilities>(
      future: _capabilities,
      builder: (context, snapshot) {
        final capabilities = snapshot.data ?? PipCapabilities.unsupported;
        final showHideDanmaku = capabilities.pipCanHideDanmaku;
        final showAutoOnLeave = capabilities.pipAutoOnLeaveSupported;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppStyle.divider,
            if (showHideDanmaku)
              Obx(
                () => SettingsSwitch(
                  title: "进入小窗隐藏弹幕",
                  value: widget.controller.pipHideDanmu.value,
                  onChanged: widget.controller.setPIPHideDanmu,
                ),
              ),
            if (showHideDanmaku && showAutoOnLeave) AppStyle.divider,
            if (showAutoOnLeave)
              Obx(
                () => SettingsSwitch(
                  title: "退出时自动小窗",
                  subtitle: "按 Home 键或系统手势退到后台时进入小窗；应用内返回仍回到主页",
                  value: widget.controller.autoPipOnExit.value,
                  onChanged: widget.controller.setAutoPipOnExit,
                ),
              ),
            if (showHideDanmaku || showAutoOnLeave) AppStyle.divider,
          ],
        );
      },
    );
  }
}
