import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/ohos_video_player.dart';
import 'package:video_player/video_player.dart';

VideoPlayerValue _value({
  required Duration position,
  Duration duration = Duration.zero,
  bool playing = false,
  bool buffering = false,
}) {
  return VideoPlayerValue(
    duration: duration,
    position: position,
    isInitialized: true,
    isPlaying: playing,
    isBuffering: buffering,
  );
}

void main() {
  test('reports continuous buffering after eight seconds', () {
    final started = DateTime(2026, 7, 14, 12);
    final value = _value(position: Duration.zero, buffering: true);

    expect(
      detectOhosPlaybackHealthIssue(
        value: value,
        now: started.add(const Duration(seconds: 8)),
        bufferingSince: started,
        lastProgressAt: started,
        hasObservedProgress: false,
      ),
      OhosPlaybackHealthIssue.bufferingTimeout,
    );
  });

  test('reports a playback stall only after progress was observed', () {
    final progressedAt = DateTime(2026, 7, 14, 12);
    final value = _value(
      position: const Duration(seconds: 30),
      playing: true,
    );

    expect(
      detectOhosPlaybackHealthIssue(
        value: value,
        now: progressedAt.add(const Duration(seconds: 12)),
        bufferingSince: null,
        lastProgressAt: progressedAt,
        hasObservedProgress: true,
      ),
      OhosPlaybackHealthIssue.playbackStall,
    );
    expect(
      detectOhosPlaybackHealthIssue(
        value: value,
        now: progressedAt.add(const Duration(minutes: 1)),
        bufferingSince: null,
        lastProgressAt: progressedAt,
        hasObservedProgress: false,
      ),
      isNull,
    );
  });

  test('buffer flicker cannot postpone a no-progress timeout forever', () {
    final progressedAt = DateTime(2026, 7, 14, 12);
    final value = _value(
      position: const Duration(seconds: 30),
      playing: true,
      buffering: true,
    );

    expect(
      detectOhosPlaybackHealthIssue(
        value: value,
        now: progressedAt.add(const Duration(seconds: 12)),
        bufferingSince: progressedAt.add(const Duration(seconds: 10)),
        lastProgressAt: progressedAt,
        hasObservedProgress: true,
      ),
      OhosPlaybackHealthIssue.bufferingTimeout,
    );
  });

  test('treats a live timeline rewind as fresh progress', () {
    expect(
      didOhosPlaybackTimelineProgress(
        current: const Duration(seconds: 1),
        previous: const Duration(seconds: 30),
      ),
      isTrue,
    );
    expect(
      didOhosPlaybackTimelineProgress(
        current: const Duration(seconds: 29),
        previous: const Duration(seconds: 30),
      ),
      isFalse,
    );
  });

  test('detects a native completion that stops at the duration', () {
    final previous = _value(
      position: const Duration(seconds: 59),
      duration: const Duration(seconds: 60),
      playing: true,
    );
    final current = _value(
      position: const Duration(seconds: 60),
      duration: const Duration(seconds: 60),
    );

    expect(
      looksLikeOhosPlaybackCompleted(
        current: current,
        previous: previous,
      ),
      isTrue,
    );
  });

  test('does not treat a live timeline rewind as completion', () {
    final previous = _value(
      position: const Duration(seconds: 24),
      playing: true,
    );
    final current = _value(position: Duration.zero);

    expect(
      looksLikeOhosPlaybackCompleted(
        current: current,
        previous: previous,
      ),
      isFalse,
    );
  });

  test('does not treat an ordinary pause as completion', () {
    final previous = _value(
      position: const Duration(seconds: 24),
      playing: true,
    );
    final current = _value(position: const Duration(seconds: 24));

    expect(
      looksLikeOhosPlaybackCompleted(
        current: current,
        previous: previous,
      ),
      isFalse,
    );
  });
}
