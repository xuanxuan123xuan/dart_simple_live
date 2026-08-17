import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/sync/advanced_connection/advanced_connection_controller.dart';
import 'package:simple_live_app/widgets/settings/settings_action.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';

class AdvancedConnectionPage extends GetView<AdvancedConnectionController> {
  const AdvancedConnectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("高级连接设置")),
      body: ListView(
        padding: AppStyle.pagePadding(),
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
            child: Text(
              "仅在使用自建同步服务或需要手动指定代理时修改。错误设置可能导致远程同步无法连接。",
              style: Get.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
          SettingsCard(
            child: Column(
              children: [
                GetBuilder<AdvancedConnectionController>(
                  builder: (controller) => SettingsAction(
                    title: "同步服务地址",
                    subtitle: controller.syncServerUrlSubtitle,
                    value: controller.syncServerUrlLabel,
                    onTap: controller.editSyncServerUrl,
                  ),
                ),
                AppStyle.divider,
                GetBuilder<AdvancedConnectionController>(
                  builder: (controller) => SettingsAction(
                    title: "同步代理地址",
                    subtitle: "留空自动检测本机代理；填写 direct 可强制直连",
                    value: controller.syncProxyUrl,
                    onTap: controller.editSyncProxyUrl,
                  ),
                ),
              ],
            ),
          ),
          AppStyle.vGap12,
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await Utils.showAlertDialog(
                "将同步服务恢复为默认地址，并恢复自动检测代理。",
                title: "恢复默认连接设置",
                confirm: "恢复默认",
              );
              if (confirmed) await controller.reset();
            },
            icon: const Icon(Icons.restart_alt),
            label: const Text("恢复默认连接设置"),
          ),
        ],
      ),
    );
  }
}
