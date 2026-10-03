import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OHOS plugin exposes a one-shot playback profile configuration', () {
    final player = File(
      'third_party/video_player_ohos/lib/src/ohos_video_player.dart',
    ).readAsStringSync();

    expect(player, contains('enum OhosPlaybackProfile'));
    expect(player, contains('stable,'));
    expect(player, contains('lowLatencyExperimental,'));
    expect(player, contains('static void configureNextCreation({'));
    expect(player, contains('required OhosPlaybackProfile profile'));
    expect(player, contains('required int generation'));
    expect(player,
        contains('final configuration = _consumeNextCreationConfiguration();'));
    expect(player, contains('_nextCreationConfiguration = null;'));
    expect(player, contains('playbackProfile: configuration?.profile.name'));
    expect(player, contains('appPlayerGeneration: configuration?.generation'));
  });

  test('CreateMessage keeps the new fields optional and append-only', () {
    final messages = File(
      'third_party/video_player_ohos/lib/src/messages.g.dart',
    ).readAsStringSync();

    expect(messages, contains('String? playbackProfile;'));
    expect(messages, contains('int? appPlayerGeneration;'));
    expect(messages, contains('playbackProfile,'));
    expect(messages, contains('appPlayerGeneration,'));
    expect(
        messages, contains('result.length > 5 ? result[5] as String? : null'));
    expect(messages, contains('result.length > 6 ? result[6] as int? : null'));
  });

  test('ArkTS stores profile and app generation and preserves stable policy',
      () {
    final messages = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/Messages.ets',
    ).readAsStringSync();
    final api = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/VideoPlayerApiImpl.ets',
    ).readAsStringSync();
    final player = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/VideoPlayer.ets',
    ).readAsStringSync();

    expect(messages, contains('getPlaybackProfile()'));
    expect(messages, contains('getAppPlayerGeneration()'));
    expect(messages, contains('new Array<Object>(7)'));
    expect(messages, contains('list.length > 5'));
    expect(messages, contains('list.length > 6'));
    expect(api, contains('arg.getPlaybackProfile()'));
    expect(api, contains('arg.getAppPlayerGeneration()'));
    expect(api, contains('new VideoPlayer('));

    expect(player, contains('private playbackProfile: string'));
    expect(player, contains('private appPlayerGeneration: number | null'));
    expect(player, contains('PLAYBACK_PROFILE_LOW_LATENCY_EXPERIMENTAL'));
    expect(player, contains('this.appPlayerGeneration = appPlayerGeneration;'));
    expect(player, contains('lowLatencyExperimentalSupported'));

    final strategy = RegExp(
      r'private buildLivePlaybackStrategy\(\): media\.PlaybackStrategy \{([\s\S]*?)\n  \}',
    ).firstMatch(player)!.group(1)!;
    expect(
      strategy,
      contains(
        'this.playbackProfile !== PLAYBACK_PROFILE_LOW_LATENCY_EXPERIMENTAL',
      ),
    );
    expect(strategy, contains('return {};'));
    expect(strategy, contains('preferredBufferDuration: 1'));
    expect(strategy, isNot(contains('preferredBufferDurationForPlaying')));
    expect(strategy, isNot(contains('thresholdForAutoQuickPlay')));
    expect(strategy, isNot(contains('.setSpeed(')));
  });

  test('profile status event contains no source secret fields', () {
    final player = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/VideoPlayer.ets',
    ).readAsStringSync();
    final event = RegExp(
      r'private sendPlaybackProfile\(status: string\): void \{([\s\S]*?)\n  \}',
    ).firstMatch(player)!.group(1)!;

    expect(event, contains('event.set("event", "playbackProfile")'));
    expect(event, contains('event.set("textureId"'));
    expect(event, contains('event.set("profile"'));
    expect(event, contains('event.set("status"'));
    expect(event, contains('lowLatencyExperimentalSupported'));
    expect(event, isNot(contains('this.url')));
    expect(event, isNot(contains('this.headers')));
  });
}
