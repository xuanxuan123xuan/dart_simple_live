import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/profile_backup_service.dart';
import 'package:simple_live_app/services/xiaohongshu_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  late Directory hiveDirectory;
  late LocalStorageService storage;
  late XiaohongshuAccountService account;
  late Box settingsBox;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'simple_live_xiaohongshu_account_test_',
    );
    Hive.init(hiveDirectory.path);
  });

  setUp(() async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    settingsBox = await Hive.openBox('settings_$suffix');
    storage = LocalStorageService()..settingsBox = settingsBox;
    Get.put<LocalStorageService>(storage);
    account = Get.put(XiaohongshuAccountService());
    Get.put(KuaishouAccountService());
  });

  tearDown(() async {
    await settingsBox.deleteFromDisk();
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('registers sixth site and migrates old, duplicate and retired ids',
      () async {
    await LocalStorageService.instance.setValue(
      LocalStorageService.kSiteSort,
      'bilibili,douyu,huya,douyin,kuaishou,bilibili,retired',
    );
    final settings = AppSettingsController();
    settings.initSiteSort();
    expect(settings.siteSort.toList(), [
      'bilibili',
      'douyu',
      'huya',
      'douyin',
      'kuaishou',
      'xiaohongshu',
    ]);
    expect(Sites.allSites.length, 6);
  });

  test('normalizes a Cookie header while preserving equals in values', () {
    expect(
      account.normalizeCookie('Host: xiaohongshu.com\nCookie: a=1; b=x=y'),
      'a=1; b=x=y',
    );
    expect(account.normalizeCookie('a=1; invalid; =empty'), 'a=1');
  });

  test('saves normalized cookie and applies it to the live site', () async {
    final saved = await account.setCookie('Cookie: a=1; b=x=y');
    final site =
        Sites.allSites[Constant.kXiaohongshu]!.liveSite as XiaohongshuSite;

    expect(saved, isTrue);
    expect(account.cookie, 'a=1; b=x=y');
    expect(account.hasCookie.value, isTrue);
    expect(site.cookie, 'a=1; b=x=y');
    expect(
      storage.getValue(LocalStorageService.kXiaohongshuCookie, ''),
      'a=1; b=x=y',
    );
  });

  test('rejects invalid replacement and clears persisted/site state', () async {
    await account.setCookie('a=1');
    expect(await account.setCookie('no-cookie-pairs'), isFalse);
    expect(account.cookie, 'a=1');

    await account.clearCookie();
    final site =
        Sites.allSites[Constant.kXiaohongshu]!.liveSite as XiaohongshuSite;
    expect(account.cookie, isEmpty);
    expect(account.hasCookie.value, isFalse);
    expect(site.cookie, isEmpty);
    expect(
      storage.getValue(LocalStorageService.kXiaohongshuCookie, 'missing'),
      isEmpty,
    );
  });

  test('backs up the account separately and restores its cookie', () async {
    Utils.packageInfo = PackageInfo(
      appName: 'Simple Live',
      packageName: 'com.simplelive.app',
      version: '1.0.0',
      buildNumber: '1',
    );
    await account.setCookie('xiaohongshu_session=backup-value');

    final backup = ProfileBackupService().exportProfileMap(
      options: const ProfileExportOptions(
        settings: true,
        accounts: true,
        shields: false,
        shieldPresets: false,
        follows: false,
        histories: false,
      ),
    );
    final settings = backup['settings'] as Map<String, dynamic>;
    final accounts = backup['accounts'] as Map<String, dynamic>;
    final accountItems = accounts['items'] as List;
    final xiaohongshuItem = accountItems.cast<Map>().firstWhere(
          (item) => item['siteId'] == Constant.kXiaohongshu,
        );

    expect(
        settings.containsKey(LocalStorageService.kXiaohongshuCookie), isFalse);
    expect(xiaohongshuItem['cookie'], 'xiaohongshu_session=backup-value');

    await account.setCookie('xiaohongshu_session=old-value');
    final summary = await ProfileBackupService().importProfileMap(
      {
        'schema': ProfileBackupService.schema,
        'schemaVersion': ProfileBackupService.schemaVersion,
        'accounts': {
          'items': [xiaohongshuItem],
        },
      },
      options: const ProfileImportOptions(
        settings: false,
        accounts: true,
        shields: false,
        shieldPresets: false,
        follows: false,
        histories: false,
      ),
    );
    final site =
        Sites.allSites[Constant.kXiaohongshu]!.liveSite as XiaohongshuSite;

    expect(summary.accounts, 1);
    expect(account.cookie, 'xiaohongshu_session=backup-value');
    expect(
      storage.getValue(LocalStorageService.kXiaohongshuCookie, ''),
      'xiaohongshu_session=backup-value',
    );
    expect(site.cookie, 'xiaohongshu_session=backup-value');
  });
}
