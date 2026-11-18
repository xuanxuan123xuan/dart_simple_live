import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_auto_switch_policy.dart';

void main() {
  group('TvAutoSwitchPolicy', () {
    test('only confirmed offline status is eligible after initial load', () {
      expect(
        TvAutoSwitchPolicy.isConfirmedOffline(LiveStatusState.offline),
        isTrue,
      );
      expect(
        TvAutoSwitchPolicy.isConfirmedOffline(LiveStatusState.live),
        isFalse,
      );
      expect(
        TvAutoSwitchPolicy.isConfirmedOffline(LiveStatusState.unknown),
        isFalse,
      );
    });

    test('uses the setting matching the switch reason', () {
      expect(
        TvAutoSwitchPolicy.isEnabled(
          reason: TvAutoSwitchReason.liveEnd,
          onLiveEnd: true,
          onPlaybackFailure: false,
        ),
        isTrue,
      );
      expect(
        TvAutoSwitchPolicy.isEnabled(
          reason: TvAutoSwitchReason.liveEnd,
          onLiveEnd: false,
          onPlaybackFailure: true,
        ),
        isFalse,
      );
      expect(
        TvAutoSwitchPolicy.isEnabled(
          reason: TvAutoSwitchReason.playbackFailure,
          onLiveEnd: false,
          onPlaybackFailure: true,
        ),
        isTrue,
      );
    });
  });
}
