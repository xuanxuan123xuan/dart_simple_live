import 'package:simple_live_core/simple_live_core.dart';

const String ohosStablePlaybackProfileValue = 'stable';
const String ohosLowLatencyExperimentalProfileValue = 'lowLatencyExperimental';

/// Playback policy selected for the active HarmonyOS player.
///
/// This enum used to live in the video_player_ohos package alongside the
/// AVPlayer platform implementation. With the app fully on libmpv it now
/// lives here so the mpv player can reference it without depending on the
/// removed AVPlayer plugin.
enum OhosPlaybackProfile {
  stable,
  lowLatencyExperimental,
}

enum OhosPlaybackProfileDecisionReason {
  stableRequested,
  experimentalEnabled,
  capabilityUnavailable,
  unsupportedProtocol,
  sessionFallback,
}

class OhosPlaybackProfileDecision {
  const OhosPlaybackProfileDecision({
    required this.profile,
    required this.reason,
  });

  final OhosPlaybackProfile profile;
  final OhosPlaybackProfileDecisionReason reason;

  bool get isExperimental =>
      profile == OhosPlaybackProfile.lowLatencyExperimental;
}

/// Resolves the native HarmonyOS playback profile without guessing support.
///
/// The first experimental release is deliberately limited to HTTP-FLV. HLS
/// and unknown/custom protocols keep the stable playback policy even when the
/// persisted user preference requests the experiment.
OhosPlaybackProfileDecision resolveOhosPlaybackProfile({
  required String requestedProfile,
  required String source,
  required bool lowLatencyExperimentalSupported,
  required bool disabledForSession,
}) {
  if (requestedProfile != ohosLowLatencyExperimentalProfileValue) {
    return const OhosPlaybackProfileDecision(
      profile: OhosPlaybackProfile.stable,
      reason: OhosPlaybackProfileDecisionReason.stableRequested,
    );
  }
  if (disabledForSession) {
    return const OhosPlaybackProfileDecision(
      profile: OhosPlaybackProfile.stable,
      reason: OhosPlaybackProfileDecisionReason.sessionFallback,
    );
  }
  if (!lowLatencyExperimentalSupported) {
    return const OhosPlaybackProfileDecision(
      profile: OhosPlaybackProfile.stable,
      reason: OhosPlaybackProfileDecisionReason.capabilityUnavailable,
    );
  }

  final uri = Uri.tryParse(source);
  final isHttp = uri != null &&
      (uri.scheme.toLowerCase() == 'http' ||
          uri.scheme.toLowerCase() == 'https');
  if (!isHttp || classifyLiveStreamProtocol(source) != LiveStreamProtocol.flv) {
    return const OhosPlaybackProfileDecision(
      profile: OhosPlaybackProfile.stable,
      reason: OhosPlaybackProfileDecisionReason.unsupportedProtocol,
    );
  }
  return const OhosPlaybackProfileDecision(
    profile: OhosPlaybackProfile.lowLatencyExperimental,
    reason: OhosPlaybackProfileDecisionReason.experimentalEnabled,
  );
}
