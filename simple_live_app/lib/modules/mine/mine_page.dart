import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/platform_utils.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/cache_service.dart';
import 'package:simple_live_app/services/signalr_service.dart';
import 'package:url_launcher/url_launcher_string.dart';

class MinePage extends StatefulWidget {
  const MinePage({Key? key}) : super(key: key);

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  String _cacheSize = "计算中...";
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshCacheSize());
  }

  Future<void> _refreshCacheSize() async {
    try {
      final size = await CacheService.getCacheSize();
      if (mounted) {
        setState(() => _cacheSize = CacheService.formatBytes(size));
      }
    } catch (e) {
      Log.logPrint("读取缓存大小失败: $e");
      if (mounted) {
        setState(() => _cacheSize = "未知");
      }
    }
  }

  Future<void> _clearCache() async {
    if (_isClearingCache) {
      return;
    }

    final confirmed = await Utils.showAlertDialog(
      "将清理临时文件和图片缓存，不会删除账号、关注、观看记录或设置。",
      title: "清理缓存",
      confirm: "清理",
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _isClearingCache = true);
    SmartDialog.showLoading(msg: "正在清理缓存...");
    try {
      final result = await CacheService.clearCache();
      await _refreshCacheSize();
      if (result.failedEntries == 0) {
        SmartDialog.showToast(
          "已清理 ${CacheService.formatBytes(result.clearedBytes)} 缓存",
        );
      } else {
        SmartDialog.showToast("缓存已清理，${result.failedEntries} 个占用中的文件未能删除");
      }
    } catch (e) {
      Log.logPrint("清理缓存失败: $e");
      SmartDialog.showToast("清理缓存失败");
      await _refreshCacheSize();
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
      if (mounted) {
        setState(() => _isClearingCache = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Get.isDarkMode
          ? SystemUiOverlayStyle.light.copyWith(
              systemNavigationBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              systemNavigationBarColor: Colors.transparent,
            ),
      child: SafeArea(
        child: ListView(
          padding: AppStyle.edgeInsetsA4,
          children: [
            AppStyle.vGap12,
            ListTile(
              leading: Image.asset(
                'assets/images/logo.png',
                width: 56,
                height: 56,
              ),
              title: const Text(
                "Simple Live",
                style: TextStyle(height: 1.0),
              ),
              subtitle: const Text("简简单单看直播"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Utils.showDialogSafe<dynamic>(
                  context: context,
                  builder: (_) => AboutDialog(
                    applicationIcon: Image.asset(
                      'assets/images/logo.png',
                      width: 48,
                      height: 48,
                    ),
                    applicationName: "Simple Live",
                    applicationVersion: "简简单单看直播",
                    applicationLegalese: "Ver ${Utils.packageInfo.version}",
                  ),
                );
              },
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            _buildCard(
              context,
              children: [
                ListTile(
                  leading: const Icon(Remix.history_line),
                  title: const Text("观看记录"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    AppNavigator.toHistory();
                  },
                ),
              ],
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            ListTile(
              leading: const Icon(Remix.account_circle_line),
              title: const Text("账号管理"),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
              onTap: () {
                Get.toNamed(RoutePath.kSettingsAccount);
              },
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            ListTile(
              leading: const Icon(Icons.devices),
              title: const Text("数据同步"),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
              onTap: () {
                Get.toNamed(RoutePath.kSync);
              },
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            ListTile(
              leading: const Icon(Remix.delete_bin_6_line),
              title: const Text("清理缓存"),
              subtitle: Text("当前占用 $_cacheSize"),
              trailing: _isClearingCache
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
              onTap: _isClearingCache ? null : _clearCache,
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            ListTile(
              leading: const Icon(Remix.link),
              title: const Text("链接解析"),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
              onTap: () {
                Get.toNamed(RoutePath.kTools);
              },
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            _buildCard(
              context,
              children: [
                ListTile(
                  leading: const Icon(Remix.moon_line),
                  title: const Text("外观设置"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kAppstyleSetting);
                  },
                ),
                ListTile(
                  leading: const Icon(Remix.home_2_line),
                  title: const Text("主页设置"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kSettingsIndexed);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text("播放页设置"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kSettingsPlaybackPage);
                  },
                ),
                ListTile(
                  leading: const Icon(Remix.play_circle_line),
                  title: const Text("直播设置"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kSettingsPlay);
                  },
                ),
                if (PlatformUtils.supportsInlineMultiRoomOf(context))
                  ListTile(
                    leading: const Icon(Remix.layout_grid_line),
                    title: const Text("多开设置"),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
                    onTap: () {
                      Get.toNamed(RoutePath.kSettingsMultiRoom);
                    },
                  ),
                ListTile(
                  leading: const Icon(Remix.text),
                  title: const Text("弹幕设置"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kSettingsDanmu);
                  },
                ),
                ListTile(
                  leading: const Icon(Remix.heart_line),
                  title: const Text("关注设置"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kSettingsFollow);
                  },
                ),
                ListTile(
                  leading: const Icon(Remix.timer_2_line),
                  title: const Text("定时关闭"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kSettingsAutoExit);
                  },
                ),
                ListTile(
                  leading: const Icon(Remix.apps_line),
                  title: const Text("其他设置"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Get.toNamed(RoutePath.kSettingsOther);
                  },
                ),
                if (kDebugMode)
                  ListTile(
                    leading: const Icon(Remix.apps_line),
                    title: const Text("测试"),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
                    onTap: () async {
                      SignalRService signalRService = SignalRService();
                      await signalRService.connect();
                      //Get.toNamed(RoutePath.kTest);
                      var room = await signalRService.createRoom();
                      Log.logPrint(room);
                    },
                  ),
              ],
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            _buildCard(
              context,
              children: [
                const ListTile(
                  leading: Icon(Remix.error_warning_line),
                  title: Text("免责声明"),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: Utils.showStatement,
                ),
                ListTile(
                  leading: const Icon(Remix.github_line),
                  title: const Text("开源主页"),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    launchUrlString(
                      "https://github.com/xuanxuan123xuan/dart_simple_live",
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, {required List<Widget> children}) {
    return Theme(
      data: Theme.of(context).copyWith(
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(borderRadius: AppStyle.radius8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
