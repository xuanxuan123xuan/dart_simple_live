import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/player_volume_session_policy.dart';

void main() {
  group('PlayerVolumeSessionPolicy', () {
    test('new room reapplies persisted user intent and clears transient mute',
        () {
      final state = PlayerVolumeSessionPolicy.forNewRoom(
        userIntentVolume: 37,
        lastAudibleVolume: 82,
      );

      expect(state.outputVolume, 37);
      expect(state.muted, isFalse);
      expect(state.lastAudibleVolume, 37);
    });

    test('persisted zero remains muted without inventing a restore volume', () {
      final state = PlayerVolumeSessionPolicy.forNewRoom(
        userIntentVolume: 0,
        lastAudibleVolume: 0,
      );

      expect(state.outputVolume, 0);
      expect(state.muted, isTrue);
      expect(state.lastAudibleVolume, 0);
    });

    test('persisted zero keeps a real last audible volume for later unmute',
        () {
      final state = PlayerVolumeSessionPolicy.forNewRoom(
        userIntentVolume: 0,
        lastAudibleVolume: 64,
      );

      expect(state.outputVolume, 0);
      expect(state.muted, isTrue);
      expect(state.lastAudibleVolume, 64);
    });

    test('unmute restores the actual previous volume instead of 100', () {
      final volume = PlayerVolumeSessionPolicy.volumeToRestoreAfterMute(
        lastAudibleVolume: 43,
        userIntentVolume: 18,
      );

      expect(volume, 43);
    });

    test('unmute falls back to persisted user intent', () {
      final volume = PlayerVolumeSessionPolicy.volumeToRestoreAfterMute(
        lastAudibleVolume: 0,
        userIntentVolume: 28,
      );

      expect(volume, 28);
    });

    test('volume inputs are clamped to the supported range', () {
      expect(PlayerVolumeSessionPolicy.normalize(-2), 0);
      expect(PlayerVolumeSessionPolicy.normalize(140), 100);
    });
  });
}
