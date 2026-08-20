import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/generated/app_update_channel.g.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("帮助与排障")),
      body: ListView(
        padding: AppStyle.pagePadding(),
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
            child: Text("问题排查", style: Get.textTheme.titleSmall),
          ),
          SettingsCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Remix.question_line),
                  title: const Text("常见播放问题"),
                  subtitle: const Text("播放失败、卡顿、无声音等问题的处理建议"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Utils.showMessageDialog(
                    "遇到播放失败或卡顿时，可以先切换清晰度和播放线路，再尝试刷新直播间。"
                    "如果问题仍然存在，请打开直播间“设置 → 网络诊断与播放信息”。",
                    title: "常见播放问题",
                  ),
                ),
                AppStyle.divider,
                ListTile(
                  leading: const Icon(Remix.route_line),
                  title: const Text("搜索与链接引导"),
                  subtitle: const Text("直接进入搜索页，高亮搜索框并演示链接解析"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Get.toNamed(
                      RoutePath.kSearch,
                      arguments: const {"guide": "search"},
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text("日志与恢复", style: Get.textTheme.titleSmall),
          ),
          SettingsCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Remix.file_list_3_line),
                  title: const Text("当前运行日志"),
                  subtitle: const Text("查看、分享或清空本次运行产生的调试信息"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Get.toNamed(RoutePath.kDebugLog),
                ),
                AppStyle.divider,
                ListTile(
                  leading: const Icon(Remix.tools_line),
                  title: const Text("日志记录与导出"),
                  subtitle: const Text("开启持久日志，查看、分享或清空日志文件"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Get.toNamed(RoutePath.kSupportTools),
                ),
                AppStyle.divider,
                ListTile(
                  leading: const Icon(Remix.restart_line),
                  title: const Text("重置配置"),
                  subtitle: const Text("将应用配置恢复为默认值"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Get.toNamed(RoutePath.kSupportTools),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text("版本与平台", style: Get.textTheme.titleSmall),
          ),
          SettingsCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Remix.information_line),
                  title: const Text("应用版本"),
                  trailing: Text(
                    "${Utils.packageInfo.version} / ${GeneratedAppUpdateChannel.channel}",
                  ),
                ),
                AppStyle.divider,
                ListTile(
                  leading: const Icon(Remix.device_line),
                  title: const Text("运行平台"),
                  subtitle: Text(Platform.operatingSystemVersion),
                  trailing: Text(Platform.operatingSystem),
                ),
                AppStyle.divider,
                const ListTile(
                  leading: Icon(Remix.code_line),
                  title: Text("构建模式"),
                  trailing: Text(kReleaseMode ? "正式版" : "调试版"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
