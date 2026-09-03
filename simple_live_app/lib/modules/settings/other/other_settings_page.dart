import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/ohos_playback_profile_policy.dart';
import 'package:simple_live_app/modules/settings/other/other_settings_controller.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';
import 'package:simple_live_app/services/ohos_playback_capabilities_service.dart';
import 'package:simple_live_app/widgets/settings/settings_action.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_menu.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';
import 'package:url_launcher/url_launcher_string.dart';

class OtherSettingsPage extends GetView<OtherSettingsController> {
  const OtherSettingsPage({super.key});

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("高级设置")),
      body: ListView(
        padding: AppStyle.pagePadding(),
        children: [
          if (_isDesktop) ...[
            _sectionTitle("桌面窗口"),
            SettingsCard(
              child: Obx(
                () => SettingsSwitch(
                  value: AppSettingsController
                      .instance.rememberWindowPlacement.value,
                  title: "记住窗口大小和位置",
                  subtitle: "开启后恢复上次普通窗口位置和最大化状态",
                  onChanged:
                      AppSettingsController.instance.setRememberWindowPlacement,
                ),
              ),
            ),
          ],
          if (!Utils.isOhos) ...[
            _sectionTitle("播放器高级设置", top: _isDesktop ? 24 : 0),
            Padding(
              padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
              child: Text.rich(
                TextSpan(
                  text: "请勿随意修改以下设置，除非你知道自己在做什么。修改前请先查阅",
                  children: [
                    WidgetSpan(
                      child: GestureDetector(
                        onTap: () => launchUrlString(
                          "https://mpv.io/manual/stable/#video-output-drivers",
                        ),
                        child: const Text(
                          " MPV 文档",
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            SettingsCard(
              child: Column(
                children: [
                  Obx(
                    () => SettingsMenu(
                      title: "mpv 性能档位",
                      subtitle: "流畅适合核显/低功耗，均衡为默认，画质适合高性能显卡",
                      value: AppSettingsController.instance.mpvProfile.value,
                      valueMap: MpvOptionsService.profileLabels,
                      onChanged: AppSettingsController.instance.setMpvProfile,
                    ),
                  ),
                  AppStyle.divider,
                  Obx(
                    () => SettingsMenu(
                      title: "直播延迟档位",
                      subtitle: "自动按协议使用不同缓冲策略，重开直播间后生效",
                      value: AppSettingsController
                          .instance.mpvLiveLatencyMode.value,
                      valueMap: MpvOptionsService.liveLatencyModeLabels,
                      onChanged:
                          AppSettingsController.instance.setMpvLiveLatencyMode,
                    ),
                  ),
                  AppStyle.divider,
                  Obx(
                    () => SettingsSwitch(
                      value: AppSettingsController
                          .instance.customPlayerOutput.value,
                      title: "自定义输出驱动与硬件加速",
                      onChanged:
                          AppSettingsController.instance.setCustomPlayerOutput,
                    ),
                  ),
                  AppStyle.divider,
                  GetBuilder<OtherSettingsController>(
                    builder: (controller) => SettingsAction(
                      title: "高级 mpv options",
                      subtitle: "每行一个 key=value，覆盖内置档位和可视化设置",
                      value: AppSettingsController
                              .instance.mpvAdvancedOptions.value.isEmpty
                          ? "未设置"
                          : "已设置",
                      onTap: controller.editMpvAdvancedOptions,
                    ),
                  ),
                  AppStyle.divider,
                  GetBuilder<OtherSettingsController>(
                    builder: (controller) => SettingsAction(
                      title: "导入 mpv.conf",
                      subtitle: "导入后复制到应用私有目录，覆盖同名 mpv option",
                      value: AppSettingsController
                              .instance.importedMpvConfPath.value.isEmpty
                          ? "未导入"
                          : "已导入",
                      onTap: controller.importMpvConf,
                    ),
                  ),
                  AppStyle.divider,
                  Obx(
                    () => SettingsMenu(
                      title: "视频输出驱动(--vo)",
                      value: AppSettingsController
                          .instance.videoOutputDriver.value,
                      valueMap: controller.videoOutputDrivers,
                      onChanged:
                          AppSettingsController.instance.setVideoOutputDriver,
                    ),
                  ),
                  AppStyle.divider,
                  Obx(
                    () => SettingsMenu(
                      title: "音频输出驱动(--ao)",
                      value: AppSettingsController
                          .instance.audioOutputDriver.value,
                      valueMap: controller.audioOutputDrivers,
                      onChanged:
                          AppSettingsController.instance.setAudioOutputDriver,
                    ),
                  ),
                  AppStyle.divider,
                  Obx(
                    () => SettingsMenu(
                      title: "硬件解码器(--hwdec)",
                      value: AppSettingsController
                          .instance.videoHardwareDecoder.value,
                      valueMap: controller.hardwareDecoder,
                      onChanged: AppSettingsController
                          .instance.setVideoHardwareDecoder,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!_isDesktop && Utils.isOhos) ...[
            _sectionTitle("播放缓冲策略"),
            SettingsCard(
              child: _OhosPlaybackProfileSection(
                controller: AppSettingsController.instance,
              ),
            ),
            _sectionTitle("播放器高级设置"),
            SettingsCard(
              child: Column(
                children: [
                  GetBuilder<OtherSettingsController>(
                    builder: (controller) => SettingsAction(
                      title: "高级 mpv options",
                      subtitle: "每行一个 key=value，覆盖内置档位和可视化设置，重开直播间后生效",
                      value: AppSettingsController
                              .instance.mpvAdvancedOptions.value.isEmpty
                          ? "未设置"
                          : "已设置",
                      onTap: controller.editMpvAdvancedOptions,
                    ),
                  ),
                  AppStyle.divider,
                  Obx(
                    () => SettingsMenu<String>(
                      title: "硬件解码器(--hwdec)",
                      subtitle: "auto 为 OHCodec 硬解，auto-copy 经 CPU 回拷，no 为软解",
                      value: _ohosHwdecUiValue(
                        AppSettingsController
                            .instance.videoHardwareDecoder.value,
                      ),
                      valueMap: controller.ohosHardwareDecoder,
                      onChanged: AppSettingsController
                          .instance.setVideoHardwareDecoder,
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

  String _ohosHwdecUiValue(String stored) {
    const known = {'auto', 'auto-copy', 'no'};
    final v = stored.trim();
    return known.contains(v) ? v : 'auto';
  }
  Widget _sectionTitle(String title, {double top = 0}) {
    return Padding(
      padding: AppStyle.edgeInsetsA12.copyWith(top: top),
      child: Text(title, style: Get.textTheme.titleSmall),
    );
  }
}

class _OhosPlaybackProfileSection extends StatefulWidget {
  const _OhosPlaybackProfileSection({required this.controller});

  final AppSettingsController controller;

  @override
  State<_OhosPlaybackProfileSection> createState() =>
      _OhosPlaybackProfileSectionState();
}

class _OhosPlaybackProfileSectionState
    extends State<_OhosPlaybackProfileSection> {
  late final Future<OhosPlaybackCapabilities> _capabilities =
      OhosPlaybackCapabilitiesService.instance.getCapabilities(refresh: true);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OhosPlaybackCapabilities>(
      future: _capabilities,
      builder: (context, snapshot) {
        // Do not expose a preference that the native bridge cannot actually
        // honor. Capability failures are intentionally fail-closed.
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.data?.lowLatencyExperimentalSupported != true) {
          return const SizedBox.shrink();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [            Obx(
              () => SettingsMenu<String>(
                title: "播放缓冲策略",
                subtitle: _subtitleFor(
                  widget.controller.ohosPlaybackProfile.value,
                ),
                value: widget.controller.ohosPlaybackProfile.value,
                valueMap: const {
                  AppSettingsController.kOhosPlaybackProfileStable: "稳定",
                  AppSettingsController
                      .kOhosPlaybackProfileLowLatencyExperimental: "低延迟（实验）",
                },
                onChanged: widget.controller.setOhosPlaybackProfile,
              ),
            ),
            Padding(
              padding: AppStyle.edgeInsetsH16.copyWith(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "低延迟（实验）仅对 HTTP-FLV 生效，可能增加首帧失败、缓冲和耗电；异常时会在当前播放会话内回退稳定档。实际生效档位以当前播放会话为准。",
                  style: Get.textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
            // GetX requires every Obx builder to read at least one observable.
            // With no live room session there is nothing reactive to read,
            // which made GetX throw its "improper use" error box here.
            if (!Get.isRegistered<LiveRoomController>())
              Padding(
                padding: AppStyle.edgeInsetsH16.copyWith(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "本次会话实际生效：暂无活动播放会话",
                    style: Get.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ),
              )
            else
              Obx(
                () => Padding(
                  padding: AppStyle.edgeInsetsH16.copyWith(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _effectiveProfileLabel(),
                      style: Get.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _subtitleFor(String profile) {
    if (profile ==
        AppSettingsController.kOhosPlaybackProfileLowLatencyExperimental) {
      return "当前偏好：低延迟（实验）；仅 HTTP-FLV 生效，异常时自动回退稳定档";
    }
    return "当前偏好：稳定；优先保证起播和连续播放";
  }

  String _effectiveProfileLabel() {
    if (!Get.isRegistered<LiveRoomController>()) {
      return "本次会话实际生效：暂无活动播放会话";
    }
    final roomController = Get.find<LiveRoomController>();
    final status = roomController.ohosPlaybackProfileStatus.value;
    final reason = roomController.ohosPlaybackProfileReason.value;
    if (reason == OhosPlaybackProfileDecisionReason.sessionFallback.name) {
      return "本次会话实际生效：稳定（实验档已回退）";
    }
    return "本次会话实际生效：$status";
  }
}

