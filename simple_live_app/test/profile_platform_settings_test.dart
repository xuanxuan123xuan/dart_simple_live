import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/profile_backup_service.dart';

void main() {
  group('ProfileBackupService.isSamePlatformPackage', () {
    test('accepts a package exported by this very platform', () {
      expect(
        ProfileBackupService.isSamePlatformPackage(Platform.operatingSystem),
        isTrue,
      );
    });

    test('accepts regardless of case and padding', () {
      expect(
        ProfileBackupService.isSamePlatformPackage(
          '  ${Platform.operatingSystem.toUpperCase()} ',
        ),
        isTrue,
      );
    });

    test('rejects a package from another platform', () {
      // The reported case: an Android package restored onto Windows carried
      // ao=audiotrack, which makes libmpv fail audio init and play silently.
      final foreign = Platform.isAndroid ? 'windows' : 'android';
      expect(ProfileBackupService.isSamePlatformPackage(foreign), isFalse);
    });

    test('treats a missing platform field as foreign', () {
      // Older exports may predate the field. Dropping tuning is recoverable;
      // writing a foreign ao leaves the user with no sound at all.
      expect(ProfileBackupService.isSamePlatformPackage(null), isFalse);
      expect(ProfileBackupService.isSamePlatformPackage(''), isFalse);
      expect(ProfileBackupService.isSamePlatformPackage('   '), isFalse);
    });

    test('treats a non-string platform field as foreign', () {
      expect(ProfileBackupService.isSamePlatformPackage(42), isFalse);
      expect(ProfileBackupService.isSamePlatformPackage(['windows']), isFalse);
    });
  });

  group('配置包的平台专属设置', () {
    late Directory tempDir;
    late ProfileBackupService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sl_profile_platform_');
      Hive.init(tempDir.path);
      Get.put(LocalStorageService());
      await LocalStorageService.instance.init();
      // importProfileMap 末尾会 reloadFromStorage()，需要控制器已注册。
      Get.put(AppSettingsController());
      Utils.packageInfo = PackageInfo(
        appName: 'Simple Live',
        packageName: 'com.simplelive.app',
        version: '1.0.0',
        buildNumber: '1',
      );
      service = ProfileBackupService();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await Hive.close();
      Get.reset();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    /// 直接走真实导入路径，只带 settings 分类。
    Future<ProfileImportSummary> importSettings(
      Map<String, dynamic> settings, {
      required dynamic platform,
    }) {
      return service.importProfileMap(
        {
          'schema': ProfileBackupService.schema,
          'schemaVersion': ProfileBackupService.schemaVersion,
          if (platform != null) 'platform': platform,
          'settings': settings,
        },
        options: const ProfileImportOptions(
          settings: true,
          accounts: false,
          shields: false,
          shieldPresets: false,
          follows: false,
          histories: false,
        ),
      );
    }

    test('跨平台包不会写入会导致无声的 ao', () async {
      final summary = await importSettings(
        {
          LocalStorageService.kMpvAdvancedOptions: 'ao=audiotrack\nvo=gpu',
          LocalStorageService.kAudioOutputDriver: 'audiotrack',
          LocalStorageService.kCustomPlayerOutput: true,
          LocalStorageService.kPlayerCompatMode: true,
          // 与平台无关的设置必须照常恢复。
          LocalStorageService.kPlayerScaleMode: 2,
        },
        platform: Platform.isAndroid ? 'windows' : 'android',
      );

      final box = LocalStorageService.instance.settingsBox;
      expect(box.containsKey(LocalStorageService.kMpvAdvancedOptions), isFalse);
      expect(box.containsKey(LocalStorageService.kAudioOutputDriver), isFalse);
      expect(box.containsKey(LocalStorageService.kCustomPlayerOutput), isFalse);
      expect(box.containsKey(LocalStorageService.kPlayerCompatMode), isFalse);
      // 非平台相关的项不受影响。
      expect(box.get(LocalStorageService.kPlayerScaleMode), 2);
      expect(summary.droppedPlatformSettings, 4);
      expect(summary.message, contains('跳过其他平台的播放器设置 4 项'));
    });

    test('同平台包保留播放器调优', () async {
      final summary = await importSettings(
        {
          LocalStorageService.kMpvAdvancedOptions: 'cache-secs=2',
          LocalStorageService.kAudioOutputDriver: 'wasapi',
          LocalStorageService.kPlayerScaleMode: 1,
        },
        platform: Platform.operatingSystem,
      );

      final box = LocalStorageService.instance.settingsBox;
      expect(box.get(LocalStorageService.kMpvAdvancedOptions), 'cache-secs=2');
      expect(box.get(LocalStorageService.kAudioOutputDriver), 'wasapi');
      expect(box.get(LocalStorageService.kPlayerScaleMode), 1);
      expect(summary.droppedPlatformSettings, 0);
      expect(summary.message, isNot(contains('跳过其他平台')));
    });

    test('没有 platform 字段的老包按跨平台处理', () async {
      final summary = await importSettings(
        {
          LocalStorageService.kAudioOutputDriver: 'audiotrack',
          LocalStorageService.kPlayerScaleMode: 3,
        },
        platform: null,
      );

      final box = LocalStorageService.instance.settingsBox;
      expect(box.containsKey(LocalStorageService.kAudioOutputDriver), isFalse);
      expect(box.get(LocalStorageService.kPlayerScaleMode), 3);
      expect(summary.droppedPlatformSettings, 1);
    });

    test('本机路径类设置无论来源平台都不恢复', () async {
      final summary = await importSettings(
        {
          LocalStorageService.kImportedMpvConfPath: '/data/user/0/mpv.conf',
          LocalStorageService.kPlayerScaleMode: 1,
        },
        // 即使源平台与当前一致也不恢复：绝对路径换机后必然失效。
        platform: Platform.operatingSystem,
      );

      final box = LocalStorageService.instance.settingsBox;
      expect(box.containsKey(LocalStorageService.kImportedMpvConfPath), isFalse);
      expect(box.get(LocalStorageService.kPlayerScaleMode), 1);
      // 本机路径不计入"平台专属"计数，它是无条件排除的另一类。
      expect(summary.droppedPlatformSettings, 0);
    });

    test('导出不带本机路径，但同平台调优照常带走', () async {
      final box = LocalStorageService.instance.settingsBox;
      await box.put(LocalStorageService.kImportedMpvConfPath, 'C:/mpv.conf');
      await box.put(LocalStorageService.kMpvAdvancedOptions, 'cache-secs=2');

      // 只导设置：账号/关注等分类要依赖别的服务，与本用例无关。
      final payload = service.exportProfileMap(
        options: const ProfileExportOptions(
          settings: true,
          accounts: false,
          shields: false,
          shieldPresets: false,
          follows: false,
          histories: false,
        ),
      );
      final settings = payload['settings'] as Map<String, dynamic>;

      expect(
        settings.containsKey(LocalStorageService.kImportedMpvConfPath),
        isFalse,
      );
      expect(settings[LocalStorageService.kMpvAdvancedOptions], 'cache-secs=2');
      // 导出必须记下平台，否则对端无法判断能不能恢复调优。
      expect(payload['platform'], Platform.operatingSystem);
    });
  });
}
