import 'dart:io';

import 'package:flutter/material.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/services/background_playback_guide_service.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';

class BackgroundPlaybackGuidePage extends StatelessWidget {
  const BackgroundPlaybackGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('后台播放保活指南')),
      body: ListView(
        padding: AppStyle.pagePadding(),
        children: [
          const _IntroCard(),
          const SizedBox(height: 16),
          const _SectionTitle('通用设置'),
          SettingsCard(
            child: Column(
              children: [
                _ActionTile(
                  icon: Icons.battery_saver_outlined,
                  title: '电池优化',
                  subtitle: '允许 Simple Live 在后台继续运行',
                  action: 'openBatteryOptimization',
                ),
                const Divider(height: 1),
                _ActionTile(
                  icon: Icons.battery_alert_outlined,
                  title: '应用电池管理',
                  subtitle: '选择“不限制”或“允许后台活动”',
                  action: 'openAppBatteryManagement',
                ),
                const Divider(height: 1),
                _ActionTile(
                  icon: Icons.autorenew,
                  title: '自启动管理',
                  subtitle: '允许应用在后台自动恢复播放',
                  action: 'openAutostart',
                ),
                const Divider(height: 1),
                _ActionTile(
                  icon: Icons.notifications_none,
                  title: '通知权限',
                  subtitle: '允许后台播放通知显示控制按钮',
                  action: 'openNotifications',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('厂商设置建议'),
          const _VendorCard(
            title: '小米 / Redmi',
            steps: '设置 → 电池 → 应用电池保护 → Simple Live → 无限制\n'
                '设置 → 应用设置 → 授权管理 → 自启动管理 → 允许',
          ),
          const _VendorCard(
            title: 'OPPO / 真我',
            steps: '设置 → 电池 → 应用耗电管理 → Simple Live → 允许后台运行\n'
                '设置 → 应用 → 自启动 → 允许 Simple Live 自启动',
          ),
          const _VendorCard(
            title: 'vivo',
            steps: '设置 → 电池 → 后台耗电管理 → Simple Live → 允许后台高耗电\n'
                '设置 → 应用与权限 → 权限管理 → 自启动 → 允许',
          ),
          const _VendorCard(
            title: '华为',
            steps: '设置 → 应用和服务 → 应用启动管理 → Simple Live → 关闭自动管理并允许后台活动',
          ),
          const _VendorCard(
            title: '荣耀',
            steps: '设置 → 电池 → 应用启动管理 → Simple Live → 关闭自动管理并允许后台活动',
          ),
          const _VendorCard(
            title: '魅族',
            steps: '设置 → 应用管理 → Simple Live → 权限管理 → 后台运行\n'
                '设置 → 电量管理 → 待机耗电管理 → 允许',
          ),
          const _VendorCard(
            title: '三星 / 原生 Android',
            steps: '设置 → 应用 → Simple Live → 电池 → 不受限制\n'
                '设置 → 应用 → Simple Live → 通知 → 允许',
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Text(
              '不同系统版本的菜单名称可能不同。找不到对应选项时，使用上方按钮或在系统设置中搜索“电池优化”“自启动”和“通知”。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: Padding(
        padding: AppStyle.edgeInsetsA16,
        child: Text(
          '开启“允许后台继续播放”后，系统仍可能因为省电策略暂停应用。请同时允许后台活动、关闭电池优化，并保留后台播放通知。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.title, required this.steps});

  final String title;
  final String steps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SettingsCard(
        child: ExpansionTile(
          title: Text(title),
          childrenPadding: AppStyle.edgeInsetsH16.copyWith(bottom: 14),
          expandedAlignment: Alignment.centerLeft,
          children: [
            Text(steps, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String action;

  Future<void> _open(BuildContext context) async {
    final service = BackgroundPlaybackGuideService.instance;
    final opened = switch (action) {
      'openBatteryOptimization' => await service.openBatteryOptimization(),
      'openAppBatteryManagement' =>
        await service.openAppBatteryManagement(),
      'openAutostart' => await service.openAutostart(),
      'openNotifications' => await service.openNotifications(),
      _ => false,
    };
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('系统未提供该快捷入口，请按下方路径手动设置')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.open_in_new, size: 20),
      onTap: () => _open(context),
    );
  }
}

bool get supportsBackgroundPlaybackGuide => Platform.isAndroid;
