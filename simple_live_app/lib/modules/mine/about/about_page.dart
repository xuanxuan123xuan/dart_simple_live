import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _showStatement() async {
    final text = await rootBundle.loadString("assets/statement.txt");
    await Utils.showMessageDialog(
      text,
      title: "免责声明",
      confirm: "关闭",
      selectable: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("关于 Simple Live")),
      body: ListView(
        padding: AppStyle.pagePadding(),
        children: [
          Padding(
            padding: AppStyle.edgeInsetsV24,
            child: Column(
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 80,
                  height: 80,
                ),
                AppStyle.vGap12,
                Text(
                  "Simple Live",
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                AppStyle.vGap4,
                const Text("简简单单看直播"),
                AppStyle.vGap4,
                Text(
                  "版本 ${Utils.packageInfo.version}",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          SettingsCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Remix.error_warning_line),
                  title: const Text("免责声明"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showStatement,
                ),
                AppStyle.divider,
                ListTile(
                  leading: const Icon(Remix.refresh_line),
                  title: const Text("检查更新"),
                  subtitle: const Text("切换 stable / dev，查看当前平台可用安装包"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Get.toNamed(RoutePath.kAppUpdate);
                  },
                ),
                AppStyle.divider,
                ListTile(
                  leading: const Icon(Remix.github_line),
                  title: const Text("开源主页"),
                  subtitle: const Text("查看源代码、问题反馈与发行说明"),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () {
                    launchUrlString(
                      "https://github.com/xuanxuan123xuan/dart_simple_live",
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
