import 'dart:io';

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
  test('OHOS playback state owns a display lease and drives keep-awake', () {
    final player = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();

    expect(player, contains('initPlaybackDisplayLease();'));
    expect(player, contains('_setKeepScreenAwake(value.isPlaying);'));
    expect(player, contains('await releasePlaybackDisplayLease();'));
    expect(
      player,
      isNot(contains('if (!Utils.isOhos) {\n      _playbackDisplayLease')),
    );
  });

  test('OHOS assigns each source generation once and selects by headers', () {
    final nativePlayer = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/VideoPlayer.ets',
    ).readAsStringSync();

    expect(
      nativePlayer,
      contains('assignMediaSourceIfNeeded(generation: number)'),
    );
    expect(nativePlayer, contains('SOURCE_ASSIGNMENT_ASSIGNING'));
    expect(nativePlayer, contains('SOURCE_ASSIGNMENT_ASSIGNED'));
    expect(nativePlayer, contains('generation === this.playerGeneration'));
    expect(
      nativePlayer,
      contains(
        'this.disposed || creationGeneration !== this.playerGeneration',
      ),
    );
    expect(nativePlayer, contains('Object.keys(this.headers).length > 0'));
    expect(nativePlayer, contains('player.url = this.getIUri();'));
    expect(
      nativePlayer,
      contains('player.setMediaSource(mediaSource, playbackStrategy)'),
    );
    expect(
      nativePlayer,
      contains('let playbackStrategy: media.PlaybackStrategy = {};'),
    );
    expect(nativePlayer, isNot(contains('preferredBufferDuration')));
    expect(nativePlayer, contains('Events.START_RENDER_FRAME'));
    expect(nativePlayer, contains('this.sendFirstFrame();'));
    expect(nativePlayer, contains('event.set("event", "firstFrame")'));
  });

  test('OHOS waits for a real native first frame and times it out', () {
    final player = File(
      'lib/modules/live_room/player/ohos_video_player.dart',
    ).readAsStringSync();
    final plugin = File(
      'third_party/video_player_ohos/lib/src/ohos_video_player.dart',
    ).readAsStringSync();

    expect(player, contains('OhosVideoPlayer.firstFrameEvents.listen'));
    expect(player, contains('event.textureId != currentTextureId'));
    expect(player, contains('_startFirstFrameTimeout(generation, controller)'));
    expect(player, contains('const ohosFirstFrameTimeout'));
    expect(plugin, contains("case 'firstFrame':"));
  });

  test('OHOS does not replace a starting player from background TCP timing',
      () {
    final controller = File(
      'lib/modules/live_room/live_room_controller.dart',
    ).readAsStringSync();
    final scheduler = RegExp(
      r'void _scheduleAutoSelectFastestLine\([\s\S]*?'
      r'Future<void> _selectFastestLineAfterPlaybackStart',
    ).firstMatch(controller)!.group(0)!;

    expect(scheduler, contains('if (Utils.isOhos ||'));
  });

  test('OHOS native errors are structured and sanitized', () {
    final nativePlayer = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/VideoPlayer.ets',
    ).readAsStringSync();
    final sendError = RegExp(
      r'sendError\(error: BusinessError\): void \{([\s\S]*?)\n  \}',
    ).firstMatch(nativePlayer)!.group(1)!;

    for (final field in const [
      'nativeErrorCode',
      'nativeState',
      'sourceAssignmentState',
      'sourceKind',
      'prepared',
      'firstFrameRendered',
    ]) {
      expect(sendError, contains('details.set("$field"'));
    }
    expect(sendError, isNot(contains('url')));
    expect(sendError, isNot(contains('headers')));
    expect(sendError, contains(r'HarmonyOS AVPlayer error ${error.code}'));
    expect(nativePlayer, contains('this.sendError(err);'));
  });

  test('OHOS ignores only prepared non-fatal operation errors', () {
    final nativePlayer = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/VideoPlayer.ets',
    ).readAsStringSync();
    final ignoreError = RegExp(
      r'shouldIgnorePreparedPlaybackError\(error: BusinessError\): boolean \{([\s\S]*?)\n  \}',
    ).firstMatch(nativePlayer)!.group(1)!;

    expect(ignoreError, contains('this.prepared'));
    expect(ignoreError, contains('SOURCE_ASSIGNMENT_ASSIGNED'));
    expect(ignoreError, contains('OPERATE_ERROR'));
    expect(ignoreError, contains('AVPLAYER_STATE_ERROR'));
    expect(ignoreError, isNot(contains('5400103')));
    expect(
      nativePlayer,
      contains('if (this.shouldIgnorePreparedPlaybackError(err))'),
    );
  });

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
