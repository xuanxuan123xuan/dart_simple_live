import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/settings/other/other_settings_controller.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';
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
          if (!_isDesktop && Utils.isOhos)
            const SettingsCard(
              child: ListTile(
                title: Text("当前平台暂无可用的高级设置"),
                leading: Icon(Icons.info_outline),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {double top = 0}) {
    return Padding(
      padding: AppStyle.edgeInsetsA12.copyWith(top: top),
      child: Text(title, style: Get.textTheme.titleSmall),
    );
  }
}
