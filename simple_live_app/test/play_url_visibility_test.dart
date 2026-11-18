import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copy-play-url entry is persisted and disabled by default', () {
    final storage =
        File('lib/services/local_storage_service.dart').readAsStringSync();
    final settings = File('lib/app/controller/app_settings_controller.dart')
        .readAsStringSync();
    final settingsPage =
        File('lib/modules/settings/play_settings_page.dart').readAsStringSync();

    expect(storage, contains('kPlayerShowPlayUrl'));
    expect(
      settings,
      contains('getValue(LocalStorageService.kPlayerShowPlayUrl, false)'),
    );
    expect(settings, contains('setPlayerShowPlayUrl'));
    expect(settingsPage, contains('显示“复制播放直链”'));
  });

  test('both live-room entries honor the setting', () {
    final page =
        File('lib/modules/live_room/live_room_page.dart').readAsStringSync();

    expect(
      RegExp(r'playerShowPlayUrl\.value').allMatches(page).length,
      greaterThanOrEqualTo(2),
    );
    expect(
      RegExp('复制播放直链').allMatches(page).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('copy action uses the current effective playback URL', () {
    final controller = File(
      'lib/modules/live_room/live_room_controller.dart',
    ).readAsStringSync();
    final start = controller.indexOf('void copyPlayUrl()');
    final end = controller.indexOf('void showDanmuSettingsSheet()', start);
    final method = controller.substring(start, end);

    expect(start, greaterThanOrEqualTo(0));
    expect(method, contains('currentNetworkDiagnosePlaybackUrl'));
    expect(method, isNot(contains('getPlayUrls(')));
    expect(method, isNot(contains('playUrl.urls.first')));
  });
}
