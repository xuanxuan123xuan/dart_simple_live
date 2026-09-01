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
    expect(nativePlayer, contains('Events.START_RENDER_FRAME'));
    expect(nativePlayer, contains('this.sendFirstFrame();'));
    expect(nativePlayer, contains('event.set("event", "firstFrame")'));
  });

  test('OHOS build keeps API 12 compatibility and targets API 18', () {
    final buildProfile = File(
      'ohos/build-profile.json5',
    ).readAsStringSync();

    expect(
      buildProfile,
      contains('"compatibleSdkVersion": "5.0.0(12)"'),
    );
    expect(
      buildProfile,
      contains('"targetSdkVersion": "5.1.0(18)"'),
    );
  });

  test('OHOS live buffering policy changes at the API 18 boundary', () {
    final nativePlayer = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/VideoPlayer.ets',
    ).readAsStringSync();
    final policyBuilder = RegExp(
      r'buildLivePlaybackStrategy\(\): media\.PlaybackStrategy \{([\s\S]*?)\n  \}',
    ).firstMatch(nativePlayer)!.group(1)!;

    expect(
      nativePlayer,
      contains('OHOS_SMART_CATCHUP_API_VERSION: number = 18'),
    );
    expect(
      nativePlayer,
      contains('LIVE_PREFERRED_BUFFER_DURATION_SECONDS: number = 20'),
    );
    expect(
      nativePlayer,
      contains(
        'LIVE_PREFERRED_BUFFER_DURATION_FOR_PLAYING_SECONDS: number = 5',
      ),
    );
    expect(
      nativePlayer,
      contains('LIVE_SMART_CATCHUP_THRESHOLD_SECONDS: number = 60'),
    );
    expect(
      policyBuilder,
      contains(
        'deviceInfo.sdkApiVersion >= OHOS_SMART_CATCHUP_API_VERSION',
      ),
    );
    expect(policyBuilder, contains('preferredBufferDuration:'));
    expect(policyBuilder, contains('preferredBufferDurationForPlaying'));
    expect(policyBuilder, contains('thresholdForAutoQuickPlay'));

    bool usesApi18Policy(int sdkApiVersion) => sdkApiVersion >= 18;
    expect(usesApi18Policy(12), isFalse);
    expect(usesApi18Policy(17), isFalse);
    expect(usesApi18Policy(18), isTrue);
  });

  test('OHOS applies policy and prepare once per current generation', () {
    final nativePlayer = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/VideoPlayer.ets',
    ).readAsStringSync();
    final prepareCurrent = RegExp(
      r'prepareCurrentGeneration\([\s\S]*?\n  \}',
    ).firstMatch(nativePlayer)!.group(0)!;

    expect(nativePlayer, contains('playbackStrategyGeneration: number = -1'));
    expect(nativePlayer, contains('playbackStrategyTask: Promise<void> | null'));
    expect(nativePlayer, contains('prepareGeneration: number = -1'));
    expect(
      nativePlayer,
      contains('this.playbackStrategyGeneration = -1;'),
    );
    expect(nativePlayer, contains('this.prepareGeneration = -1;'));
    expect(
      nativePlayer,
      contains('this.playbackStrategyGeneration === generation'),
    );
    expect(prepareCurrent, contains('this.prepareGeneration === generation'));
    expect(prepareCurrent, contains('await this.applyPlaybackStrategyIfNeeded'));
    expect(
      prepareCurrent.indexOf('await this.applyPlaybackStrategyIfNeeded'),
      lessThan(prepareCurrent.indexOf('await player.prepare()')),
    );
    expect(nativePlayer, contains('await this.prepareCurrentGeneration('));
    expect(nativePlayer, contains('this.disposed = true;'));
    expect(nativePlayer, contains('this.playerGeneration += 1;'));
  });

  test('OHOS policy failures fall back without exposing source secrets', () {
    final nativePlayer = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/VideoPlayer.ets',
    ).readAsStringSync();
    final strategyLogging = RegExp(
      r'logPlaybackStrategy\([\s\S]*?\n  \}',
    ).firstMatch(nativePlayer)!.group(0)!;

    expect(nativePlayer, contains('await player.setPlaybackStrategy('));
    expect(
      nativePlayer,
      contains("this.logPlaybackStrategy('fallback-system-default'"),
    );
    expect(
      nativePlayer,
      contains('await player.setMediaSource(mediaSource, {});'),
    );
    expect(strategyLogging, contains('sdkApi='));
    expect(strategyLogging, contains('sourceKind='));
    expect(strategyLogging, isNot(contains('this.url')));
    expect(strategyLogging, isNot(contains('this.headers')));
  });

  test('OHOS app-owned latency chase remains disabled', () {
    final player = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();

    expect(player, contains('if (!Utils.isOhos) {'));
    expect(player, contains('await _liveLatencyChaser.start('));
    expect(player, contains('if (Utils.isOhos) return;'));
    expect(
      player,
      contains(
        'Utils.isOhos ? null : _liveLatencyChaser.recommendedSampleInterval',
      ),
    );
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

  test('OHOS fullscreen top bar stays positioned in placeholder states', () {
    final page = File(
      'lib/modules/live_room/live_room_page.dart',
    ).readAsStringSync();
    final placeholderBranches = RegExp(
      r'if \(controller\.showOfflineOverlay\)[\s\S]*?'
      r'var url = controller\.playUrls',
    ).firstMatch(page)!.group(0)!;
    final overlayBuilder = RegExp(
      r'Widget _buildOhosTopBarOverlay\([\s\S]*?'
      r'Widget _buildOhosTopBar\(',
    ).firstMatch(page)!.group(0)!;

    expect(
      '_buildOhosTopBarOverlay('.allMatches(placeholderBranches),
      hasLength(2),
    );
    expect(placeholderBranches, isNot(contains('_buildOhosTopBar(context)')));
    expect(overlayBuilder, contains('return AnimatedPositioned('));
    expect(overlayBuilder, contains('top: controlsVisible ? 0 :'));
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

  test('native position falls back to the last known clock, not to zero', () {
    final nativePlayer = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/VideoPlayer.ets',
    ).readAsStringSync();
    final getPosition = RegExp(
      r'getPosition\(\): number \{([\s\S]*?)\n  \}',
    ).firstMatch(nativePlayer)!.group(1)!;

    // AVPlayer reports -1 for live sources whose timeline it cannot expose.
    expect(getPosition, contains('if (currentTime >= 0)'));
    expect(getPosition, contains('this.lastKnownTimeMs'));
    // A genuine live-window rewind must still reach Flutter.
    expect(getPosition, isNot(contains('Math.max')));
    expect(
      nativePlayer,
      contains('this.lastKnownTimeMs = -1;'),
    );
  });

  test('native emits a heartbeat and distinguishes cache duration from percent',
      () {
    final nativePlayer = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/VideoPlayer.ets',
    ).readAsStringSync();

    expect(nativePlayer, contains('sendPlaybackTime(timeMs: number)'));
    expect(nativePlayer, contains('this.sendPlaybackTime(time)'));
    expect(nativePlayer, contains('"playbackTime"'));
    expect(nativePlayer, contains('"cachedDuration"'));
    expect(nativePlayer, contains('"bufferingPercent"'));
    // A 0..100 percent must not be handed to video_player as milliseconds.
    expect(nativePlayer, contains('event.set("percent", bufferingPosition)'));
    // High-frequency telemetry must not queue up while Flutter is detached.
    expect(
      nativePlayer,
      contains("this.eventSink?.hasDelegate() !== true"),
    );
  });

  test('native stale guards cover the time and buffer callbacks', () {
    final nativePlayer = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/VideoPlayer.ets',
    ).readAsStringSync();
    final timeUpdate = RegExp(
      r'Events\.TIME_UPDATE, \(time: number\) => \{([\s\S]*?)\n    \}\);',
    ).firstMatch(nativePlayer)!.group(1)!;

    expect(timeUpdate, contains('this.disposed || this.avPlayer !== boundPlayer'));
    expect(timeUpdate, contains('this.lastKnownTimeMs = time;'));
  });

  test('plugin forwards heartbeat and cache telemetry on a side channel', () {
    final plugin = File(
      'third_party/video_player_ohos/lib/src/ohos_video_player.dart',
    ).readAsStringSync();

    expect(plugin, contains('class OhosPlaybackTelemetryEvent'));
    expect(plugin, contains('enum OhosPlaybackTelemetryKind'));
    expect(plugin, contains('playbackTelemetryEvents'));
    expect(plugin, contains("case 'playbackTime':"));
    expect(plugin, contains("case 'cachedDuration':"));
    expect(plugin, contains("case 'bufferingPercent':"));
  });

  test('OHOS health sample carries the native cache depth', () {
    final player = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();

    expect(player, contains('recordOhosDemuxerCacheDuration'));
    expect(player, contains('demuxerCacheSeconds: ohosCacheSeconds'));
  });

  test('OHOS degrade uses the evidence gate instead of pure edge counting', () {
    final room = File(
      'lib/modules/live_room/live_room_controller.dart',
    ).readAsStringSync();

    expect(room, contains('_ohosDegradeEvidence.update('));
    expect(room, contains('_ohosDegradeEvidence.beginWarmup('));
    expect(room, contains('_ohosDegradeEvidence.reset()'));
    // Non-OHOS platforms must keep the original tracker.
    expect(room, contains('_autoQualityBufferTracker.update('));
  });

  test('OHOS healthy playback and stall checks fall back to the heartbeat', () {
    final room = File(
      'lib/modules/live_room/live_room_controller.dart',
    ).readAsStringSync();

    expect(room, contains('_ohosHeartbeatLooksAlive(now)'));
    expect(room, contains('updateOhosTelemetryForGeneration'));
    expect(room, contains('_ohosLastHeartbeatAt = null;'));
    expect(
      room,
      isNot(contains('_lastOhosPlaybackPosition <= Duration.zero')),
    );
  });

  test('a frozen timeline with live heartbeats is not a stall', () {
    final startedAt = DateTime(2026, 7, 14, 12);
    final value = _value(
      position: const Duration(seconds: 30),
      playing: true,
    );

    expect(
      detectOhosPlaybackHealthIssue(
        value: value,
        now: startedAt.add(const Duration(minutes: 5)),
        bufferingSince: null,
        lastProgressAt: startedAt,
        hasObservedProgress: false,
        lastHeartbeatAt: startedAt.add(const Duration(minutes: 5)),
        hasObservedHeartbeat: true,
        monitoringSince: startedAt,
      ),
      isNull,
    );
  });

  test('a silent heartbeat is a stall once the timeline is unavailable', () {
    final startedAt = DateTime(2026, 7, 14, 12);
    final value = _value(
      position: const Duration(seconds: 30),
      playing: true,
    );

    expect(
      detectOhosPlaybackHealthIssue(
        value: value,
        now: startedAt.add(const Duration(seconds: 40)),
        bufferingSince: null,
        lastProgressAt: startedAt,
        hasObservedProgress: false,
        lastHeartbeatAt: startedAt.add(const Duration(seconds: 30)),
        hasObservedHeartbeat: true,
        monitoringSince: startedAt,
      ),
      OhosPlaybackHealthIssue.playbackStall,
    );
  });

  test('an advancing timeline outranks a silent heartbeat', () {
    final progressedAt = DateTime(2026, 7, 14, 12);
    final value = _value(
      position: const Duration(seconds: 30),
      playing: true,
    );

    expect(
      detectOhosPlaybackHealthIssue(
        value: value,
        now: progressedAt.add(const Duration(seconds: 5)),
        bufferingSince: null,
        lastProgressAt: progressedAt,
        hasObservedProgress: true,
        lastHeartbeatAt: progressedAt.subtract(const Duration(minutes: 2)),
        hasObservedHeartbeat: true,
        monitoringSince: progressedAt.subtract(const Duration(minutes: 3)),
      ),
      isNull,
    );
  });

  test('no timeline and no heartbeat reports unobservable, never a stall', () {
    final startedAt = DateTime(2026, 7, 14, 12);
    final value = _value(
      position: Duration.zero,
      playing: true,
    );

    expect(
      detectOhosPlaybackHealthIssue(
        value: value,
        now: startedAt.add(const Duration(seconds: 19)),
        bufferingSince: null,
        lastProgressAt: startedAt,
        hasObservedProgress: false,
        monitoringSince: startedAt,
      ),
      isNull,
    );
    expect(
      detectOhosPlaybackHealthIssue(
        value: value,
        now: startedAt.add(const Duration(minutes: 10)),
        bufferingSince: null,
        lastProgressAt: startedAt,
        hasObservedProgress: false,
        monitoringSince: startedAt,
      ),
      OhosPlaybackHealthIssue.playbackUnobservable,
    );
  });

  test('buffering timeout still fires without any liveness signal', () {
    final startedAt = DateTime(2026, 7, 14, 12);
    final value = _value(position: Duration.zero, buffering: true);

    expect(
      detectOhosPlaybackHealthIssue(
        value: value,
        now: startedAt.add(const Duration(seconds: 8)),
        bufferingSince: startedAt,
        lastProgressAt: startedAt,
        hasObservedProgress: false,
        monitoringSince: startedAt,
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

  test('cache telemetry cannot masquerade as a native heartbeat', () {
    final player = File(
      'lib/modules/live_room/player/ohos_video_player.dart',
    ).readAsStringSync();

    // 缓存事件不带 heartbeatAt。否则"缓冲还在报深度"会被当成
    // "播放器还活着"，看门狗永远不开火。
    expect(player, contains('heartbeatAt: _lastHeartbeatAt,'));
    expect(player, isNot(contains('heartbeatAt: _lastHeartbeatAt ?? now')));
    expect(player, contains('final DateTime? heartbeatAt;'));

    final controller = File(
      'lib/modules/live_room/live_room_controller.dart',
    ).readAsStringSync();
    final start = controller.indexOf(
      'void updateOhosTelemetryForGeneration(',
    );
    final end = controller.indexOf(
      'void updateOhosVideoStateForGeneration(',
      start,
    );
    final method = controller.substring(start, end);

    expect(start, greaterThanOrEqualTo(0));
    expect(method, contains('final heartbeatAt = telemetry.heartbeatAt;'));
    expect(method, contains('if (heartbeatAt != null)'));
    // 心跳缺失时不得把 _ohosLastHeartbeatAt 写成 null 之外的值。
    final heartbeatAssignment = method.indexOf(
      '_ohosLastHeartbeatAt = heartbeatAt;',
    );
    final nullCheck = method.indexOf('if (heartbeatAt != null)');
    expect(heartbeatAssignment, greaterThan(nullCheck));
  });

  test('OHOS reconnects settle on a native playback confirmation', () {
    final controller = File(
      'lib/modules/live_room/live_room_controller.dart',
    ).readAsStringSync();

    // 三条确认路径：initialized/首帧、首帧回调、心跳兜底。
    expect(
      '_confirmOhosReconnect('.allMatches(controller).length,
      greaterThanOrEqualTo(4),
    );
    // 超时兜底必须存在，否则确认信号不来时这次重连会被静默丢掉。
    expect(controller, contains('flushIfExpired('));
    // 换房与销毁都要清掉待确认记录与超时定时器。
    expect(
      '_ohosReconnectConfirmation.reset();'.allMatches(controller).length,
      2,
    );
    expect(
      '_ohosReconnectConfirmationTimer?.cancel();'.allMatches(controller).length,
      greaterThanOrEqualTo(3),
    );
    // 两处重开记账点都不再按平台跳过。
    expect(controller, isNot(contains('recordedReason != null && !Utils.isOhos')));
    expect(
      controller,
      isNot(contains('!Utils.isOhos &&\n          automaticReconnectReason')),
    );
  });

  test('endpoint reachability reuses the diagnose probe and expires', () {
    final player = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();

    // 复用自动诊断已付出的探测，不新开探测循环：健康采样是每秒一次，
    // 一次探测最坏要几秒。
    expect(
      'NetworkDiagnoseService.diagnosePlaybackUrl('.allMatches(player).length,
      1,
    );
    expect(player, contains('recordPlaybackEndpointReachable('));
    expect(player, contains('playbackResult.lost < playbackResult.samples'));
    // 结论有有效期，且与探测冷却对齐：一个过期的"不可达"会压制评估器的
    // catchupCacheDrain 归因，窗口越长误判机会越大。
    expect(
      player,
      contains('endpointReachabilityTtl = Duration(seconds: 30)'),
    );
    expect(player, contains('resetPlaybackEndpointReachable();'));
  });
}
