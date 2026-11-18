import 'package:simple_live_core/simple_live_core.dart';

enum TvAutoSwitchReason {
  liveEnd,
  playbackFailure,
}

class TvAutoSwitchPolicy {
  const TvAutoSwitchPolicy._();

  static bool isConfirmedOffline(LiveStatusState state) {
    return state == LiveStatusState.offline;
  }

  static bool isEnabled({
    required TvAutoSwitchReason reason,
    required bool onLiveEnd,
    required bool onPlaybackFailure,
  }) {
    return switch (reason) {
      TvAutoSwitchReason.liveEnd => onLiveEnd,
      TvAutoSwitchReason.playbackFailure => onPlaybackFailure,
    };
  }
}
