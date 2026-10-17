import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/ohos_playback_profile_policy.dart';
import 'package:video_player_ohos/video_player_ohos.dart';

void main() {
  test('stable remains the default for every source', () {
    final decision = resolveOhosPlaybackProfile(
      requestedProfile: ohosStablePlaybackProfileValue,
      source: 'https://cdn.example/live.flv?token=secret',
      lowLatencyExperimentalSupported: true,
      disabledForSession: false,
    );

    expect(decision.profile, OhosPlaybackProfile.stable);
    expect(
      decision.reason,
      OhosPlaybackProfileDecisionReason.stableRequested,
    );
  });

  test('experimental profile is limited to supported HTTP-FLV', () {
    final flv = resolveOhosPlaybackProfile(
      requestedProfile: ohosLowLatencyExperimentalProfileValue,
      source: 'https://cdn.example/live.flv?token=secret',
      lowLatencyExperimentalSupported: true,
      disabledForSession: false,
    );
    final hls = resolveOhosPlaybackProfile(
      requestedProfile: ohosLowLatencyExperimentalProfileValue,
      source: 'https://cdn.example/live.m3u8?token=secret',
      lowLatencyExperimentalSupported: true,
      disabledForSession: false,
    );
    final rtmp = resolveOhosPlaybackProfile(
      requestedProfile: ohosLowLatencyExperimentalProfileValue,
      source: 'rtmp://cdn.example/live/room',
      lowLatencyExperimentalSupported: true,
      disabledForSession: false,
    );

    expect(flv.profile, OhosPlaybackProfile.lowLatencyExperimental);
    expect(hls.profile, OhosPlaybackProfile.stable);
    expect(rtmp.profile, OhosPlaybackProfile.stable);
  });

  test('missing capability and session fuse force stable fallback', () {
    final unsupported = resolveOhosPlaybackProfile(
      requestedProfile: ohosLowLatencyExperimentalProfileValue,
      source: 'http://cdn.example/live.flv',
      lowLatencyExperimentalSupported: false,
      disabledForSession: false,
    );
    final fused = resolveOhosPlaybackProfile(
      requestedProfile: ohosLowLatencyExperimentalProfileValue,
      source: 'http://cdn.example/live.flv',
      lowLatencyExperimentalSupported: true,
      disabledForSession: true,
    );

    expect(
      unsupported.reason,
      OhosPlaybackProfileDecisionReason.capabilityUnavailable,
    );
    expect(fused.profile, OhosPlaybackProfile.stable);
    expect(fused.reason, OhosPlaybackProfileDecisionReason.sessionFallback);
  });
}
