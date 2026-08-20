import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("设置")),
      body: ListView(
        padding: AppStyle.pagePadding(),
        children: [
          _sectionTitle("界面"),
          SettingsCard(
            child: Column(
              children: [
                _entry(
                  icon: Remix.moon_line,
                  title: "外观设置",
                  subtitle: "主题、动态取色与主题颜色",
                  route: RoutePath.kAppstyleSetting,
                ),
                AppStyle.divider,
                _entry(
                  icon: Remix.home_2_line,
                  title: "主页设置",
                  subtitle: "首页栏目、平台和标签顺序",
                  route: RoutePath.kSettingsIndexed,
                ),
                AppStyle.divider,
                _entry(
                  icon: Icons.tune,
                  title: "播放页设置",
                  subtitle: "直播间标签、快捷入口和页面显示项",
                  route: RoutePath.kSettingsPlaybackPage,
                ),
              ],
            ),
          ),
          _sectionTitle("观看体验", top: 24),
          SettingsCard(
            child: Column(
              children: [
                _entry(
                  icon: Remix.play_circle_line,
                  title: "直播设置",
                  subtitle: "画质、播放行为、网络与小窗播放",
                  route: RoutePath.kSettingsPlay,
                ),
                AppStyle.divider,
                _entry(
                  icon: Remix.layout_grid_line,
                  title: "多开设置",
                  subtitle: "布局、声音和性能策略",
                  route: RoutePath.kSettingsMultiRoom,
                ),
                AppStyle.divider,
                _entry(
                  icon: Remix.text,
                  title: "弹幕设置",
                  subtitle: "显示样式、屏蔽规则与高级过滤",
                  route: RoutePath.kSettingsDanmu,
                ),
                AppStyle.divider,
                _entry(
                  icon: Remix.heart_line,
                  title: "关注设置",
                  subtitle: "自动刷新、开播通知和列表显示",
                  route: RoutePath.kSettingsFollow,
                ),
              ],
            ),
          ),
          _sectionTitle("系统与高级", top: 24),
          SettingsCard(
            child: Column(
              children: [
                _entry(
                  icon: Remix.timer_2_line,
                  title: "定时关闭",
                  subtitle: "设置自动关闭时间",
                  route: RoutePath.kSettingsAutoExit,
                ),
                AppStyle.divider,
                _entry(
                  icon: Remix.settings_4_line,
                  title: "高级设置",
                  subtitle: "桌面窗口和播放器高级参数",
                  route: RoutePath.kSettingsOther,
                ),
              ],
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

  Widget _entry({
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Get.toNamed(route),
    );
  }
}
