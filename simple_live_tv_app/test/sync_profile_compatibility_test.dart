import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/modules/sync/webdav/webdav_controller.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'package:simple_live_tv_app/services/profile_backup_service.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/models/db/follow_user.dart';
import 'package:simple_live_tv_app/models/db/history.dart';
import 'package:simple_live_tv_app/services/kuaishou_account_service.dart';

class _RecordingKuaishouAccountService extends KuaishouAccountService {
  Map<String, dynamic>? imported;

  @override
  // No platform session or account timers are needed for import assertions.
  // ignore: must_call_super
  void onInit() {}

  @override
  Map<String, dynamic> exportBackupMap() => {
        'slots': {
          'primary': {'cookie': 'local-primary'},
          'secondary': {'cookie': 'local-secondary'},
        },
      };

  @override
  void importBackupMap(dynamic raw, {dynamic legacySettings}) {
    imported = Map<String, dynamic>.from(raw as Map);
  }
}

void main() {
  late Directory hiveDirectory;
  late Box settingsBox;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('tv_sync_profile_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(FollowUserAdapter());
    Hive.registerAdapter(HistoryAdapter());
  });

  setUp(() async {
    final storage = Get.put(LocalStorageService());
    await storage.init();
    settingsBox = storage.settingsBox;
    await Get.put(DBService()).init();
    Get.put(AppSettingsController());
  });

  tearDown(() async {
    Get.reset();
    await Hive.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  group('TV profile sync compatibility', () {
    test('schema 4 ignores legacy settings when merging Kuaishou slots',
        () async {
      final account = _RecordingKuaishouAccountService();
      Get.put<KuaishouAccountService>(account);
      await ProfileBackupService().importProfileJson(
        jsonEncode({
          'schema': ProfileBackupService.schema,
          'schemaVersion': 4,
          'settings': {
            LocalStorageService.kKuaishouSecondaryCookie: 'legacy-secondary',
          },
          'accounts': {
            'items': [
              {'siteId': 'kuaishou', 'cookie': 'incoming-primary'},
            ],
          },
        }),
        options: const ProfileImportOptions(
          settings: false,
          shields: false,
          follows: false,
          histories: false,
        ),
      );
      final slots = account.imported!['slots'] as Map;
      expect(slots['primary']['cookie'], 'incoming-primary');
      expect(slots['secondary']['cookie'], 'local-secondary');
    });

    test('disabled accounts preserve canonical and legacy credentials',
        () async {
      await settingsBox.put(LocalStorageService.kDouyuCookie, 'local-cookie');
      final summary = await ProfileBackupService().importProfileJson(
        jsonEncode({
          'schema': ProfileBackupService.schema,
          'schemaVersion': 3,
          'settings': {LocalStorageService.kDouyuCookie: 'legacy-cookie'},
          'accounts': {
            'items': [
              {'siteId': 'douyu', 'cookie': 'incoming-cookie'},
            ],
          },
        }),
        overwrite: true,
        options: const ProfileImportOptions(
          accounts: false,
          shields: false,
          follows: false,
          histories: false,
        ),
      );
      expect(settingsBox.get(LocalStorageService.kDouyuCookie), 'local-cookie');
      expect(summary.accounts, 0);
    });

    test('empty and excluded account items preserve existing credentials',
        () async {
      await settingsBox.put(LocalStorageService.kDouyuCookie, 'local-cookie');
      final summary = await ProfileBackupService().importProfileMap(
        {
          'accounts': {
            'items': [
              {'siteId': 'douyu', 'cookie': ''},
              {'siteId': 'xiaohongshu', 'cookie': 'excluded-cookie'},
              {'siteId': 'future-provider', 'cookie': 'unknown-cookie'},
            ],
          },
        },
        overwrite: true,
        options: const ProfileImportOptions(
          settings: false,
          accounts: true,
          accountSiteIds: {'douyu'},
          shields: false,
          follows: false,
          histories: false,
        ),
      );
      expect(settingsBox.get(LocalStorageService.kDouyuCookie), 'local-cookie');
      expect(summary.accounts, 0);
      expect(summary.skipped, 1);
    });

    test('unknown sites do not erase existing follows or histories', () async {
      final db = DBService.instance;
      await db.addFollow(
          FollowUser.fromJson({'siteId': 'bilibili', 'roomId': '1'}));
      await db.addOrUpdateHistory(
          History.fromJson({'siteId': 'bilibili', 'roomId': '1'}));
      final summary = await ProfileBackupService().importProfileMap(
        {
          'followUsers': [
            {'siteId': 'future-provider', 'roomId': '2'},
            {'siteId': 'douyu', 'roomId': '3'},
          ],
          'histories': [
            {'siteId': 'future-provider', 'roomId': '2'},
          ],
        },
        overwrite: true,
        options: const ProfileImportOptions(
          settings: false,
          accounts: false,
          shields: false,
        ),
      );
      expect(db.getFollowExist('bilibili_1'), isTrue);
      expect(db.getFollowExist('douyu_3'), isTrue);
      expect(db.getHistory('bilibili_1'), isNotNull);
      expect(summary.skipped, 2);
    });

    test('exports schema 4 and accepts schemas 2, 3, and 4 only', () {
      expect(ProfileBackupService.schemaVersion, 4);
      for (final version in [2, 3, 4]) {
        expect(
          ProfileBackupService.isSupportedSchemaVersion(version),
          isTrue,
          reason: 'schema $version remains importable',
        );
      }
      expect(ProfileBackupService.isSupportedSchemaVersion(1), isFalse);
      expect(ProfileBackupService.isSupportedSchemaVersion(5), isFalse);
    });

    test('never exports account cookies as settings', () {
      final filtered = ProfileBackupService().filterTransportSettings({
        LocalStorageService.kBilibiliCookie: 'bili-secret',
        LocalStorageService.kDouyinCookie: 'douyin-secret',
        'DouyuCookie': 'douyu-secret',
        'XiaohongshuCookie': 'xhs-secret',
        LocalStorageService.kKuaishouCookie: 'ks-secret',
        LocalStorageService.kKuaishouSecondaryCookie: 'ks-secondary-secret',
        'playerVolume': 65,
      });

      expect(filtered, {'playerVolume': 65});
    });

    test('cross-platform overwrite preserves TV decoder and output settings',
        () async {
      await settingsBox.put(
        LocalStorageService.kVideoHardwareDecoder,
        'mediacodec-copy',
      );
      await settingsBox.put(LocalStorageService.kVideoOutputDriver, 'gpu');
      await settingsBox.put(
        LocalStorageService.kAudioOutputDriver,
        'audiotrack',
      );
      await settingsBox.put(LocalStorageService.kCustomPlayerOutput, true);
      await settingsBox.put(LocalStorageService.kPlayerScaleMode, 7);

      final foreignPlatform = Platform.isAndroid ? 'windows' : 'android';
      final summary = await ProfileBackupService().importProfileMap(
        {
          'schema': ProfileBackupService.schema,
          'schemaVersion': ProfileBackupService.schemaVersion,
          'platform': foreignPlatform,
          'settings': {LocalStorageService.kPlayerScaleMode: 2},
        },
        overwrite: true,
        options: const ProfileImportOptions(
          settings: true,
          accounts: false,
          shields: false,
          follows: false,
          histories: false,
        ),
      );

      expect(
        settingsBox.get(LocalStorageService.kVideoHardwareDecoder),
        'mediacodec-copy',
      );
      expect(settingsBox.get(LocalStorageService.kVideoOutputDriver), 'gpu');
      expect(settingsBox.get(LocalStorageService.kAudioOutputDriver),
          'audiotrack');
      expect(settingsBox.get(LocalStorageService.kCustomPlayerOutput), true);
      expect(settingsBox.get(LocalStorageService.kPlayerScaleMode), 2);
      expect(summary.droppedPlatformSettings, 0);
    });

    test('same-platform overwrite clears absent TV decoder and output settings',
        () async {
      await settingsBox.put(
        LocalStorageService.kVideoHardwareDecoder,
        'mediacodec-copy',
      );
      await settingsBox.put(LocalStorageService.kVideoOutputDriver, 'gpu');
      await settingsBox.put(
        LocalStorageService.kAudioOutputDriver,
        'audiotrack',
      );
      await settingsBox.put(LocalStorageService.kCustomPlayerOutput, true);

      await ProfileBackupService().importProfileMap(
        {
          'schema': ProfileBackupService.schema,
          'schemaVersion': ProfileBackupService.schemaVersion,
          'platform': Platform.operatingSystem,
          'settings': {LocalStorageService.kPlayerScaleMode: 2},
        },
        overwrite: true,
        options: const ProfileImportOptions(
          settings: true,
          accounts: false,
          shields: false,
          follows: false,
          histories: false,
        ),
      );

      expect(
        settingsBox.containsKey(LocalStorageService.kVideoHardwareDecoder),
        isFalse,
      );
      expect(
        settingsBox.containsKey(LocalStorageService.kVideoOutputDriver),
        isFalse,
      );
      expect(
        settingsBox.containsKey(LocalStorageService.kAudioOutputDriver),
        isFalse,
      );
      expect(
        settingsBox.containsKey(LocalStorageService.kCustomPlayerOutput),
        isFalse,
      );
      expect(settingsBox.get(LocalStorageService.kPlayerScaleMode), 2);
    });

    test('recognizes profile archives so legacy files are fallback only', () {
      expect(
        WebDavController.archiveContainsProfile([
          'SimpleLive_Profile_v4.json',
        ]),
        isTrue,
      );
      expect(
        WebDavController.archiveContainsProfile([
          'SimpleLive_Profile_v3.json',
        ]),
        isTrue,
      );
      expect(
        WebDavController.archiveContainsProfile([
          'SimpleLive_Profile_v2.json',
        ]),
        isTrue,
      );
      expect(
        WebDavController.archiveContainsProfile([
          'SimpleLive_Settings.json',
          'SimpleLive_bilibili_account.json',
        ]),
        isFalse,
      );
    });
  });
}
