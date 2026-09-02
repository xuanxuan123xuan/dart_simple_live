import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

void main() {
  late Directory hiveDirectory;
  late LocalStorageService storage;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'simple_live_ohos_playback_profile_test_',
    );
    Hive.init(hiveDirectory.path);
  });

  setUp(() async {
    storage = LocalStorageService();
    final suffix = DateTime.now().microsecondsSinceEpoch;
    storage.settingsBox = await Hive.openBox('settings_$suffix');
    storage.shieldBox = await Hive.openBox<String>('shields_$suffix');
    storage.shieldPresetBox =
        await Hive.openBox<String>('shield_presets_$suffix');
    Get.put<LocalStorageService>(storage);
  });

  tearDown(() async {
    await storage.settingsBox.deleteFromDisk();
    await storage.shieldBox.deleteFromDisk();
    await storage.shieldPresetBox.deleteFromDisk();
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('profile defaults to stable and persists normalized values', () async {
    final settings = AppSettingsController();

    expect(
      settings.ohosPlaybackProfile.value,
      AppSettingsController.kOhosPlaybackProfileStable,
    );

    settings.setOhosPlaybackProfile(
      AppSettingsController.kOhosPlaybackProfileLowLatencyExperimental,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      settings.ohosPlaybackProfile.value,
      AppSettingsController.kOhosPlaybackProfileLowLatencyExperimental,
    );
    expect(
      storage.getValue(LocalStorageService.kOhosPlaybackProfile, 'stable'),
      AppSettingsController.kOhosPlaybackProfileLowLatencyExperimental,
    );

    settings.setOhosPlaybackProfile('not-a-profile');
    await Future<void>.delayed(Duration.zero);

    expect(
      settings.ohosPlaybackProfile.value,
      AppSettingsController.kOhosPlaybackProfileStable,
    );
    expect(
      storage.getValue(LocalStorageService.kOhosPlaybackProfile, 'invalid'),
      AppSettingsController.kOhosPlaybackProfileStable,
    );
  });

  test(
    'stored unknown profile is normalized to stable on initialization',
    () async {
      await storage.setValue(
        LocalStorageService.kOhosPlaybackProfile,
        'legacy',
      );

      final settings = AppSettingsController();
      settings.onInit();

      expect(
        settings.ohosPlaybackProfile.value,
        AppSettingsController.kOhosPlaybackProfileStable,
      );
    },
  );

  test('settings page gates the profile on native capability', () {
    final page =
        File('lib/modules/settings/play_settings_page.dart').readAsStringSync();

    expect(
      page,
      contains('lowLatencyExperimentalSupported != true'),
    );
    expect(page, contains('播放缓冲策略'));
    expect(page, contains('低延迟（实验）'));
    expect(page, contains('实际生效档位以当前播放会话为准'));
    expect(page, contains('本次会话实际生效'));
    expect(page, contains('实验档已回退'));
  });
}
