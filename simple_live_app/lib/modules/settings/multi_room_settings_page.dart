import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/services/desktop_multi_window_service.dart';
import 'package:simple_live_app/widgets/settings/settings_action.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_number.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

class MultiRoomSettingsPage extends GetView<AppSettingsController> {
  const MultiRoomSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isWindows || Platform.isMacOS;
    return Scaffold(
      appBar: AppBar(
        title: const Text("多开设置"),
      ),
      body: ListView(
        padding: AppStyle.pagePadding(),
        children: [
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDesktop)
                  Obx(
                    () => SettingsSwitch(
                      title: "默认收起聊天区",
                      subtitle: "从关注页多开时，独立直播窗口默认只保留展开按钮",
                      value: controller.multiRoomCollapseChat.value,
                      onChanged: controller.setMultiRoomCollapseChat,
                    ),
                  ),
                if (isDesktop) AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "显示聊天区面板",
                    subtitle: "2个直播时画面左移，右侧显示聊天区；"
                        "3个直播时用空白格显示。顶部可切换来源直播间。",
                    value: controller.multiRoomShowChatPanel.value,
                    onChanged: controller.setMultiRoomShowChatPanel,
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "低内存自动降级",
                    subtitle: "进程内存较高时，自动暂停非活跃格子弹幕"
                        "（4路及以上时额外降低画质），内存回落自动恢复",
                    value: controller.multiRoomLowMemoryDegrade.value,
                    onChanged: controller.setMultiRoomLowMemoryDegrade,
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "仅允许一路声音",
                    subtitle: "取消某格静音时自动静音其他直播间；关闭后允许多路混音",
                    value: controller.multiRoomSingleAudio.value,
                    onChanged: controller.setMultiRoomSingleAudio,
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "自动调节多开画质",
                    subtitle: "根据缓冲、内存和设备解码负载优先保障主画面",
                    value: controller.multiRoomAdaptiveQuality.value,
                    onChanged: controller.setMultiRoomAdaptiveQuality,
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsNumber(
                    title: "布局间距",
                    subtitle: isDesktop
                        ? "影响独立窗口铺排、桌面同屏多开和 TV 多屏同播"
                        : "多开同屏时每格画面之间的间距",
                    value: controller.effectiveMultiRoomGap,
                    min: AppSettingsController.kMultiRoomMinGap,
                    max: AppSettingsController.kMultiRoomMaxGap,
                    unit: "px",
                    onChanged: controller.setMultiRoomGap,
                  ),
                ),
              ],
            ),
          ),
          if (isDesktop) ...[
            AppStyle.vGap12,
            const SettingsCard(
              child: SettingsAction(
                title: "关闭所有多开窗口",
                subtitle: "关闭本次从关注页多开启动的独立直播窗口",
                leading: Icon(Icons.close),
                onTap: DesktopMultiWindowService.closeOpenedRooms,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
