import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OHOS adaptive playback settings are persisted and visible', () {
    final storage =
        File('lib/services/local_storage_service.dart').readAsStringSync();
    final settings = File('lib/app/controller/app_settings_controller.dart')
        .readAsStringSync();
    final page =
        File('lib/modules/settings/play_settings_page.dart').readAsStringSync();

    expect(storage, contains('kOhosAutoQualityDegrade'));
    expect(storage, contains('kOhosNetworkFluctuationNotice'));
    expect(settings, contains('ohosAutoQualityDegrade'));
    expect(settings, contains('ohosNetworkFluctuationNotice'));
    expect(page, contains('网络波动时自动降低清晰度'));
    expect(page, contains('网络波动提示'));
  });

  test('OHOS buffering honors adaptive settings and starts diagnosis', () {
    final room = File('lib/modules/live_room/live_room_controller.dart')
        .readAsStringSync();
    final player = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();

    expect(room, contains('ohosAutoQualityDegrade.value'));
    expect(room, contains('observeAutoNetworkDiagnosisBuffering('));
    expect(player, contains('ohosNetworkFluctuationNotice.value'));
    expect(player, contains('void observeAutoNetworkDiagnosisBuffering('));
  });
}
