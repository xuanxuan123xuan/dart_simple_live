
import 'package:flutter/foundation.dart';
import 'package:simple_live_app/modules/live_room/player/ohos_playback_profile_policy.dart';
import 'package:video_player/video_player.dart';

enum OhosPlaybackHealthIssue {
  bufferingTimeout,
  playbackStall,

  /// Neither the timeline nor the native heartbeat has ever been observed, so
  /// liveness cannot be judged. Reported for diagnostics only: the picture may
  /// well be fine, and retrying would interrupt a stream that is playing.
  playbackUnobservable,
}

typedef OhosVideoValueChanged = void Function(
  int playerGeneration,
  VideoPlayerValue value,
);

/// Native playback telemetry for one player generation.
typedef OhosVideoTelemetryChanged = void Function(
  int playerGeneration,
  OhosPlaybackTelemetry telemetry,
);

typedef OhosPlaybackProfileChanged = void Function(
  int sessionGeneration,
  int playerGeneration,
  OhosPlaybackProfileDecision decision,
);

/// Liveness and cache evidence gathered from the active HarmonyOS backend.
@immutable
class OhosPlaybackTelemetry {
  const OhosPlaybackTelemetry({
    this.heartbeatAt,
    this.position,
    this.cacheDuration,
    this.cacheSampledAt,
    this.hasCacheUpdate = false,
  });

  /// When the most recent native clock tick arrived, or null when this
  /// generation has never produced one.
  ///
  /// Only `TIME_UPDATE` sets this. Cache telemetry deliberately leaves it
  /// untouched, because a buffer that no longer drains keeps reporting depth
  /// long after the clock has died — treating that as a heartbeat would
  /// disguise a dead player as a healthy one.
  final DateTime? heartbeatAt;

  /// Timeline reported alongside the heartbeat, when AVPlayer exposes one.
  final Duration? position;

  /// Depth of the native read-ahead cache, when reported.
  final Duration? cacheDuration;

  /// Native cache-property sample time. Heartbeats never populate this.
  final DateTime? cacheSampledAt;

  /// Whether this telemetry item explicitly updates (or clears) cache state.
  final bool hasCacheUpdate;
}

const ohosBufferingTimeout = Duration(seconds: 8);
const ohosPlaybackStallTimeout = Duration(seconds: 12);
const ohosFirstFrameTimeout = Duration(seconds: 12);

/// A heartbeat fires about once per second, so this tolerates a long gap
/// before concluding the native player has gone quiet.
const ohosHeartbeatStallTimeout = Duration(seconds: 10);

/// Grace period before declaring liveness unobservable, giving both the
/// timeline and the heartbeat a fair chance to show up first.
const ohosUnobservableGrace = Duration(seconds: 20);

/// Classifies playback health from the strongest evidence available.
///
/// Evidence is layered, strongest first:
///  1. the timeline advances — unambiguously healthy;
///  2. the timeline is frozen but native heartbeats keep arriving — alive with
///     no exposed timeline, which is normal for HTTP-FLV live on HarmonyOS;
///  3. neither signal has ever appeared — unjudgeable, never a retry trigger.
///
/// Buffering keeps its own independent timer, since a player can be stuck
/// buffering while its clock still ticks.
// Shared with the libmpv player implementation (mpv_ohos_player.dart).
OhosPlaybackHealthIssue? detectOhosPlaybackHealthIssue({
  required VideoPlayerValue value,
  required DateTime now,
  required DateTime? bufferingSince,
  required DateTime lastProgressAt,
  required bool hasObservedProgress,
  DateTime? lastHeartbeatAt,
  bool hasObservedHeartbeat = false,
  DateTime? monitoringSince,
}) {
  final bool liveClockStalled = hasObservedProgress
      ? now.difference(lastProgressAt) >= ohosPlaybackStallTimeout
      : hasObservedHeartbeat &&
          lastHeartbeatAt != null &&
          now.difference(lastHeartbeatAt) >= ohosHeartbeatStallTimeout;

  if (value.isBuffering) {
    if (bufferingSince != null &&
        (now.difference(bufferingSince) >= ohosBufferingTimeout ||
            liveClockStalled)) {
      return OhosPlaybackHealthIssue.bufferingTimeout;
    }
    return null;
  }

  if (!value.isPlaying) {
    return null;
  }

  if (liveClockStalled) {
    return OhosPlaybackHealthIssue.playbackStall;
  }

  // No timeline and no heartbeat ever seen. Report it so the cause is visible
  // in logs instead of silently disabling every progress-based safeguard.
  if (!hasObservedProgress &&
      !hasObservedHeartbeat &&
      monitoringSince != null &&
      now.difference(monitoringSince) >= ohosUnobservableGrace) {
    return OhosPlaybackHealthIssue.playbackUnobservable;
  }

  return null;
}

bool didOhosPlaybackTimelineProgress({
  required Duration current,
  required Duration previous,
}) {
  if (current > previous) {
    return true;
  }
  // A live HLS window can restart its timestamp after a discontinuity. Count
  // a meaningful rewind as progress so the watchdog does not wait for the new
  // timeline to catch up to the old timestamp.
  return previous - current >= const Duration(seconds: 2);
}

@visibleForTesting
bool looksLikeOhosPlaybackCompleted({
  required VideoPlayerValue current,
  required VideoPlayerValue? previous,
}) {
  if (previous == null ||
      !current.isInitialized ||
      current.hasError ||
      current.isBuffering) {
    return false;
  }

  final duration = current.duration;
  final stoppedAtEnd = previous.isPlaying &&
      !current.isPlaying &&
      duration > Duration.zero &&
      current.position >= duration - const Duration(seconds: 1);

  // Do not treat a rewind to zero as completion for a live stream. HLS live
  // windows can reset their timeline during a discontinuity, which used to
  // trigger the retry limit and incorrectly mark an active room as offline.
  return stoppedAtEnd;
}
