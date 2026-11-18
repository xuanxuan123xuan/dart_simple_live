import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_configuration.dart';

void main() {
  test('default configuration preserves full multi-room behavior', () {
    const configuration = MultiRoomPlayerConfiguration();

    expect(configuration.preferLowestQuality, isFalse);
    expect(configuration.enableDanmaku, isTrue);
    expect(configuration.enableLiveHealthSampling, isTrue);
    expect(configuration.enableAutomaticRecovery, isTrue);
  });

  test('lightweight preview disables optional background work', () {
    const configuration = MultiRoomPlayerConfiguration.lightweightPreview();

    expect(configuration.preferLowestQuality, isTrue);
    expect(configuration.enableDanmaku, isFalse);
    expect(configuration.enableLiveHealthSampling, isFalse);
    expect(configuration.enableAutomaticRecovery, isFalse);
  });
}
