import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/sync/profile_backup/profile_backup_controller.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';

class ProfileBackupPage extends GetView<ProfileBackupController> {
  const ProfileBackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("配置包"),
      ),
      body: ListView(
        padding: AppStyle.pagePadding(),
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
            child: Text(
              "导出内容",
              style: Get.textTheme.titleSmall,
            ),
          ),
          _buildExportCard(),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text(
              "导入内容",
              style: Get.textTheme.titleSmall,
            ),
          ),
          _buildImportCard(),
        ],
      ),
    );
  }

  Widget _buildExportCard() {
    return SettingsCard(
      child: Column(
        children: [
          _buildOptionTile(
            icon: Icons.settings_outlined,
            title: "设置",
            subtitle: "播放、显示、刷新等偏好设置",
            value: controller.exportSettings,
            onChanged: (value) => controller.exportSettings.value = value,
          ),
          AppStyle.divider,
          _buildOptionTile(
            icon: Icons.people_outline,
            title: "关注列表与标签",
            subtitle: "关注主播、标签和特别关注标记",
            value: controller.exportFollows,
            onChanged: (value) => controller.exportFollows.value = value,
          ),
          AppStyle.divider,
          _buildOptionTile(
            icon: Icons.history,
            title: "观看历史",
            subtitle: "本机直播间观看记录",
            value: controller.exportHistories,
            onChanged: (value) => controller.exportHistories.value = value,
          ),
          AppStyle.divider,
          _buildOptionTile(
            icon: Icons.shield_outlined,
            title: "弹幕屏蔽规则",
            subtitle: "关键词和用户屏蔽规则",
            value: controller.exportShields,
            onChanged: (value) => controller.exportShields.value = value,
          ),
          AppStyle.divider,
          _buildOptionTile(
            icon: Icons.bookmarks_outlined,
            title: "屏蔽预设",
            subtitle: "已保存的屏蔽规则预设",
            value: controller.exportShieldPresets,
            onChanged: (value) => controller.exportShieldPresets.value = value,
          ),
          AppStyle.divider,
          _buildOptionTile(
            icon: Icons.lock_outline,
            title: "账号登录信息",
            subtitle: "包含平台 Cookie，默认不导出",
            value: controller.exportAccounts,
            onChanged: (value) => controller.exportAccounts.value = value,
          ),
          AppStyle.divider,
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: controller.exportProfile,
                icon: const Icon(Remix.download_2_line),
                label: const Text("导出配置包"),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportCard() {
    return SettingsCard(
      child: Column(
        children: [
          _buildOptionTile(
            icon: Icons.settings_outlined,
            title: "设置",
            subtitle: "导入包内播放、显示、刷新等设置",
            value: controller.importSettings,
            onChanged: (value) => controller.importSettings.value = value,
          ),
          AppStyle.divider,
          _buildOptionTile(
            icon: Icons.people_outline,
            title: "关注列表与标签",
            subtitle: "导入关注主播、标签和特别关注标记",
            value: controller.importFollows,
            onChanged: (value) => controller.importFollows.value = value,
          ),
          AppStyle.divider,
          _buildOptionTile(
            icon: Icons.history,
            title: "观看历史",
            subtitle: "导入包内观看记录",
            value: controller.importHistories,
            onChanged: (value) => controller.importHistories.value = value,
          ),
          AppStyle.divider,
          _buildOptionTile(
            icon: Icons.shield_outlined,
            title: "弹幕屏蔽规则",
            subtitle: "导入关键词和用户屏蔽规则",
            value: controller.importShields,
            onChanged: (value) => controller.importShields.value = value,
          ),
          AppStyle.divider,
          _buildOptionTile(
            icon: Icons.bookmarks_outlined,
            title: "屏蔽预设",
            subtitle: "导入包内屏蔽规则预设",
            value: controller.importShieldPresets,
            onChanged: (value) => controller.importShieldPresets.value = value,
          ),
          AppStyle.divider,
          _buildOptionTile(
            icon: Icons.lock_outline,
            title: "账号登录信息",
            subtitle: "恢复包内平台账号 Cookie，默认不导入",
            value: controller.importAccounts,
            onChanged: (value) => controller.importAccounts.value = value,
          ),
          AppStyle.divider,
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: controller.importProfile,
                icon: const Icon(Remix.upload_2_line),
                label: const Text("导入配置包"),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required RxBool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Obx(
      () => CheckboxListTile(
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        value: value.value,
        onChanged: (checked) => onChanged(checked ?? false),
        controlAffinity: ListTileControlAffinity.trailing,
      ),
    );
  }
}
