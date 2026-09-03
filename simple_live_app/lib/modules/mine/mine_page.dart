import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/app_update_service.dart';
import 'package:simple_live_app/services/cache_service.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';

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

    await _refreshCacheSize();
    final confirmed = await Utils.showAlertDialog(
      "当前缓存占用 $_cacheSize。\n\n将清理临时文件和图片缓存，不会删除账号、关注、观看记录或设置。",
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

  Widget _buildUpdateTile() {
    // OHOS update delivery is not adapted yet: hide the entry entirely.
    if (Utils.isOhos) {
      return const SizedBox.shrink();
    }
    final updateService = AppUpdateService.instance;
    return Obx(() {
      final hasUpdate = updateService.updateAvailable.value;
      return ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Remix.refresh_line),
            if (hasUpdate)
              Positioned(
                right: -2,
                top: -2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const SizedBox(width: 8, height: 8),
                ),
              ),
          ],
        ),
        title: const Text("检查更新"),
        trailing: const Icon(
          Icons.chevron_right,
          color: Colors.grey,
        ),
        onTap: () {
          Get.toNamed(RoutePath.kAppUpdate);
        },
      );
    });
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
          padding: AppStyle.edgeInsetsA4.copyWith(bottom: 96),
          children: [
            AppStyle.vGap12,
            GlassSurface(
              role: GlassSurfaceRole.content,
              radius: 20,
              child: ListTile(
                leading: Image.asset(
                  Theme.of(context).brightness == Brightness.dark
                      ? 'assets/images/logo_dark.png'
                      : 'assets/images/logo.png',
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
                  Get.toNamed(RoutePath.kAbout);
                },
              ),
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
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
              title: const Text("数据与同步"),
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
              leading: const Icon(Remix.settings_3_line),
              title: const Text("设置"),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
              onTap: () {
                Get.toNamed(RoutePath.kSettings);
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
              leading: const Icon(Remix.question_line),
              title: const Text("帮助与排障"),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
              onTap: () {
                Get.toNamed(RoutePath.kHelp);
              },
            ),
            Divider(
              indent: 12,
              endIndent: 12,
              color: Colors.grey.withAlpha(25),
            ),
            _buildUpdateTile(),
          ],
        ),
      ),
    );
  }
}
