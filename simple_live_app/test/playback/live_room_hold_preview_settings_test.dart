import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

void main() {
  group('live room hold preview audio setting', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sl_hold_preview_');
      Hive.init(tempDir.path);
      Get.put(LocalStorageService());
      await LocalStorageService.instance.init();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await Hive.close();
      Get.reset();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('defaults to muted preview audio when no value is stored', () {
      final controller = Get.put(AppSettingsController());

      expect(controller.liveRoomHoldPreviewAudio.value, isFalse);
    });

    test('loads and persists the preview audio preference', () async {
      await LocalStorageService.instance.setValue(
        LocalStorageService.kLiveRoomHoldPreviewAudio,
        true,
      );
      final controller = Get.put(AppSettingsController());

      expect(controller.liveRoomHoldPreviewAudio.value, isTrue);

      controller.setLiveRoomHoldPreviewAudio(false);
      await Future<void>.delayed(Duration.zero);

      expect(controller.liveRoomHoldPreviewAudio.value, isFalse);
      expect(
        LocalStorageService.instance.getValue(
          LocalStorageService.kLiveRoomHoldPreviewAudio,
          true,
        ),
        isFalse,
      );
    });
  });
}
