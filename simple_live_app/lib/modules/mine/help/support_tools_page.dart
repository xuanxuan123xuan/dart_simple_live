import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/mine/help/support_tools_controller.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

class SupportToolsPage extends GetView<SupportToolsController> {
  const SupportToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("日志与配置恢复")),
      body: ListView(
        padding: AppStyle.pagePadding(),
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
            child: Text("日志记录", style: Get.textTheme.titleSmall),
          ),
          SettingsCard(
            child: Obx(
              () => SettingsSwitch(
                value: AppSettingsController.instance.logEnable.value,
                title: "开启日志记录",
                subtitle: "复现问题前开启，完成后可将日志文件提供给开发者",
                onChanged: controller.setLogEnable,
              ),
            ),
          ),
          ListTile(
            contentPadding: AppStyle.edgeInsetsL12,
            title: Text("日志文件", style: Get.textTheme.titleSmall),
            trailing: TextButton.icon(
              onPressed: controller.cleanLog,
              icon: const Icon(Icons.clear_all),
              label: const Text("清空"),
            ),
          ),
          SettingsCard(
            child: Obx(() {
              if (controller.logFiles.isEmpty) {
                return const ListTile(
                  leading: Icon(Icons.description_outlined),
                  title: Text("暂无日志文件"),
                );
              }
              return Column(
                children: [
                  for (var index = 0;
                      index < controller.logFiles.length;
                      index++) ...[
                    _logItem(context, controller.logFiles[index]),
                    if (index != controller.logFiles.length - 1)
                      AppStyle.divider,
                  ],
                ],
              );
            }),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text("配置恢复", style: Get.textTheme.titleSmall),
          ),
          SettingsCard(
            child: ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text("重置配置"),
              subtitle: const Text("恢复默认设置和弹幕屏蔽配置，不删除账号、关注和观看记录"),
              trailing: const Icon(Icons.chevron_right),
              onTap: controller.resetDefaultConfig,
            ),
          ),
        ],
      ),
    );
  }

  Widget _logItem(BuildContext context, SupportLogFile item) {
    return ListTile(
      title: Text(item.name),
      subtitle: Text(Utils.parseFileSize(item.size)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!Platform.isLinux)
            Builder(
              builder: (buttonContext) => IconButton(
                tooltip: "分享日志",
                onPressed: () {
                  final box = buttonContext.findRenderObject() as RenderBox?;
                  controller.shareLogFile(
                    item,
                    sharePositionOrigin: box == null
                        ? null
                        : box.localToGlobal(Offset.zero) & box.size,
                  );
                },
                icon: const Icon(Icons.share_outlined),
              ),
            ),
          IconButton(
            tooltip: "保存日志",
            onPressed: () => controller.saveLogFile(item),
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
    );
  }
}
