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
      'simple_live_cold_start_test_',
    );
    Hive.init(hiveDirectory.path);
  });

  setUp(() async {
    storage = LocalStorageService();
    storage.settingsBox = await Hive.openBox(
      'cold_start_${DateTime.now().microsecondsSinceEpoch}',
    );
    Get.put<LocalStorageService>(storage);
  });

  tearDown(() async {
    await storage.settingsBox.deleteFromDisk();
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('OHOS cold start clears pending room without restoring it', () async {
    await storage.setValue(
      LocalStorageService.kLastLiveRoomResumePending,
      true,
    );
    final settings = AppSettingsController();

    final room = await settings.consumePendingLastLiveRoom(restore: false);

    expect(room, isNull);
    expect(
      storage.getValue(
        LocalStorageService.kLastLiveRoomResumePending,
        true,
      ),
      isFalse,
    );
  });
}
