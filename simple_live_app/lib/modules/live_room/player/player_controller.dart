import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:auto_orientation_v2/auto_orientation_v2.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/custom_throttle.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/modules/live_room/live_room_auto_quality_buffer_tracker.dart';
import 'package:simple_live_app/modules/live_room/player/player_volume_session_policy.dart';
import 'package:simple_live_app/services/background_playback_service.dart';
import 'package:simple_live_app/services/live_latency_telemetry_service.dart';
import 'package:simple_live_app/services/live_link_health_collector.dart';
import 'package:simple_live_app/services/live_link_health_media_kit_adapter.dart';
import 'package:simple_live_app/services/live_link_health_models.dart';
import 'package:simple_live_app/services/live_link_health_tracker.dart';
import 'package:simple_live_app/services/mpv_live_latency_chase_service.dart';
import 'package:simple_live_app/services/mpv_live_latency_chase_sampling_loop.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';
import 'package:simple_live_app/services/ohos_pip_service.dart';
import 'package:simple_live_app/services/playback_display_coordinator.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:window_manager/window_manager.dart';
import 'package:video_player/video_player.dart';

const _ohosMediaChannel = MethodChannel('simple_live/ohos_media');

class _DanmakuReplayEntry {
  final String message;
  final Color color;
  final List<String>? imageUrls;
  final List<DanmakuContentPart>? parts;
  final DateTime visibleFrom;
  final DateTime visibleUntil;

  const _DanmakuReplayEntry({
    required this.message,
    required this.color,
    this.imageUrls,
    this.parts,
    required this.visibleFrom,
    required this.visibleUntil,
  });

  bool isVisibleAt(DateTime now) {
    return !now.isBefore(visibleFrom) && now.isBefore(visibleUntil);
  }
}

const int _kDanmakuReplayLimit = 300;

mixin PlayerMixin {
  bool _playerInitialized = false;
  GlobalKey<VideoState> globalPlayerKey = GlobalKey<VideoState>();
  GlobalKey globalDanmuKey = GlobalKey();
  GlobalKey ohosScreenshotKey = GlobalKey();
  PlaybackDisplayLease? _playbackDisplayLease;

  void initPlaybackDisplayLease() {
    _playbackDisplayLease ??= PlaybackDisplayCoordinator.instance.acquire(
      debugLabel: 'single-live-room',
    );
  }

  void _setKeepScreenAwake(bool enabled) {
    _playbackDisplayLease?.setKeepScreenAwake(enabled);
  }

  void setPlaybackKeepScreenAwake(bool enabled) {
    _setKeepScreenAwake(enabled);
  }

  Future<void> releasePlaybackDisplayLease() async {
    final displayLease = _playbackDisplayLease;
    _playbackDisplayLease = null;
    displayLease?.dispose();
    await PlaybackDisplayCoordinator.instance.settle();
  }

  /// media_kit 播放器实例。
  ///
  /// OHOS 上不初始化 media_kit（见 `main.dart` 跳过 `MediaKit.ensureInitialized()`），
  /// 播放走 [ohosVideoController]。因此这里只在非 OHOS 平台惰性构造，
  /// 通过 [player] getter 访问以便在缺少平台守卫时给出明确报错。
  late final Player _mpvPlayer = Player(
    configuration: PlayerConfiguration(
      title: "Simple Live Player",
      logLevel: AppSettingsController.instance.logEnable.value
          ? MPVLogLevel.info
          // Audio underruns are emitted by libmpv at warning level.
          : MPVLogLevel.warn,
    ),
  );

  /// 播放器实例
  ///
  /// 在 OHOS 上访问会抛出 [StateError]，提示调用点缺少 `Utils.isOhos` 守卫。
  /// 这样可以避免在未初始化 media_kit 的情况下构造 mpv 实例导致的原生崩溃。
  Player get player {
    if (Utils.isOhos) {
      throw StateError(
        'media_kit player 在 OHOS 上不可用：该平台使用 video_player'
        '（ohosVideoController）播放。此调用点缺少 Utils.isOhos 守卫。',
      );
    }
    return _mpvPlayer;
  }

  /// 当前平台是否存在可用的 media_kit 播放器。
  bool get hasMpvPlayer => !Utils.isOhos;

  /// Safe, signature-free target used by shadow health logs.
  String get liveLinkHealthTarget => 'unknown';

  late final MpvLiveLatencyChaseService _liveLatencyChaser =
      MpvLiveLatencyChaseService(
    writeSpeed: _writeLiveLatencyChaseSpeed,
    readSpeed: _readLiveLatencyChaseSpeed,
    onWriteError: (error) => Log.d('live latency chase speed skipped: $error'),
  );
  late final MpvLiveLatencyChaseSamplingLoop _liveLatencyChaseSamplingLoop =
      MpvLiveLatencyChaseSamplingLoop(
    sample: _sampleLivePlaybackLightweight,
    nextInterval: _nextLivePlaybackSampleInterval,
    onError: (error) =>
        Log.d('live latency chase cache sample skipped: $error'),
  );
  final LiveLinkHealthShadowCollector _liveLinkHealthCollector =
      LiveLinkHealthShadowCollector(
    tracker: LiveLinkHealthTracker(
      capabilities: LiveLinkHealthCapabilities(
        audioUnderrunEvents: !Utils.isOhos,
        // OHOS currently exposes only a widget rebuild request here, not a
        // reliable async playback-success callback. Report the metric as
        // unsupported instead of presenting a misleading zero reconnects.
        automaticReconnectEvents: !Utils.isOhos,
      ),
    ),
  );
  StreamSubscription<bool>? _livePlaybackBufferingSubscription;
  int? _livePlaybackSamplingGeneration;
  int? _liveLatencyChaseServiceGeneration;
  DateTime? _nextLivePlaybackHealthSampleAt;
  DateTime? _lastLiveLatencyChaseAudioUnderrunAt;
  DateTime? _latestLivePlaybackCacheSampledAt;
  double? _latestLivePlaybackCacheDurationSeconds;
  bool? _livePlaybackBuffering;
  String? _livePlaybackSource;
  LiveStreamProtocol? _livePlaybackProtocol;
  int _livePlaybackGeneration = 0;
  int _liveLatencyChaseActivationRevision = 0;
  bool _liveLatencyChaseSuspended = true;
  bool _liveLatencyChaseAppActive = true;
  bool _liveLatencyChaseUserPaused = false;

  LiveLinkHealthSnapshot? get currentLiveLinkHealthSnapshot =>
      _liveLinkHealthCollector.snapshot();

  MpvTelemetryValue get latestLivePlaybackCacheTelemetry {
    final sampledAt = _latestLivePlaybackCacheSampledAt;
    if (sampledAt == null ||
        DateTime.now().difference(sampledAt) > const Duration(seconds: 3)) {
      return const MpvTelemetryValue.unsupported();
    }
    return MpvTelemetryValue.parse(_latestLivePlaybackCacheDurationSeconds);
  }

  bool get _isLiveLatencyChaseActivationAllowed =>
      _liveLatencyChaseAppActive && !_liveLatencyChaseUserPaused;

  bool? get currentLiveLinkHealthBuffering => _livePlaybackBuffering;

  Future<void> _writeLiveLatencyChaseSpeed(double speed) async {
    final platform = player.platform;
    if (platform is! NativePlayer) {
      return;
    }
    final dynamic native = platform;
    await native.setProperty('speed', speed.toStringAsFixed(3));
  }

  Future<double?> _readLiveLatencyChaseSpeed() async {
    final platform = player.platform;
    if (platform is! NativePlayer) {
      return null;
    }
    try {
      final dynamic native = platform;
      final dynamic value = await native.getProperty('speed');
      final speed = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      return speed != null && speed.isFinite && speed > 0 ? speed : null;
    } catch (_) {
      return null;
    }
  }

  /// 初始化播放器并设置静态 mpv 参数。
  ///
  /// OHOS 上没有 media_kit，直接返回；播放由 [ohosVideoController] 负责。
  Future<void> initializePlayer() async {
    if (Utils.isOhos || _playerInitialized) {
      return;
    }
    _playerInitialized = true;
    await MpvOptionsService.applyToPlayer(player);
    final nativePlayer = player.platform as NativePlayer;
    // 设置音频输出驱动
    if (AppSettingsController.instance.customPlayerOutput.value) {
      if (player.platform is NativePlayer) {
        await (player.platform as dynamic).setProperty(
          'ao',
          AppSettingsController.instance.audioOutputDriver.value,
        );
      }
    }
    // media_kit 仓库更新导致的问题，临时解决办法
    if (Platform.isAndroid) {
      await nativePlayer.setProperty('force-seekable', 'yes');
    }
  }

  Future<void> startLivePlaybackLightweightSampling({
    required String source,
    DateTime? openedAt,
  }) async {
    final generation = _livePlaybackGeneration;
    final canonicalSource = canonicalizeLivePlaybackSource(source);
    if (canonicalSource.isEmpty || !_liveLinkHealthCollector.isActive) {
      return;
    }
    final activationRevision = ++_liveLatencyChaseActivationRevision;
    if (_livePlaybackSource != canonicalSource) {
      _lastLiveLatencyChaseAudioUnderrunAt = null;
    }
    _livePlaybackSource = canonicalSource;
    _livePlaybackProtocol = classifyLiveStreamProtocol(source);
    _liveLatencyChaseSuspended = !_isLiveLatencyChaseActivationAllowed;
    final now = openedAt ?? DateTime.now();
    if (!Utils.isOhos) {
      await _liveLatencyChaser.start(
        latencyMode: AppSettingsController.instance.mpvLiveLatencyMode.value,
        protocol: _livePlaybackProtocol!,
        startedAt: now,
      );
      if (generation == _livePlaybackGeneration &&
          canonicalSource == _livePlaybackSource &&
          activationRevision == _liveLatencyChaseActivationRevision &&
          _isLiveLatencyChaseActivationAllowed) {
        _liveLatencyChaseServiceGeneration = _liveLatencyChaser.generation;
      }
    }
    if (generation != _livePlaybackGeneration ||
        canonicalSource != _livePlaybackSource) {
      return;
    }
    _liveLinkHealthCollector.addEvent(
      LiveLinkHealthEvent(
        generation: generation,
        occurredAt: now,
        type: LiveLinkEventType.streamOpened,
      ),
    );
    if (!Utils.isOhos) {
      _livePlaybackBufferingSubscription ??=
          player.stream.buffering.listen((buffering) {
        _recordLivePlaybackBuffering(buffering, at: DateTime.now());
        if (buffering) {
          unawaited(
            protectLiveLatencyChase(
              MpvLiveLatencyProtectionReason.buffering,
            ),
          );
        }
      });
    }
    if (activationRevision == _liveLatencyChaseActivationRevision &&
        _isLiveLatencyChaseActivationAllowed) {
      _liveLatencyChaseSuspended = false;
      _nextLivePlaybackHealthSampleAt = now;
      _liveLatencyChaseSamplingLoop.start();
    }
  }

  Duration? _nextLivePlaybackSampleInterval() {
    if (_liveLatencyChaseSuspended ||
        _livePlaybackSource == null ||
        !_liveLinkHealthCollector.isActive) {
      return null;
    }
    return MpvLiveLatencyChaseSamplingLoop.nextDelay(
      chaseInterval:
          Utils.isOhos ? null : _liveLatencyChaser.recommendedSampleInterval,
      healthDueAt: _nextLivePlaybackHealthSampleAt,
    );
  }

  Future<void> _sampleLivePlaybackLightweight() async {
    final generation = _livePlaybackGeneration;
    final source = _livePlaybackSource;
    final chaseGeneration = _liveLatencyChaseServiceGeneration;
    if (_liveLatencyChaseSuspended ||
        _livePlaybackSamplingGeneration != null ||
        source == null) {
      return;
    }
    _livePlaybackSamplingGeneration = generation;
    try {
      final sampledAt = DateTime.now();
      final healthDueAt = _nextLivePlaybackHealthSampleAt;
      final shouldCollectHealth =
          healthDueAt == null || !sampledAt.isBefore(healthDueAt);
      if (shouldCollectHealth) {
        _nextLivePlaybackHealthSampleAt =
            sampledAt.add(LiveLinkHealthTracker.sampleInterval);
      }
      if (Utils.isOhos) {
        if (!shouldCollectHealth) return;
        final controller = _ohosVideoController;
        if (controller == null) {
          return;
        }
        final value = controller.value;
        _recordLivePlaybackBuffering(
          value.isBuffering || !value.isInitialized,
          at: sampledAt,
        );
        _recordLiveLinkHealthSample(
          LiveLinkHealthSample(
            generation: generation,
            sampledAt: sampledAt,
            position: value.position,
            playing: value.isPlaying,
            buffering: value.isBuffering || !value.isInitialized,
            playbackSpeed: value.playbackSpeed,
            streamActive:
                value.isInitialized && (value.isPlaying || value.isBuffering),
          ),
        );
        return;
      }

      final state = player.state;
      final playlist = state.playlist;
      if (playlist.medias.isEmpty ||
          playlist.index < 0 ||
          playlist.index >= playlist.medias.length) {
        return;
      }
      final dynamic media = playlist.medias[playlist.index];
      final currentSource = canonicalizeLivePlaybackSource(
        media.uri?.toString() ?? '',
      );
      if (currentSource != source) {
        return;
      }
      final cacheDurationFuture = sampleMpvDemuxerCacheDuration(player);
      final throughputFuture =
          shouldCollectHealth ? sampleMpvLiveHealthThroughput(player) : null;
      final cacheDurationSeconds = await cacheDurationFuture;
      final throughput = await throughputFuture;
      if (generation != _livePlaybackGeneration ||
          source != _livePlaybackSource) {
        return;
      }
      _latestLivePlaybackCacheSampledAt = sampledAt;
      _latestLivePlaybackCacheDurationSeconds = cacheDurationSeconds;
      if (shouldCollectHealth && throughput != null) {
        _recordLiveLinkHealthSample(
          LiveLinkHealthSample(
            generation: generation,
            sampledAt: sampledAt,
            position: state.position,
            playing: state.playing,
            buffering: state.buffering,
            playbackSpeed: _liveLatencyChaser.currentSpeed,
            streamActive: state.playing || state.buffering,
            demuxerCacheSeconds: cacheDurationSeconds,
            receiveBytesPerSecond: throughput.receiveBytesPerSecond,
            estimatedMediaBitsPerSecond: throughput.estimatedMediaBitsPerSecond,
          ),
        );
      }
      if (!_liveLatencyChaseSuspended &&
          state.playing &&
          chaseGeneration != null &&
          chaseGeneration == _liveLatencyChaseServiceGeneration) {
        await _liveLatencyChaser.observe(
          cacheDurationSeconds: cacheDurationSeconds,
          isBuffering: state.buffering,
          sampledAt: sampledAt,
          generation: chaseGeneration,
        );
      }
    } catch (error) {
      Log.d('live playback lightweight sample skipped: $error');
      if (!Utils.isOhos &&
          !_liveLatencyChaseSuspended &&
          generation == _livePlaybackGeneration &&
          source == _livePlaybackSource &&
          chaseGeneration == _liveLatencyChaseServiceGeneration) {
        await protectLiveLatencyChase(
          MpvLiveLatencyProtectionReason.telemetryUnavailable,
        );
      }
    } finally {
      if (_livePlaybackSamplingGeneration == generation) {
        _livePlaybackSamplingGeneration = null;
      }
    }
  }

  Future<void> protectLiveLatencyChase(
    MpvLiveLatencyProtectionReason reason, {
    DateTime? sampledAt,
  }) async {
    if (Utils.isOhos) return;
    if (reason == MpvLiveLatencyProtectionReason.audioUnderrun) {
      final now = sampledAt ?? DateTime.now();
      final previous = _lastLiveLatencyChaseAudioUnderrunAt;
      if (previous != null &&
          now.difference(previous) < const Duration(milliseconds: 500)) {
        return;
      }
      _lastLiveLatencyChaseAudioUnderrunAt = now;
    }
    final chaseGeneration = _liveLatencyChaseServiceGeneration;
    if (chaseGeneration == null) return;
    await _liveLatencyChaser.protect(
      sampledAt: sampledAt,
      reason: reason,
      generation: chaseGeneration,
    );
  }

  Future<void> suspendLiveLatencyChase(
    MpvLiveLatencyProtectionReason reason, {
    DateTime? sampledAt,
  }) async {
    if (reason == MpvLiveLatencyProtectionReason.lifecycleInterrupted) {
      _liveLatencyChaseAppActive = false;
    } else if (reason == MpvLiveLatencyProtectionReason.userPaused) {
      _liveLatencyChaseUserPaused = true;
    }
    _liveLatencyChaseActivationRevision += 1;
    if (_liveLatencyChaseSuspended) {
      _liveLatencyChaseSamplingLoop.stop();
      return;
    }
    _liveLatencyChaseSuspended = true;
    _liveLatencyChaseSamplingLoop.stop();
    await protectLiveLatencyChase(reason, sampledAt: sampledAt);
  }

  Future<void> resumeLiveLatencyChase({bool appForegrounded = false}) {
    if (appForegrounded) {
      _liveLatencyChaseAppActive = true;
    } else {
      _liveLatencyChaseUserPaused = false;
    }
    if (!_isLiveLatencyChaseActivationAllowed) {
      return Future<void>.value();
    }
    if (!_liveLatencyChaseSuspended) {
      return Future<void>.value();
    }
    final activationRevision = ++_liveLatencyChaseActivationRevision;
    return _resumeLiveLatencyChase(activationRevision);
  }

  Future<void> _resumeLiveLatencyChase(int activationRevision) async {
    if (!_liveLatencyChaseSuspended) return;
    final generation = _livePlaybackGeneration;
    final source = _livePlaybackSource;
    final protocol = _livePlaybackProtocol;
    if (source == null ||
        protocol == null ||
        !_isLiveLatencyChaseActivationAllowed ||
        !_liveLinkHealthCollector.isActive) {
      return;
    }
    if (!Utils.isOhos) {
      await _liveLatencyChaser.start(
        latencyMode: AppSettingsController.instance.mpvLiveLatencyMode.value,
        protocol: protocol,
        startedAt: DateTime.now(),
      );
      if (generation != _livePlaybackGeneration ||
          source != _livePlaybackSource ||
          activationRevision != _liveLatencyChaseActivationRevision ||
          !_liveLatencyChaseSuspended ||
          !_isLiveLatencyChaseActivationAllowed) {
        return;
      }
      _liveLatencyChaseServiceGeneration = _liveLatencyChaser.generation;
    }
    if (generation != _livePlaybackGeneration ||
        source != _livePlaybackSource ||
        activationRevision != _liveLatencyChaseActivationRevision ||
        !_liveLatencyChaseSuspended ||
        !_isLiveLatencyChaseActivationAllowed) {
      return;
    }
    _liveLatencyChaseSuspended = false;
    _nextLivePlaybackHealthSampleAt = DateTime.now();
    _liveLatencyChaseSamplingLoop.start();
  }

  void _recordLiveLinkHealthSample(LiveLinkHealthSample sample) {
    final summary = _liveLinkHealthCollector.addSample(sample);
    if (summary != null) {
      Log.writeLog(summary);
    }
  }

  void _recordLivePlaybackBuffering(bool buffering, {required DateTime at}) {
    if (_livePlaybackBuffering == buffering) {
      return;
    }
    _livePlaybackBuffering = buffering;
    recordLiveLinkHealthEvent(
      buffering
          ? LiveLinkEventType.bufferingStarted
          : LiveLinkEventType.bufferingEnded,
      at: at,
    );
  }

  void recordLiveLinkHealthEvent(
    LiveLinkEventType type, {
    DateTime? at,
    LiveReconnectReason? reconnectReason,
    bool? reconnectHostChanged,
    Duration? reconnectRecoveryDuration,
  }) {
    _liveLinkHealthCollector.addEvent(
      LiveLinkHealthEvent(
        generation: _livePlaybackGeneration,
        occurredAt: at ?? DateTime.now(),
        type: type,
        reconnectReason: reconnectReason,
        reconnectHostChanged: reconnectHostChanged,
        reconnectRecoveryDuration: reconnectRecoveryDuration,
      ),
    );
  }

  Future<void> _cancelLivePlaybackSamplingInfrastructure() async {
    _liveLatencyChaseSamplingLoop.stop();
    _nextLivePlaybackHealthSampleAt = null;
    await _livePlaybackBufferingSubscription?.cancel();
    _livePlaybackBufferingSubscription = null;
    _livePlaybackBuffering = null;
  }

  Future<void> resetLiveLatencyChase() async {
    final chaseGeneration = _liveLatencyChaseServiceGeneration;
    _liveLatencyChaseActivationRevision += 1;
    _liveLatencyChaseSuspended = true;
    _livePlaybackGeneration += 1;
    _liveLatencyChaseServiceGeneration = null;
    _lastLiveLatencyChaseAudioUnderrunAt = null;
    _latestLivePlaybackCacheSampledAt = null;
    _latestLivePlaybackCacheDurationSeconds = null;
    await _cancelLivePlaybackSamplingInfrastructure();
    _livePlaybackSource = null;
    _livePlaybackProtocol = null;
    _liveLinkHealthCollector.startGeneration(
      generation: _livePlaybackGeneration,
      target: liveLinkHealthTarget,
    );
    if (!Utils.isOhos) {
      if (chaseGeneration != null) {
        await _liveLatencyChaser.protect(
          reason: MpvLiveLatencyProtectionReason.sourceChanged,
          generation: chaseGeneration,
        );
      }
      await _liveLatencyChaser.reset();
    }
  }

  Future<void> stopLiveLatencyChase() async {
    _liveLatencyChaseActivationRevision += 1;
    _liveLatencyChaseSuspended = true;
    _livePlaybackGeneration += 1;
    _liveLatencyChaseServiceGeneration = null;
    _lastLiveLatencyChaseAudioUnderrunAt = null;
    _latestLivePlaybackCacheSampledAt = null;
    _latestLivePlaybackCacheDurationSeconds = null;
    await _cancelLivePlaybackSamplingInfrastructure();
    _livePlaybackSource = null;
    _livePlaybackProtocol = null;
    _liveLinkHealthCollector.stop();
    if (!Utils.isOhos) {
      await _liveLatencyChaser.stop();
    }
  }

  late final VideoController _mpvVideoController = VideoController(
    _mpvPlayer,
    configuration: MpvOptionsService.videoControllerConfiguration(),
  );

  /// 视频控制器
  ///
  /// 与 [player] 同理，OHOS 上访问会抛出 [StateError]。
  VideoController get videoController {
    if (Utils.isOhos) {
      throw StateError(
        'media_kit videoController 在 OHOS 上不可用：该平台使用 video_player'
        '（ohosVideoController）播放。此调用点缺少 Utils.isOhos 守卫。',
      );
    }
    return _mpvVideoController;
  }

  VideoPlayerController? _ohosVideoController;
  final GlobalKey ohosPlayerWidgetKey =
      GlobalKey(debugLabel: 'ohos-native-player');
  final RxBool ohosPlaying = false.obs;
  final RxBool ohosBuffering = true.obs;
  final RxBool ohosScreenshotInProgress = false.obs;

  /// Native OHOS 0..1 mirror. Persisted 0..100 user intent remains
  /// [AppSettingsController.playerVolume] and is the source of truth.
  final RxDouble ohosVolume = 1.0.obs;
  final RxDouble ohosAspectRatio = (16 / 9).obs;
  final RxInt ohosScaleRevision = 0.obs;

  /// Whether the current source is actually taller than it is wide.
  final RxBool isVertical = false.obs;

  VideoPlayerController? get ohosVideoController => _ohosVideoController;

  void attachOhosVideoController(VideoPlayerController controller) {
    _ohosVideoController = controller;
    BackgroundPlaybackService.instance.attachOhosController(controller);
    updateOhosVideoState(controller.value);
    if (_livePlaybackSource != null && _liveLinkHealthCollector.isActive) {
      _liveLatencyChaseSamplingLoop.start();
    }
  }

  void detachOhosVideoController(VideoPlayerController controller) {
    if (identical(_ohosVideoController, controller)) {
      BackgroundPlaybackService.instance.detachOhosController(controller);
      _ohosVideoController = null;
      _liveLatencyChaseSamplingLoop.stop();
      ohosPlaying.value = false;
      ohosBuffering.value = false;
      _setKeepScreenAwake(false);
    }
  }

  void updateOhosVideoState(VideoPlayerValue value) {
    final wasPlaying = ohosPlaying.value;
    ohosPlaying.value = value.isPlaying;
    ohosBuffering.value = value.isBuffering || !value.isInitialized;
    _setKeepScreenAwake(value.isPlaying);
    if (value.aspectRatio > 0) {
      ohosAspectRatio.value = value.aspectRatio;
    }
    final size = value.size;
    if (value.isInitialized && size.width > 0 && size.height > 0) {
      isVertical.value = size.height > size.width;
    }
    if (Utils.isOhos && wasPlaying != value.isPlaying) {
      unawaited(_syncOhosBackgroundPlayback(value.isPlaying));
    }
  }

  Future<void> _syncOhosBackgroundPlayback(bool playing) async {
    if (playing &&
        AppSettingsController.instance.allowBackgroundPlayback.value) {
      await BackgroundPlaybackService.instance.start();
    } else {
      await BackgroundPlaybackService.instance.stop();
    }
  }

  Future<void> toggleOhosPlayback() async {
    final controller = _ohosVideoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await suspendLiveLatencyChase(
        MpvLiveLatencyProtectionReason.userPaused,
      );
      await controller.pause();
      recordLiveLinkHealthEvent(LiveLinkEventType.playbackPausedByUser);
    } else {
      await controller.play();
      await resumeLiveLatencyChase();
      recordLiveLinkHealthEvent(LiveLinkEventType.playbackResumedByUser);
    }
    updateOhosVideoState(controller.value);
  }
}

mixin PlayerStateMixin on PlayerMixin {
  bool _playerClosing = false;
  bool _desktopVolumeDragging = false;

  ///音量控制条计时器
  Timer? hidevolumeTimer;

  /// 是否进入桌面端小窗
  RxBool smallWindowState = false.obs;

  /// 是否显示弹幕
  RxBool showDanmakuState = false.obs;

  RxBool mutedState = false.obs;
  double _volumeBeforeMute = 0.0;

  void onPlayerWindowModeExited() {}

  /// 是否显示控制器
  RxBool showControlsState = false.obs;

  RxBool hideMouseCursorState = false.obs;

  /// 是否显示设置窗口
  RxBool showSettingState = false.obs;

  /// 是否显示弹幕设置窗口
  RxBool showDanmakuSettingState = false.obs;

  /// 是否处于锁定控制器状态
  RxBool lockControlsState = false.obs;
  RxBool showLockEdgeState = false.obs;

  /// 是否处于全屏状态
  RxBool fullScreenState = false.obs;
  RxBool ohosFullscreenTransition = false.obs;

  /// 鸿蒙全屏过渡期间收到退出请求时置位，待过渡结束后立即消费执行退出。
  /// 避免过渡中 exitFull 直接返回导致 fullScreenState/方向/系统栏残留。
  bool _pendingExitFullscreen = false;

  bool get showOhosFullscreenSurface =>
      Utils.isOhos && (fullScreenState.value || ohosFullscreenTransition.value);

  /// 显示手势Tip
  RxBool showGestureTip = false.obs;

  /// 手势Tip文本
  RxString gestureTipText = "".obs;

  /// 显示提示底部Tip
  RxBool showBottomTip = false.obs;

  /// 提示底部Tip文本
  RxString bottomTipText = "".obs;

  /// 自动隐藏控制器计时器
  Timer? hideControlsTimer;
  bool _controlsAutoHidePaused = false;

  /// 自动隐藏鼠标光标计时器
  Timer? hideMouseCursorTimer;

  /// 自动隐藏提示计时器
  Timer? hideSeekTipTimer;

  RxInt danmakuViewVersion = 0.obs;

  var showQualites = false.obs;
  var showLines = false.obs;

  bool get useBottomSheetPlayerMenus =>
      (Platform.isAndroid || Platform.isIOS || Utils.isOhos) &&
      !fullScreenState.value;

  bool get desktopVolumeDragging => _desktopVolumeDragging;

  set desktopVolumeDragging(bool value) {
    _desktopVolumeDragging = value;
  }

  bool get isPlayerClosing => _playerClosing;

  /// 隐藏控制器
  void hideControls() {
    if (_controlsAutoHidePaused) {
      return;
    }
    showControlsState.value = false;
    hideControlsTimer?.cancel();
    hideMouseCursor();
  }

  void setLockState() {
    lockControlsState.value = !lockControlsState.value;
    showLockEdgeState.value = false;
    if (lockControlsState.value) {
      showControlsState.value = false;
    } else {
      showControlsState.value = true;
    }
  }

  /// 显示控制器
  void showControls() {
    showControlsState.value = true;
    showMouseCursor();
    resetHideControlsTimer();
    resetHideMouseCursorTimer();
  }

  /// 显示鼠标光标
  void showMouseCursor() {
    if (!Platform.isWindows) {
      return;
    }
    hideMouseCursorTimer?.cancel();
    hideMouseCursorState.value = false;
  }

  /// 隐藏鼠标光标
  void hideMouseCursor() {
    if (!Platform.isWindows || _controlsAutoHidePaused) {
      return;
    }
    hideMouseCursorTimer?.cancel();
    hideMouseCursorState.value = true;
  }

  /// 开始隐藏控制器计时
  /// - 当点击控制器上时功能时需要重新计时
  void resetHideControlsTimer() {
    hideControlsTimer?.cancel();
    hideControlsTimer = null;
    if (_controlsAutoHidePaused) {
      return;
    }

    hideControlsTimer = Timer(
      const Duration(
        seconds: 5,
      ),
      hideControls,
    );
  }

  /// 开始隐藏鼠标光标计时
  void resetHideMouseCursorTimer() {
    if (!Platform.isWindows || _controlsAutoHidePaused) {
      return;
    }

    hideMouseCursorTimer?.cancel();
    hideMouseCursorTimer = Timer(
      const Duration(
        seconds: 5,
      ),
      hideMouseCursor,
    );
  }

  /// Keeps the player controls visible while an attached control is in use.
  void pauseControlsAutoHide() {
    _controlsAutoHidePaused = true;
    hideControlsTimer?.cancel();
    hideControlsTimer = null;
    hideMouseCursorTimer?.cancel();
    hideMouseCursorTimer = null;
    showControlsState.value = true;
    showMouseCursor();
  }

  /// Restarts a fresh countdown after the attached control is dismissed.
  void resumeControlsAutoHide() {
    if (!_controlsAutoHidePaused) {
      return;
    }
    _controlsAutoHidePaused = false;
    if (_playerClosing || !showControlsState.value || lockControlsState.value) {
      return;
    }
    resetHideControlsTimer();
    resetHideMouseCursorTimer();
  }

  void updateScaleMode() {
    if (Utils.isOhos) {
      ohosScaleRevision.value += 1;
      return;
    }
    var boxFit = BoxFit.contain;
    double? aspectRatio;
    if (player.state.width != null && player.state.height != null) {
      aspectRatio = player.state.width! / player.state.height!;
    }

    if (AppSettingsController.instance.scaleMode.value == 0) {
      boxFit = BoxFit.contain;
    } else if (AppSettingsController.instance.scaleMode.value == 1) {
      boxFit = BoxFit.fill;
    } else if (AppSettingsController.instance.scaleMode.value == 2) {
      boxFit = BoxFit.cover;
    } else if (AppSettingsController.instance.scaleMode.value == 3) {
      boxFit = BoxFit.contain;
      aspectRatio = 16 / 9;
    } else if (AppSettingsController.instance.scaleMode.value == 4) {
      boxFit = BoxFit.contain;
      aspectRatio = 4 / 3;
    }
    globalPlayerKey.currentState?.update(
      aspectRatio: aspectRatio,
      fit: boxFit,
    );
  }
}
mixin PlayerDanmakuMixin on PlayerStateMixin {
  /// 弹幕控制器
  DanmakuController? danmakuController;
  final List<_DanmakuReplayEntry> _danmakuReplayHistory = [];
  bool _danmakuReplayScheduled = false;

  void initDanmakuController(DanmakuController e) {
    danmakuController = e;
    // danmakuController?.updateOption(
    //   DanmakuOption(
    //     fontSize: AppSettingsController.instance.danmuSize.value,
    //     area: AppSettingsController.instance.danmuArea.value,
    //     duration: AppSettingsController.instance.danmuSpeed.value,
    //     opacity: AppSettingsController.instance.danmuOpacity.value,
    //     strokeWidth: AppSettingsController.instance.danmuStrokeWidth.value,
    //     fontWeight: FontWeight
    //         .values[AppSettingsController.instance.danmuFontWeight.value],
    //   ),
    // );
  }

  void updateDanmuOption(DanmakuOption? option) {
    if (danmakuController == null || option == null) return;
    danmakuController!.updateOption(option);
  }

  void disposeDanmakuController() {
    danmakuController?.clear();
    danmakuController = null;
  }

  void clearDanmakuReplayHistory() {
    _danmakuReplayHistory.clear();
  }

  void rememberDanmakuReplay(
    String message,
    Color color, {
    Duration delay = Duration.zero,
    List<String>? imageUrls,
    List<DanmakuContentPart>? parts,
  }) {
    var durationSeconds =
        AppSettingsController.instance.danmuSpeed.value.toInt();
    if (durationSeconds < 1) {
      durationSeconds = 1;
    }

    final visibleFrom = DateTime.now().add(delay);
    _danmakuReplayHistory.add(
      _DanmakuReplayEntry(
        message: message,
        color: color,
        imageUrls: imageUrls,
        parts: parts,
        visibleFrom: visibleFrom,
        visibleUntil: visibleFrom.add(Duration(seconds: durationSeconds)),
      ),
    );
    _pruneDanmakuReplayHistory();
  }

  void _pruneDanmakuReplayHistory([DateTime? now]) {
    final current = now ?? DateTime.now();
    _danmakuReplayHistory.removeWhere(
      (item) => !item.visibleUntil.isAfter(current),
    );
    if (_danmakuReplayHistory.length > _kDanmakuReplayLimit) {
      _danmakuReplayHistory.removeRange(
        0,
        _danmakuReplayHistory.length - _kDanmakuReplayLimit,
      );
    }
  }

  void _scheduleDanmakuReplay() {
    if (_danmakuReplayScheduled) {
      return;
    }
    _danmakuReplayScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _danmakuReplayScheduled = false;
      _replayDanmakuOverlay();
    });
  }

  void _replayDanmakuOverlay() {
    if (!showDanmakuState.value ||
        AppSettingsController.instance.danmuLineCount.value <= 0 ||
        danmakuController == null) {
      return;
    }
    final now = DateTime.now();
    _pruneDanmakuReplayHistory(now);
    for (final item in _danmakuReplayHistory) {
      if (!item.isVisibleAt(now)) {
        continue;
      }
      danmakuController?.addDanmaku(
        DanmakuContentItem(
          item.message,
          color: item.color,
          imageUrls: item.imageUrls,
          parts: item.parts,
        ),
      );
    }
  }

  void rebuildDanmakuView({bool clearCurrent = true}) {
    if (clearCurrent) {
      danmakuController?.clear();
    }
    globalDanmuKey = GlobalKey();
    danmakuViewVersion.value += 1;
    _scheduleDanmakuReplay();
  }

  void addDanmaku(List<DanmakuContentItem> items) {
    if (!showDanmakuState.value ||
        AppSettingsController.instance.danmuLineCount.value <= 0) {
      return;
    }
    for (var item in items) {
      danmakuController?.addDanmaku(item);
    }
  }
}
mixin PlayerSystemMixin on PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin {
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  final pip = Floating();
  StreamSubscription<PiPStatus>? _pipSubscription;
  StreamSubscription<bool>? _ohosPipSubscription;

  //final VolumeController volumeController = VolumeController();

  /// 初始化一些系统状态
  void initSystem() async {
    initPlaybackDisplayLease();
    if (Platform.isAndroid || Platform.isIOS) {
      VolumeController.instance.showSystemUI = false;
    }

    if (Utils.isOhos) {
      _ensureOhosPipStatusListener();
    }

    // 开始隐藏计时
    resetHideControlsTimer();

    // 进入全屏模式
    if (AppSettingsController.instance.autoFullScreen.value) {
      enterFullScreen();
    }
  }

  /// 释放一些系统状态
  Future resetSystem() async {
    _pipSubscription?.cancel();
    _ohosPipSubscription?.cancel();
    //pip.dispose();
    await releasePlaybackDisplayLease();

    await resetPreferredOrientation();
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Utils.isOhos) {
      // 亮度重置,桌面平台可能会报错,暂时不处理桌面平台的亮度
      try {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      } catch (e) {
        Log.logPrint(e);
      }
    }
  }

  /// 进入全屏
  Future<void> enterFullScreen() async {
    if (smallWindowState.value) {
      await exitSmallWindow();
      return;
    }
    if (Utils.isOhos) {
      if (ohosFullscreenTransition.value) {
        return;
      }
      // 开始新一轮进入全屏：清掉上次可能残留的待处理退出请求。
      _pendingExitFullscreen = false;
      ohosFullscreenTransition.value = true;
      // 立即切全屏布局，方向同步转：过渡期间画面在竖屏窗口里等比
      // letterbox（黑边），方向就绪后恢复横屏满屏。比"先转方向再全屏"
      // 响应更快（用户选择黑边过渡）。
      fullScreenState.value = true;
      showControls();
      await WidgetsBinding.instance.endOfFrame;
      unawaited(
        _runOhosSystemUiOperation(
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: [],
          ),
          "隐藏系统栏",
        ),
      );
      if (!isVertical.value) {
        // Observe the viewport directly. The platform method can acknowledge
        // the request later than the window actually rotates.
        unawaited(
          _runOhosSystemUiOperation(
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]),
            "切换横屏",
          ),
        );
        await _waitForOhosViewport(portrait: false);
      }
      ohosFullscreenTransition.value = false;
      // 过渡期间若有退出请求（如关闭直播间），此时立即接续执行完整退出，
      // 避免 fullScreenState/方向/系统栏停留残留。
      if (_pendingExitFullscreen) {
        _pendingExitFullscreen = false;
        await exitFull();
      }
    } else if (Platform.isAndroid || Platform.isIOS) {
      fullScreenState.value = true;
      // 开关开启时全屏总是横屏：iPad 竖屏系统强制显示状态栏，
      // 只有横屏才能可靠隐藏。默认关闭并跟随视频方向。
      if (!isVertical.value ||
          AppSettingsController.instance.fullScreenForceLandscape.value) {
        //横屏
        await setLandscapeOrientation();
      }
      await restoreFullScreenSystemUi();
    } else {
      await _serializeDesktopWindowModeTransition(() async {
        if (fullScreenState.value || smallWindowState.value) {
          return;
        }
        Log.d('Desktop fullscreen: enter start');
        try {
          _windowMaximizedBeforeFullScreen = await windowManager.isMaximized();
          await windowManager
              .setFullScreen(true)
              .timeout(const Duration(seconds: 2));
          await _waitForWindowsFullScreenState(true);
          // Let window_manager finish the native Win32 resize before moving
          // the Video widget into the fullscreen layout. Changing both at the
          // same time can stall the Windows texture/surface during a double
          // click transition.
          fullScreenState.value = true;
          await Future.delayed(const Duration(milliseconds: 32));
          Log.d('Desktop fullscreen: enter complete');
        } catch (e, stackTrace) {
          fullScreenState.value = false;
          try {
            await windowManager
                .setFullScreen(false)
                .timeout(const Duration(seconds: 2));
          } catch (rollbackError) {
            Log.d('Desktop fullscreen: enter rollback failed: $rollbackError');
          }
          Log.e('Desktop fullscreen: enter failed: $e', stackTrace);
        }
      });
    }
    //danmakuController?.clear();
  }

  /// 隐藏移动端系统栏。
  ///
  /// iOS 不支持 Android 的 immersiveSticky 语义，需要明确传入空 overlays。
  /// 该方法也会在 App 回到前台时重新调用，防止 iOS 恢复状态栏。
  Future<void> restoreFullScreenSystemUi() async {
    if ((!Platform.isAndroid && !Platform.isIOS) ||
        !fullScreenState.value ||
        smallWindowState.value ||
        isPlayerClosing) {
      return;
    }
    Log.d(
        'SystemUi: restoreFullScreenSystemUi enter fullScreen=${fullScreenState.value} smallWindow=${smallWindowState.value}');
    _playbackDisplayLease?.setImmersiveSystemUi(true);
    await PlaybackDisplayCoordinator.instance.settle();
    if (Platform.isIOS) {
      // iOS 横竖屏旋转/路由动画完成（约 300-400ms）后会重新应用系统栏
      // 样式，把之前的 hidden 覆盖掉。延迟多次重检（最长 3s），确保动画
      // 结束及系统 scene 重置后状态栏仍保持隐藏。
      for (final ms in const [250, 500, 900, 2000, 3000]) {
        await Future.delayed(Duration(milliseconds: ms));
        if (!fullScreenState.value ||
            smallWindowState.value ||
            isPlayerClosing) {
          Log.d(
              'SystemUi: restoreFullScreenSystemUi abort at ${ms}ms fullScreen=${fullScreenState.value} smallWindow=${smallWindowState.value}');
          return;
        }
        Log.d('SystemUi: reapply hidden at ${ms}ms');
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: const [],
        );
      }
    }
  }

  Future<void> toggleFullScreen() async {
    if (fullScreenState.value || smallWindowState.value) {
      await exitPlayerWindowMode();
    } else {
      await enterFullScreen();
    }
  }

  /// 退出全屏
  Future<void> exitFull() async {
    if (smallWindowState.value) {
      await exitSmallWindow();
      return;
    }
    if (Utils.isOhos) {
      if (ohosFullscreenTransition.value) {
        // 全屏过渡中：不要直接 return（会导致全屏/方向/系统栏残留），
        // 置待处理标记，由 enterFullScreen 过渡结束后接续执行退出，
        // 或由 closePlayerResources 的兜底逻辑强制恢复系统状态。
        _pendingExitFullscreen = true;
        return;
      }
      // Keep the fullscreen surface alive while the platform direction policy
      // is released, so the native AVPlayer texture remains attached.
      ohosFullscreenTransition.value = true;
      lockControlsState.value = false;
      showLockEdgeState.value = false;
      // System-bar restoration can take hundreds of milliseconds on some
      // HarmonyOS builds. Do not hold the portrait page behind that operation.
      unawaited(
        _runOhosSystemUiOperation(
          SystemChrome.setEnabledSystemUIMode(
            // 与 enterFullScreen 的 manual+[] 对称：flutter_ohos 对
            // SystemUiMode.edgeToEdge 支持不完整（channel 永不 reply，
            // 650ms 超时报"恢复系统栏失败"，退出全屏后系统栏不恢复）。
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          ),
          "恢复系统栏",
        ),
      );
      await _runOhosSystemUiOperation(
        SystemChrome.setPreferredOrientations(DeviceOrientation.values),
        "恢复屏幕方向",
      );
      fullScreenState.value = false;
      ohosFullscreenTransition.value = false;
      onPlayerWindowModeExited();
      showControls();
      return;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      _playbackDisplayLease?.setImmersiveSystemUi(false);
      await PlaybackDisplayCoordinator.instance.settle();
      await resetPreferredOrientation();
      await Future.delayed(const Duration(milliseconds: 32));
    } else {
      await _serializeDesktopWindowModeTransition(() async {
        if (!fullScreenState.value || smallWindowState.value) {
          return;
        }
        Log.d('Desktop fullscreen: exit start');
        try {
          await windowManager
              .setFullScreen(false)
              .timeout(const Duration(seconds: 2));
          await _waitForWindowsFullScreenState(false);
          await _refreshWindowsWindowBounds();
          if (_windowMaximizedBeforeFullScreen) {
            await windowManager.maximize();
            await _waitForWindowMaximizedState(true);
          }
          Log.d('Desktop fullscreen: exit complete');
        } catch (e, stackTrace) {
          Log.e('Desktop fullscreen: exit failed: $e', stackTrace);
        } finally {
          _windowMaximizedBeforeFullScreen = false;
          fullScreenState.value = false;
        }
      });
      onPlayerWindowModeExited();
      return;
    }
    fullScreenState.value = false;
    onPlayerWindowModeExited();

    //danmakuController?.clear();
  }

  Future<void> _runOhosSystemUiOperation(
    Future<void> operation,
    String description,
  ) async {
    try {
      await operation.timeout(const Duration(milliseconds: 650));
    } catch (e) {
      Log.logPrint("鸿蒙$description失败: $e");
    }
  }

  Future<void> _waitForOhosViewport({required bool portrait}) async {
    // 鸿蒙方向切换实际耗时可达 1s 左右，450ms 超时会在方向未就绪时
    // 提前切布局（画面被压成细长横条/拉伸填满）。放宽到 1.5s。
    final deadline = DateTime.now().add(const Duration(milliseconds: 1500));
    while (DateTime.now().isBefore(deadline)) {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        final size = views.first.physicalSize;
        final matches =
            portrait ? size.height >= size.width : size.width >= size.height;
        if (matches) {
          return;
        }
      }
      await Future.delayed(const Duration(milliseconds: 16));
    }
  }

  Size? _lastWindowSize;
  Offset? _lastWindowPosition;
  Future<void>? _desktopWindowModeTransition;
  bool _windowMaximizedBeforeFullScreen = false;
  bool _windowMaximizedBeforeSmallWindow = false;

  Future<void> _serializeDesktopWindowModeTransition(
    Future<void> Function() operation,
  ) async {
    while (_desktopWindowModeTransition != null) {
      await _desktopWindowModeTransition;
    }
    final completer = Completer<void>();
    _desktopWindowModeTransition = completer.future;
    try {
      await operation();
    } finally {
      _desktopWindowModeTransition = null;
      completer.complete();
    }
  }

  Future<void> _waitForWindowMaximizedState(bool value) async {
    if (!Platform.isWindows) {
      return;
    }

    final deadline = DateTime.now().add(const Duration(milliseconds: 600));
    while (DateTime.now().isBefore(deadline)) {
      if (await windowManager.isMaximized() == value) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _waitForWindowsFullScreenState(bool value) async {
    if (!Platform.isWindows) {
      await Future.delayed(const Duration(milliseconds: 16));
      return;
    }

    final deadline = DateTime.now().add(const Duration(milliseconds: 800));
    while (DateTime.now().isBefore(deadline)) {
      if (await windowManager.isFullScreen() == value) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _waitForWindowBoundsToChange(Rect previousBounds) async {
    if (!Platform.isWindows) {
      return;
    }

    final deadline = DateTime.now().add(const Duration(milliseconds: 800));
    while (DateTime.now().isBefore(deadline)) {
      final currentBounds = await windowManager.getBounds();
      final moved = (currentBounds.left - previousBounds.left).abs() > 0.5 ||
          (currentBounds.top - previousBounds.top).abs() > 0.5 ||
          (currentBounds.width - previousBounds.width).abs() > 0.5 ||
          (currentBounds.height - previousBounds.height).abs() > 0.5;
      if (moved) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _refreshWindowsWindowBounds() async {
    if (!Platform.isWindows) {
      return;
    }

    try {
      final size = await windowManager.getSize();
      if (size.width <= 1 || size.height <= 1) {
        return;
      }
      final nudgedSize = Size(size.width + 1, size.height + 1);
      await windowManager.setSize(nudgedSize);
      await windowManager.setSize(size);
    } catch (e) {
      Log.logPrint(e);
    }
  }

  Future<void> enterSmallWindow() async {
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Utils.isOhos ||
        smallWindowState.value) {
      return;
    }

    _windowMaximizedBeforeSmallWindow = await windowManager.isMaximized();
    if (_windowMaximizedBeforeSmallWindow) {
      final maximizedBounds = await windowManager.getBounds();
      await windowManager.restore();
      await _waitForWindowMaximizedState(false);
      await _waitForWindowBoundsToChange(maximizedBounds);
      await _refreshWindowsWindowBounds();
      await Future.delayed(const Duration(milliseconds: 120));
    }
    fullScreenState.value = true;
    smallWindowState.value = true;

    // 读取窗口大小
    _lastWindowSize = await windowManager.getSize();
    _lastWindowPosition = await windowManager.getPosition();

    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    // 获取视频窗口大小
    var width = player.state.width ?? 16;
    var height = player.state.height ?? 9;

    // 横屏还是竖屏
    if (height > width) {
      var aspectRatio = width / height;
      await windowManager.setSize(Size(400, 400 / aspectRatio));
    } else {
      var aspectRatio = height / width;
      await windowManager.setSize(Size(280 / aspectRatio, 280));
    }

    await windowManager.setAlwaysOnTop(true);
    danmakuController?.resume();
  }

  ///退出小窗模式()
  Future<void> exitSmallWindow() async {
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Utils.isOhos ||
        !smallWindowState.value) {
      return;
    }

    fullScreenState.value = false;
    smallWindowState.value = false;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    if (_lastWindowPosition != null) {
      await windowManager.setPosition(_lastWindowPosition!);
    }
    if (_lastWindowSize != null) {
      await windowManager.setSize(_lastWindowSize!);
    }
    if (_windowMaximizedBeforeSmallWindow) {
      await windowManager.maximize();
      await _waitForWindowMaximizedState(true);
    } else {
      await _refreshWindowsWindowBounds();
    }
    _windowMaximizedBeforeSmallWindow = false;
    danmakuController?.resume();
    onPlayerWindowModeExited();
    //windowManager.setAlignment(Alignment.center);
  }

  Future<void> exitPlayerWindowMode() async {
    if (smallWindowState.value) {
      await exitSmallWindow();
      return;
    }
    if (fullScreenState.value) {
      await exitFull();
    }
  }

  void toggleDanmakuByShortcut() {
    showDanmakuState.value = !showDanmakuState.value;
    if (!showDanmakuState.value) {
      danmakuController?.clear();
    } else {
      danmakuController?.resume();
    }
  }

  Future<void> toggleMute() async {
    if (Utils.isOhos) {
      if (mutedState.value) {
        final restoreVolume =
            PlayerVolumeSessionPolicy.volumeToRestoreAfterMute(
          lastAudibleVolume: _volumeBeforeMute,
          userIntentVolume: AppSettingsController.instance.playerVolume.value,
        );
        await setSessionPlayerVolume(restoreVolume);
      } else {
        _volumeBeforeMute = ohosVolume.value * 100;
        await setSessionPlayerVolume(0);
      }
      return;
    }
    if (mutedState.value) {
      final restoreVolume = PlayerVolumeSessionPolicy.volumeToRestoreAfterMute(
        lastAudibleVolume: _volumeBeforeMute,
        userIntentVolume: AppSettingsController.instance.playerVolume.value,
      );
      await setSessionPlayerVolume(restoreVolume);
      return;
    }
    _volumeBeforeMute = player.state.volume <= 0
        ? AppSettingsController.instance.playerVolume.value
        : player.state.volume;
    await setSessionPlayerVolume(0);
  }

  /// Ends transient mute state and reapplies the persisted user volume intent.
  Future<void> restoreUserIntentPlayerVolumeForRoom() async {
    final state = PlayerVolumeSessionPolicy.forNewRoom(
      userIntentVolume: AppSettingsController.instance.playerVolume.value,
      lastAudibleVolume: _volumeBeforeMute,
    );
    _volumeBeforeMute = state.lastAudibleVolume;
    mutedState.value = state.muted;
    await setSessionPlayerVolume(state.outputVolume);
  }

  Future<void> setSessionPlayerVolume(
    double volume, {
    bool persist = false,
  }) async {
    final value = volume.clamp(0.0, 100.0).toDouble();
    if (Utils.isOhos) {
      mutedState.value = value <= 0;
      if (value > 0) {
        _volumeBeforeMute = value;
      }
      ohosVolume.value = value / 100;
      await _ohosVideoController?.setVolume(ohosVolume.value);
      if (persist) {
        AppSettingsController.instance.setPlayerVolume(value);
      }
      return;
    }
    if (value <= 0) {
      mutedState.value = true;
      await player.setVolume(0);
    } else {
      mutedState.value = false;
      _volumeBeforeMute = value;
      await player.setVolume(value);
    }
    if (persist) {
      AppSettingsController.instance.setPlayerVolume(value);
    }
  }

  /// 设置横屏
  Future setLandscapeOrientation() async {
    Log.d('SystemUi: setLandscapeOrientation enter');
    if (await beforeIOS16()) {
      AutoOrientation.landscapeAutoMode();
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  /// 设置竖屏
  Future setPortraitOrientation() async {
    if (await beforeIOS16()) {
      AutoOrientation.portraitAutoMode();
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  /// 退出移动端全屏后主动回到竖屏，避免 iOS 保持横屏方向不切回。
  Future resetPreferredOrientation() async {
    if (Platform.isIOS) {
      await setPortraitOrientation();
      return;
    }
    if (await beforeIOS16()) {
      AutoOrientation.fullAutoMode();
    } else {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  /// 是否是IOS16以下
  Future<bool> beforeIOS16() async {
    if (Platform.isIOS) {
      var info = await deviceInfo.iosInfo;
      var version = info.systemVersion;
      var versionInt = int.tryParse(version.split('.').first) ?? 0;
      return versionInt < 16;
    } else {
      return false;
    }
  }

  Future<Uint8List?> _captureOhosScreenshot() async {
    final context = ohosScreenshotKey.currentContext;
    if (context == null) {
      return null;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    ohosScreenshotInProgress.value = true;
    try {
      await WidgetsBinding.instance.endOfFrame;
      final topLeft = renderObject.localToGlobal(Offset.zero);
      try {
        final nativeImage = await _ohosMediaChannel.invokeMethod<Uint8List>(
          "captureWindowRegion",
          {
            "x": (topLeft.dx * pixelRatio).round(),
            "y": (topLeft.dy * pixelRatio).round(),
            "width": (renderObject.size.width * pixelRatio).round(),
            "height": (renderObject.size.height * pixelRatio).round(),
          },
        );
        if (nativeImage != null && nativeImage.isNotEmpty) {
          return nativeImage;
        }
        // 原生截图未返回有效数据：视频由原生 AVPlayer 纹理渲染，不在
        // Flutter 渲染树中，回退 renderObject.toImage() 只会得到黑底图。
        // 直接提示失败并返回，不调用保存逻辑。
        Log.e("鸿蒙原生窗口截图未返回数据，放弃 Flutter 回退", StackTrace.current);
        SmartDialog.showToast("截图失败");
        return null;
      } catch (e, stackTrace) {
        // 原生截图失败：同样不再回退 Flutter 截图，避免保存黑屏图。
        Log.e("鸿蒙原生窗口截图失败：$e", stackTrace);
        SmartDialog.showToast("截图失败");
        return null;
      }
    } finally {
      ohosScreenshotInProgress.value = false;
    }
  }

  /// 保存截图到鸿蒙图库。
  ///
  /// 返回 `false` 表示用户取消了系统保存对话框（不是失败）。
  Future<bool> _saveOhosScreenshot(Uint8List imageData) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final title = "SimpleLive_$timestamp";
    final tempDirectory = await getTemporaryDirectory();
    final tempFile = File("${tempDirectory.path}/$title.png");
    await tempFile.writeAsBytes(imageData, flush: true);
    try {
      final savedUri = await _ohosMediaChannel.invokeMethod<String>(
        "saveImage",
        {
          "path": tempFile.path,
          "title": title,
          "extension": "png",
        },
      );
      // 原生侧在用户取消对话框时返回 null，与保存失败区分开。
      return savedUri != null && savedUri.isNotEmpty;
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future saveScreenshot() async {
    var loadingShown = false;
    try {
      //检查相册权限,仅iOS需要
      var permission = await Utils.checkPhotoPermission();
      if (!permission) {
        SmartDialog.showToast("没有相册权限");
        return;
      }

      var imageData = Utils.isOhos
          ? await _captureOhosScreenshot()
          : await player.screenshot();
      SmartDialog.showLoading(msg: "正在保存截图");
      loadingShown = true;
      if (imageData == null) {
        SmartDialog.showToast("截图失败,数据为空");
        return;
      }

      if (Utils.isOhos) {
        final saved = await _saveOhosScreenshot(imageData);
        SmartDialog.showToast(saved ? "已保存截图至图库" : "取消保存");
      } else if (Platform.isIOS || Platform.isAndroid) {
        await ImageGallerySaverPlus.saveImage(
          imageData,
        );
        SmartDialog.showToast("已保存截图至相册");
      } else {
        //选择保存文件夹
        var path = await FilePicker.platform.saveFile(
          allowedExtensions: ["jpg"],
          type: FileType.image,
          fileName: "${DateTime.now().millisecondsSinceEpoch}.jpg",
        );
        if (path == null) {
          SmartDialog.showToast("取消保存");
          return;
        }
        var file = File(path);
        await file.writeAsBytes(imageData);
        SmartDialog.showToast("已保存截图至${file.path}");
      }
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("截图失败");
    } finally {
      if (loadingShown) {
        SmartDialog.dismiss(status: SmartStatus.loading);
      }
    }
  }

  /// 开启小窗播放前弹幕状态
  bool danmakuStateBeforePIP = false;
  bool _pipStateApplied = false;
  bool _autoPipOnLeaveConfigured = false;

  bool get pipPlaybackActiveOrPrepared =>
      _pipStateApplied || _autoPipOnLeaveConfigured;

  Rational _resolvePipAspectRatio() {
    final width = player.state.width ?? 0;
    final height = player.state.height ?? 0;
    if (height > width) {
      return const Rational.vertical();
    }
    return const Rational.landscape();
  }

  math.Rectangle<int>? _buildPipSourceRectHint() {
    final context = globalPlayerKey.currentContext;
    if (context == null) {
      return null;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final offset = renderObject.localToGlobal(Offset.zero);
    final pixelRatio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    return math.Rectangle<int>(
      (offset.dx * pixelRatio).round(),
      (offset.dy * pixelRatio).round(),
      (renderObject.size.width * pixelRatio).round(),
      (renderObject.size.height * pixelRatio).round(),
    );
  }

  void _ensurePipStatusListener() {
    _pipSubscription ??= pip.pipStatusStream.listen((event) {
      if (event == PiPStatus.enabled) {
        _applyPipEnteredState();
      } else if (event == PiPStatus.disabled) {
        _restorePipExitedState();
      }
      Log.w(event.toString());
    });
  }

  Size _resolveOhosPipSize() {
    final value = ohosVideoController?.value;
    final size = value?.size ?? Size.zero;
    if (size.width > 0 && size.height > 0) {
      return size;
    }
    return const Size(16, 9);
  }

  void _ensureOhosPipStatusListener() {
    OhosPipService.instance.initialize();
    _ohosPipSubscription ??=
        OhosPipService.instance.stateChanges.listen((enabled) {
      if (enabled) {
        _applyPipEnteredState();
      } else {
        _restorePipExitedState();
      }
      Log.w('OHOS PiP enabled=$enabled');
    });
  }

  void _applyPipEnteredState() {
    if (_pipStateApplied) {
      return;
    }
    _pipStateApplied = true;
    danmakuStateBeforePIP = showDanmakuState.value;
    if (AppSettingsController.instance.pipHideDanmu.value &&
        danmakuStateBeforePIP) {
      showDanmakuState.value = false;
    }
    showControlsState.value = false;
  }

  void _restorePipExitedState() {
    if (!_pipStateApplied && !_autoPipOnLeaveConfigured) {
      return;
    }
    _pipStateApplied = false;
    _autoPipOnLeaveConfigured = false;
    showDanmakuState.value = danmakuStateBeforePIP;
    if (showDanmakuState.value) {
      danmakuController?.resume();
    }
  }

  Future<void> cancelAutoPipOnLeave() async {
    if (Utils.isOhos) {
      _autoPipOnLeaveConfigured = false;
      try {
        await OhosPipService.instance.cancelAuto();
      } catch (e) {
        Log.d("取消鸿蒙自动小窗失败: $e");
      }
      return;
    }
    if (!Platform.isAndroid) {
      return;
    }
    _autoPipOnLeaveConfigured = false;
    try {
      await pip.cancelOnLeavePiP();
    } catch (e) {
      Log.d("取消自动小窗失败: $e");
    }
  }

  Future<bool> prepareAutoPipOnLeave() async {
    if (Utils.isOhos) {
      if (_autoPipOnLeaveConfigured) {
        return true;
      }
      _ensureOhosPipStatusListener();
      final size = _resolveOhosPipSize();
      try {
        final configured = await OhosPipService.instance.prepareAuto(
          width: size.width,
          height: size.height,
        );
        _autoPipOnLeaveConfigured = configured;
        if (configured) {
          showControlsState.value = false;
        }
        return configured;
      } catch (e) {
        Log.d("配置鸿蒙退后台自动小窗失败: $e");
        return false;
      }
    }
    if (!Platform.isAndroid || _autoPipOnLeaveConfigured) {
      return _autoPipOnLeaveConfigured;
    }
    if (await pip.isPipAvailable == false) {
      return false;
    }
    _ensurePipStatusListener();
    try {
      await pip.enable(
        OnLeavePiP(
          aspectRatio: _resolvePipAspectRatio(),
          sourceRectHint: _buildPipSourceRectHint(),
        ),
      );
      _autoPipOnLeaveConfigured = true;
      showControlsState.value = false;
      return true;
    } catch (e) {
      Log.d("配置退后台自动小窗失败: $e");
      return false;
    }
  }

  Future enablePIP() async {
    if (Utils.isOhos) {
      _ensureOhosPipStatusListener();
      if (!await OhosPipService.instance.isAvailable()) {
        SmartDialog.showToast("设备不支持小窗播放");
        return;
      }
      await cancelAutoPipOnLeave();
      final size = _resolveOhosPipSize();
      try {
        await OhosPipService.instance.enter(
          width: size.width,
          height: size.height,
        );
      } catch (e) {
        Log.d("开启鸿蒙小窗失败: $e");
        SmartDialog.showToast("开启小窗失败");
      }
      return;
    }
    if (!Platform.isAndroid) {
      SmartDialog.showToast("当前平台暂不支持小窗播放");
      return;
    }
    if (await pip.isPipAvailable == false) {
      SmartDialog.showToast("设备不支持小窗播放");
      return;
    }
    await cancelAutoPipOnLeave();
    _ensurePipStatusListener();
    await pip.enable(
      ImmediatePiP(
        aspectRatio: _resolvePipAspectRatio(),
        sourceRectHint: _buildPipSourceRectHint(),
      ),
    );
  }
}
mixin PlayerGestureControlMixin
    on PlayerStateMixin, PlayerMixin, PlayerSystemMixin {
  /// 单击显示/隐藏控制器
  void onTap() {
    Log.d(
        'PlayerGesture: onTap showControls=${showControlsState.value} lock=${lockControlsState.value} fullScreen=${fullScreenState.value}');
    if (lockControlsState.value && fullScreenState.value) {
      // 锁定时普通控制器保持隐藏，但触屏设备仍需通过点击画面重新呼出
      // 边缘解锁按钮。桌面端也保留同样的点击入口，作为鼠标悬停的补充。
      showLockEdgeState.value = !showLockEdgeState.value;
      return;
    }
    if (showControlsState.value) {
      hideControls();
    } else {
      showControls();
    }
  }

  // 桌面端鼠标操控
  void onEnter(PointerEnterEvent event) {
    showMouseCursor();
    resetHideMouseCursorTimer();
    if (lockControlsState.value) {
      return;
    }
    if (!showControlsState.value) {
      showControls();
    }
  }

  void onExit(PointerExitEvent event) {
    hideMouseCursorTimer?.cancel();
    hideControlsTimer?.cancel();
    showLockEdgeState.value = false;
    if (lockControlsState.value) {
      return;
    }
    if (!showControlsState.value) {
      return;
    }
    hideControlsTimer = Timer(
      const Duration(milliseconds: 180),
      () {
        if (showControlsState.value) {
          hideControls();
        }
      },
    );
  }

  void onHover(PointerHoverEvent event, BuildContext context) {
    showMouseCursor();
    resetHideMouseCursorTimer();
    if (lockControlsState.value) {
      final width = context.size?.width ?? 0;
      showLockEdgeState.value = fullScreenState.value &&
          width > 0 &&
          (event.localPosition.dx <= 48 ||
              event.localPosition.dx >= width - 48);
      return;
    }
    resetHideControlsTimer();
    if (!showControlsState.value) {
      showControls();
    }
  }

  /// 双击全屏/退出全屏
  void onDoubleTap(TapDownDetails details) {
    if (lockControlsState.value) {
      return;
    }
    if (smallWindowState.value) {
      exitSmallWindow();
    } else if (fullScreenState.value) {
      exitFull();
    } else {
      enterFullScreen();
    }
  }

  bool verticalDragging = false;
  bool leftVerticalDrag = false;
  var _currentVolume = 0.0;
  var _currentBrightness = 1.0;
  var verStartPosition = 0.0;

  DelayedThrottle? throttle;

  /// 竖向手势开始
  void onVerticalDragStart(DragStartDetails details) async {
    showMouseCursor();
    resetHideMouseCursorTimer();
    if (lockControlsState.value && fullScreenState.value) {
      return;
    }
    if (!AppSettingsController.instance.playerGestureControlEnable.value) {
      return;
    }

    final dy = details.globalPosition.dy;
    // 开始位置必须是中间2/4的位置
    if (dy < Get.height * 0.25 || dy > Get.height * 0.75) {
      return;
    }

    verStartPosition = dy;
    leftVerticalDrag = details.globalPosition.dx < Get.width / 2;

    throttle = DelayedThrottle(200);
    lastVolume = -1;

    verticalDragging = true;
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux ||
        Utils.isOhos) {
      showGestureTip.value = true;
    }
    if (Platform.isWindows || Platform.isLinux) {
      final currentPlayerVolume = player.state.volume;
      if (currentPlayerVolume > 0) {
        _currentVolume = currentPlayerVolume.clamp(0.0, 100.0) / 100;
      } else {
        _currentVolume = AppSettingsController.instance.playerVolume.value
                .clamp(0.0, 100.0) /
            100;
      }
    } else if (Utils.isOhos) {
      _currentVolume = ohosVolume.value;
    } else if (Platform.isAndroid || Platform.isIOS) {
      _currentVolume = await VolumeController.instance.getVolume();
    }
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux ||
        Utils.isOhos) {
      try {
        _currentBrightness = await ScreenBrightness.instance.application;
      } catch (e) {
        Log.logPrint(e);
        _currentBrightness = 1.0;
      }
    }
  }

  /// 竖向手势更新
  void onVerticalDragUpdate(DragUpdateDetails e) async {
    if (lockControlsState.value && fullScreenState.value) {
      return;
    }
    if (!AppSettingsController.instance.playerGestureControlEnable.value) {
      return;
    }
    if (verticalDragging == false) return;
    if (!Platform.isAndroid &&
        !Platform.isIOS &&
        !Platform.isWindows &&
        !Platform.isLinux &&
        !Utils.isOhos) {
      return;
    }
    //String text = "";
    //double value = 0.0;

    Log.logPrint("$verStartPosition/${e.globalPosition.dy}");

    if (leftVerticalDrag) {
      setGestureBrightness(e.globalPosition.dy);
    } else {
      setGestureVolume(e.globalPosition.dy);
    }
  }

  int lastVolume = -1; // it's ok to be -1

  void setGestureVolume(double dy) {
    double value = 0.0;
    double seek;
    if (dy > verStartPosition) {
      value = ((dy - verStartPosition) / (Get.height * 0.5));

      seek = _currentVolume - value;
      if (seek < 0) {
        seek = 0;
      }
    } else {
      value = ((dy - verStartPosition) / (Get.height * 0.5));
      seek = value.abs() + _currentVolume;
      if (seek > 1) {
        seek = 1;
      }
    }
    int volume = _convertVolume((seek * 100).round());
    if (volume == lastVolume) {
      return;
    }
    lastVolume = volume;
    // update UI outside throttle to make it more fluent
    gestureTipText.value = "音量 $volume%";
    throttle?.invoke(() async => await _realSetVolume(volume));
  }

  // 0 to 100, 5 step each
  int _convertVolume(int volume) {
    return (volume / 5).round() * 5;
  }

  Future _realSetVolume(int volume) async {
    Log.logPrint(volume);
    if (Platform.isWindows || Platform.isLinux || Utils.isOhos) {
      await setSessionPlayerVolume(volume.toDouble(), persist: true);
      return;
    }
    // 手势只调系统音量，播放器内部音量由独立设置控制。
    await VolumeController.instance.setVolume(volume / 100);
  }

  void setGestureBrightness(double dy) {
    double value = 0.0;
    if (dy > verStartPosition) {
      value = ((dy - verStartPosition) / (Get.height * 0.5));

      var seek = _currentBrightness - value;
      if (seek < 0) {
        seek = 0;
      }
      ScreenBrightness.instance.setApplicationScreenBrightness(seek);

      gestureTipText.value = "亮度 ${(seek * 100).toInt()}%";
      Log.logPrint(value);
    } else {
      value = ((dy - verStartPosition) / (Get.height * 0.5));
      var seek = value.abs() + _currentBrightness;
      if (seek > 1) {
        seek = 1;
      }

      ScreenBrightness.instance.setApplicationScreenBrightness(seek);
      gestureTipText.value = "亮度 ${(seek * 100).toInt()}%";
      Log.logPrint(value);
    }
  }

  /// 竖向手势完成
  void onVerticalDragEnd(DragEndDetails details) async {
    if (lockControlsState.value && fullScreenState.value) {
      return;
    }
    if (!AppSettingsController.instance.playerGestureControlEnable.value) {
      return;
    }
    throttle = null;
    verticalDragging = false;
    leftVerticalDrag = false;
    showGestureTip.value = false;
    // 一并清掉文案，避免下次手势按下时先闪一帧上次的残留值。
    gestureTipText.value = "";
  }
}

class PlayerController extends BaseController
    with
        PlayerMixin,
        PlayerStateMixin,
        PlayerDanmakuMixin,
        PlayerSystemMixin,
        PlayerGestureControlMixin {
  @override
  void onInit() {
    if (Utils.isOhos) {
      initPlaybackDisplayLease();
      unawaited(restoreUserIntentPlayerVolumeForRoom());
      if (AppSettingsController.instance.autoFullScreen.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!isPlayerClosing && !fullScreenState.value) {
            unawaited(enterFullScreen());
          }
        });
      }
      showControls();
      super.onInit();
      return;
    }
    initSystem();
    initStream();
    unawaited(restoreUserIntentPlayerVolumeForRoom());
    super.onInit();
  }

  StreamSubscription<String>? _errorSubscription;
  StreamSubscription? _completedSubscription;
  StreamSubscription? _widthSubscription;
  StreamSubscription? _heightSubscription;
  StreamSubscription? _logSubscription;
  StreamSubscription? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;

  // Fix Issue #57: 流错误重试计数器
  int _streamErrorRetryCount = 0;
  DateTime? _lastStreamErrorTime;
  bool _streamErrorRecoveryInFlight = false;
  Timer? _surfaceHealthCheckTimer;

  /// 自动网络诊断提示（达到 tracker 阈值的独立缓冲开始时触发，
  /// 显示在画面左上角）。
  final networkHint = "".obs;
  bool _autoDiagnoseRunning = false;
  Timer? _networkHintTimer;
  DateTime? _lastAutoDiagnoseAt;
  bool _hasMarkedInitialStreamOpening = false;

  /// 自动网络诊断的独立缓冲开始统计器（与自动降画质各持有独立实例，
  /// 只复用同构算法，不共享可变状态）。
  final LiveRoomAutoQualityBufferTracker _autoDiagnosisTracker =
      LiveRoomAutoQualityBufferTracker(
    requiredBufferStarts: 2,
    bufferingWindow: const Duration(seconds: 30),
    stableResetAfter: const Duration(seconds: 30),
    warmupDuration: const Duration(seconds: 8),
  );

  /// 诊断会话代次：换房重置时递增；旧房间的异步诊断结果返回后，
  /// 若代次不匹配则只能丢弃，不得写入新房间的 networkHint。
  int _diagnosisGeneration = 0;

  /// 当前正在执行的诊断所属代次（与 [_autoDiagnoseRunning] 配合，
  /// 使换房后的旧诊断不再阻塞新房间诊断）。
  int? _runningDiagnoseGeneration;

  /// 重置自动网络诊断会话（换房时由 LiveRoomController 调用）。
  ///
  /// 一次性处理：缓冲计数归零、边沿状态归零、诊断冷却清空、
  /// 取消旧提示 Timer、清空 networkHint、递增诊断代次，
  /// 使旧房间的异步诊断结果只能被丢弃，并恢复到尚未首次开流状态。
  ///
  /// 注意：[_autoDiagnoseRunning]/[_runningDiagnoseGeneration] 故意不在
  /// 此处重置——旧诊断终会经由 _runAutoNetworkDiagnose 的 finally 自清理，
  /// 且代次互斥（[:2055]）保证残留标志不阻塞新房间诊断。
  void resetAutoNetworkDiagnosisSession() {
    _autoDiagnosisTracker.reset();
    _hasMarkedInitialStreamOpening = false;
    _lastAutoDiagnoseAt = null;
    _networkHintTimer?.cancel();
    _networkHintTimer = null;
    networkHint.value = "";
    _diagnosisGeneration += 1;
    Log.d("[player-diag] session reset generation=$_diagnosisGeneration");
  }

  /// 在诊断会话的首次 `player.open()` 前开始忽略起播缓冲。
  ///
  /// 调用方应在真正的 `player.open()` 前紧邻调用。媒体错误、播放结束、
  /// 切线路或降画质导致的后续重开不会清零诊断计数，也不会重新开始 warmup。
  /// 返回 true 表示本次确实启动了会话 warmup，false 表示已启动过。
  bool markStreamOpening({DateTime? now}) {
    if (_hasMarkedInitialStreamOpening) {
      Log.d("[player-diag] stream opening ignored (session already warmed up)");
      return false;
    }
    _hasMarkedInitialStreamOpening = true;
    _autoDiagnosisTracker.beginWarmup(now ?? DateTime.now());
    Log.d("[player-diag] initial stream opening, warmup begins");
    return true;
  }

  /// 房间控制器可覆写为 true，让流错误回到房间级重试/刷新流程。
  /// 默认 false，保持现有平台的播放器内解码器重试行为。
  bool get shouldDelegateStreamErrorsToRoomController => false;

  /// 当前实际播放 URL。子类提供后，诊断会使用其真实 host/port。
  String get currentNetworkDiagnosePlaybackUrl => '';

  void initStream() {
    _errorSubscription = player.stream.error.listen((event) {
      Log.d("播放器错误：$event");
      // 跳过无音频输出的错误
      // Could not open/initialize audio device -> no sound.
      if (event.contains('no sound.')) {
        return;
      }

      // Fix Issue #57: 流错误默认由播放器内重试；需要房间级刷新 URL 的平台
      // 可覆写 shouldDelegateStreamErrorsToRoomController 交回 mediaError。
      if (_isStreamError(event)) {
        if (shouldDelegateStreamErrorsToRoomController) {
          final now = DateTime.now();
          if (_lastStreamErrorTime != null &&
              now.difference(_lastStreamErrorTime!) <
                  const Duration(seconds: 2)) {
            return;
          }
          _lastStreamErrorTime = now;
          Log.d("[player] delegating stream error to room controller");
          unawaited(
            suspendLiveLatencyChase(
              MpvLiveLatencyProtectionReason.sourceChanged,
            ),
          );
          mediaError(event);
        } else {
          _handleStreamError(event);
        }
        return;
      }

      //SmartDialog.showToast(event);
      unawaited(
        suspendLiveLatencyChase(
          MpvLiveLatencyProtectionReason.sourceChanged,
        ),
      );
      mediaError(event);
    });

    _playingSubscription = player.stream.playing.listen((event) {
      _setKeepScreenAwake(!isPlayerClosing && event);
      unawaited(_syncBackgroundPlaybackService(event));
      if (event) {
        Log.d("Playing");
        // 播放成功，重置流错误计数
        _streamErrorRetryCount = 0;
        unawaited(resumeLiveLatencyChase());
      } else if (!isPlayerClosing) {
        unawaited(
          suspendLiveLatencyChase(
            MpvLiveLatencyProtectionReason.userPaused,
          ),
        );
      }
    });

    _completedSubscription = player.stream.completed.listen((event) {
      if (event) {
        unawaited(
          suspendLiveLatencyChase(
            MpvLiveLatencyProtectionReason.sourceChanged,
          ),
        );
        mediaEnd();
      }
    });
    _logSubscription = player.stream.log.listen((event) {
      final eventType = classifyMpvLiveLinkLog(
        prefix: event.prefix,
        text: event.text,
      );
      if (eventType != null) {
        recordLiveLinkHealthEvent(eventType);
        if (eventType == LiveLinkEventType.audioUnderrun) {
          unawaited(
            protectLiveLatencyChase(
              MpvLiveLatencyProtectionReason.audioUnderrun,
            ),
          );
        }
      }
      Log.d("播放器日志：$event");
    });
    _widthSubscription = player.stream.width.listen((event) {
      Log.d(
          'width:$event  W:${(player.state.width)}  H:${(player.state.height)}');

      // Fix Issue #57: 检测异常的视频尺寸
      if (event == null || event <= 0) {
        if (player.state.playing) {
          Log.w("播放器宽度异常: $event (播放中)，可能是Surface失效");
          _handleInvalidVideoSize();
        }
        return;
      }

      isVertical.value =
          (player.state.height ?? 9) > (player.state.width ?? 16);
    });
    _heightSubscription = player.stream.height.listen((event) {
      Log.d(
          'height:$event  W:${(player.state.width)}  H:${(player.state.height)}');

      // Fix Issue #57: 检测异常的视频尺寸
      if (event == null || event <= 0) {
        if (player.state.playing) {
          Log.w("播放器高度异常: $event (播放中)，可能是Surface失效");
          _handleInvalidVideoSize();
        }
        return;
      }

      isVertical.value =
          (player.state.height ?? 9) > (player.state.width ?? 16);
    });

    // Fix Issue #57: 启动Surface健康检查
    _startSurfaceHealthCheck();

    // 缓冲边沿计数：按 false->true 计数独立缓冲开始，达到阈值自动触发网络诊断。
    _bufferingSubscription = player.stream.buffering.listen((buffering) {
      Log.d("[player-diag] buffering event=$buffering");
      observeAutoNetworkDiagnosisBuffering(buffering);
    });
  }

  void observeAutoNetworkDiagnosisBuffering(bool buffering) {
    if (isPlayerClosing ||
        (Utils.isOhos &&
            !AppSettingsController
                .instance.ohosNetworkFluctuationNotice.value)) {
      return;
    }
    final now = DateTime.now();
    final shouldDiagnose = _autoDiagnosisTracker.update(
      buffering: buffering,
      now: now,
    );
    if (!shouldDiagnose) {
      return;
    }
    if (_lastAutoDiagnoseAt != null &&
        now.difference(_lastAutoDiagnoseAt!) < const Duration(seconds: 30)) {
      Log.d("[player-diag] diagnose skipped (cooldown 30s)");
      return;
    }
    _lastAutoDiagnoseAt = now;
    unawaited(_runAutoNetworkDiagnose());
  }

  /// 自动网络诊断：缓冲 [LiveRoomAutoQualityBufferTracker.requiredBufferStarts]
  /// 次独立开始时测连接，提示显示在画面左上角，8 秒后自动消失。
  /// 结果写入前校验诊断代次，防止旧房间结果串房。
  Future<void> _runAutoNetworkDiagnose() async {
    final generation = _diagnosisGeneration;
    // 同一代次内并发诊断互斥；换房（代次变化）后旧诊断不再阻塞新房间诊断。
    if (_autoDiagnoseRunning && _runningDiagnoseGeneration == generation) {
      Log.d("[player-diag] diagnose skipped (already running)");
      return;
    }
    _autoDiagnoseRunning = true;
    _runningDiagnoseGeneration = generation;
    networkHint.value = "网络检测中…";
    Log.d(
        "[player-diag] playback endpoint diagnose start samples=3 generation=$generation");
    try {
      final playbackResult = await NetworkDiagnoseService.diagnosePlaybackUrl(
        currentNetworkDiagnosePlaybackUrl,
        samples: 3,
      );
      final allResults = [
        if (playbackResult != null) playbackResult,
      ];
      Log.d(
          "[player-diag] diagnose done ${allResults.map((r) => '${r.host}:lost=${r.lost}/${r.samples}').join(' ')} generation=$generation");
      // 旧房间诊断结果：代次不匹配或已换房，丢弃。
      if (isPlayerClosing || generation != _diagnosisGeneration) {
        Log.d("[player-diag] diagnose result dropped (stale generation)");
        return;
      }
      networkHint.value =
          NetworkDiagnoseService.summarizePlaybackEndpoint(playbackResult);
      _networkHintTimer?.cancel();
      _networkHintTimer = Timer(const Duration(seconds: 8), () {
        if (generation == _diagnosisGeneration &&
            networkHint.value.isNotEmpty) {
          networkHint.value = "";
        }
      });
    } catch (e) {
      // 诊断失败：清空"网络检测中…"残留，避免卡住提示。
      if (generation == _diagnosisGeneration) {
        networkHint.value = "";
      }
      Log.d("[player-diag] diagnose error generation=$generation: $e");
    } finally {
      // 仅当仍是当前运行代次时释放标志，避免旧代次 finally 误清新代次状态。
      if (_runningDiagnoseGeneration == generation) {
        _autoDiagnoseRunning = false;
        _runningDiagnoseGeneration = null;
      }
    }
  }

  void disposeStream() {
    _errorSubscription?.cancel();
    _completedSubscription?.cancel();
    _widthSubscription?.cancel();
    _heightSubscription?.cancel();
    _logSubscription?.cancel();
    _pipSubscription?.cancel();
    _ohosPipSubscription?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _networkHintTimer?.cancel();
    _surfaceHealthCheckTimer?.cancel();
  }

  // Fix Issue #57: 判断是否为流错误（网络/解码错误）
  bool _isStreamError(String error) {
    return error.contains('mbedtls_ssl_read') ||
        error.contains('Packet corrupt') ||
        error.contains('Packet corupt') ||
        error.contains('tls:') ||
        error.contains('Invalid NAL unit') ||
        error.contains('missing picture');
  }

  // Fix Issue #57: 处理流错误，自动重试
  Future<void> _handleStreamError(String error) async {
    final now = DateTime.now();

    // 防止短时间内重复触发
    if (_streamErrorRecoveryInFlight ||
        (_lastStreamErrorTime != null &&
            now.difference(_lastStreamErrorTime!) <
                const Duration(seconds: 2))) {
      return;
    }
    _lastStreamErrorTime = now;

    if (_streamErrorRetryCount >= 3) {
      Log.e("流错误重试次数已达上限(3次)，停止重试: $error", StackTrace.current);
      await suspendLiveLatencyChase(
        MpvLiveLatencyProtectionReason.sourceChanged,
      );
      mediaError(error);
      return;
    }

    _streamErrorRetryCount++;
    Log.w(
      "检测到流错误，自动重试解码器 ($_streamErrorRetryCount/3): $error",
      false,
    );

    _streamErrorRecoveryInFlight = true;
    final expectedGeneration = _livePlaybackGeneration;
    final previousSourceIdentity = _livePlaybackSource;
    final reconnectStartedAt = now;
    try {
      await suspendLiveLatencyChase(
        MpvLiveLatencyProtectionReason.sourceChanged,
      );
      // 等待1秒后重新打开当前流
      await Future.delayed(const Duration(seconds: 1));
      if (_playerClosing || expectedGeneration != _livePlaybackGeneration) {
        return;
      }
      final playlist = player.state.playlist;
      final currentMedia = playlist.medias.isNotEmpty &&
              playlist.index >= 0 &&
              playlist.index < playlist.medias.length
          ? playlist.medias[playlist.index]
          : null;

      if (currentMedia != null && !_playerClosing) {
        final source = currentMedia.uri.toString();
        final sourceIdentity = canonicalizeLivePlaybackSource(source);
        if (sourceIdentity.isEmpty ||
            (previousSourceIdentity != null &&
                sourceIdentity != previousSourceIdentity)) {
          return;
        }
        Log.i("正在重启解码器...");
        await player.pause();
        await Future.delayed(const Duration(milliseconds: 200));
        if (_playerClosing || expectedGeneration != _livePlaybackGeneration) {
          return;
        }
        await player.open(currentMedia);
        if (_playerClosing || expectedGeneration != _livePlaybackGeneration) {
          return;
        }
        await resetLiveLatencyChase();
        final recoveryGeneration = _livePlaybackGeneration;
        await startLivePlaybackLightweightSampling(source: source);
        if (_playerClosing ||
            recoveryGeneration != _livePlaybackGeneration ||
            sourceIdentity != _livePlaybackSource) {
          return;
        }
        final completedAt = DateTime.now();
        recordLiveLinkHealthEvent(
          LiveLinkEventType.cdnReconnect,
          at: completedAt,
          reconnectReason: LiveReconnectReason.mediaError,
          reconnectHostChanged: didLivePlaybackHostChange(
            previousSourceIdentity,
            sourceIdentity,
          ),
          reconnectRecoveryDuration: completedAt.difference(reconnectStartedAt),
        );
      }
    } catch (e, stackTrace) {
      Log.e("重启解码器失败: $e", stackTrace);
      if (!_playerClosing && expectedGeneration == _livePlaybackGeneration) {
        await suspendLiveLatencyChase(
          MpvLiveLatencyProtectionReason.sourceChanged,
        );
        mediaError(error);
      }
    } finally {
      _streamErrorRecoveryInFlight = false;
    }
  }

  // Fix Issue #57: 处理异常的视频尺寸（Surface失效）
  Future<void> _handleInvalidVideoSize() async {
    Log.w("检测到视频尺寸异常，尝试恢复Surface");

    // 短暂暂停再恢复，触发Surface重建
    try {
      if (player.state.playing && !_playerClosing) {
        await suspendLiveLatencyChase(
          MpvLiveLatencyProtectionReason.playbackStalled,
        );
        await player.pause();
        await Future.delayed(const Duration(milliseconds: 300));
        await player.play();
        await resumeLiveLatencyChase();
      }
    } catch (e, stackTrace) {
      Log.e("恢复Surface失败: $e", stackTrace);
    }
  }

  // Fix Issue #57: Surface健康检查（每3秒检查一次）
  void _startSurfaceHealthCheck() {
    if (!Platform.isAndroid) {
      return; // 仅Android需要
    }

    _surfaceHealthCheckTimer?.cancel();
    _surfaceHealthCheckTimer = Timer.periodic(
      const Duration(seconds: 3),
      (timer) {
        if (_playerClosing) {
          timer.cancel();
          return;
        }

        // 检测：播放中但尺寸为null = Surface异常
        if (player.state.playing &&
            (player.state.width == null || player.state.height == null)) {
          Log.w(
            "Surface健康检查失败: playing=${player.state.playing} "
            "width=${player.state.width} height=${player.state.height}",
          );
          _handleInvalidVideoSize();
        }
      },
    );
  }

  void mediaEnd() {
    _setKeepScreenAwake(false);
    unawaited(stopBackgroundPlaybackService());
  }

  void mediaError(String error) {
    _setKeepScreenAwake(false);
    unawaited(stopBackgroundPlaybackService());
  }

  Future<void> _syncBackgroundPlaybackService(bool playing) async {
    if (!Platform.isAndroid) {
      return;
    }
    if (playing &&
        AppSettingsController.instance.allowBackgroundPlayback.value) {
      await BackgroundPlaybackService.instance.start();
    } else if (!playing ||
        !AppSettingsController.instance.allowBackgroundPlayback.value) {
      await BackgroundPlaybackService.instance.stop();
    }
  }

  Future<void> stopBackgroundPlaybackService() {
    return BackgroundPlaybackService.instance.stop();
  }

  void showDebugInfo() {
    if (Utils.isOhos) {
      _showOhosDebugInfo();
      return;
    }
    Utils.showBottomSheet(
      title: "播放信息",
      child: ListView(
        children: [
          ListTile(
            title: const Text("Resolution"),
            subtitle: Text('${player.state.width}x${player.state.height}'),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text:
                      "Resolution\n${player.state.width}x${player.state.height}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("VideoParams"),
            subtitle: Text(player.state.videoParams.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "VideoParams\n${player.state.videoParams}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("AudioParams"),
            subtitle: Text(player.state.audioParams.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "AudioParams\n${player.state.audioParams}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("Media"),
            subtitle: Text(player.state.playlist.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "Media\n${player.state.playlist}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("AudioTrack"),
            subtitle: Text(player.state.track.audio.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "AudioTrack\n${player.state.track.audio}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("VideoTrack"),
            subtitle: Text(player.state.track.video.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "VideoTrack\n${player.state.track.video}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("AudioBitrate"),
            subtitle: Text(player.state.audioBitrate.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "AudioBitrate\n${player.state.audioBitrate}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("Volume"),
            subtitle: Text(player.state.volume.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "Volume\n${player.state.volume}",
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showOhosDebugInfo() {
    final controller = _ohosVideoController;
    final value = controller?.value;
    final size = value?.size ?? Size.zero;
    final state = value == null
        ? "未创建"
        : value.hasError
            ? "错误"
            : !value.isInitialized
                ? "初始化中"
                : value.isBuffering
                    ? "缓冲中"
                    : value.isPlaying
                        ? "播放中"
                        : "已暂停";
    final rows = <MapEntry<String, String>>[
      const MapEntry("Backend", "HarmonyOS AVPlayer"),
      MapEntry("State", state),
      MapEntry(
        "Resolution",
        size.isEmpty ? "未知" : "${size.width.round()}x${size.height.round()}",
      ),
      MapEntry(
        "AspectRatio",
        value == null || !value.isInitialized
            ? "未知"
            : value.aspectRatio.toStringAsFixed(4),
      ),
      MapEntry("Position", value?.position.toString() ?? "未知"),
      MapEntry("Duration", value?.duration.toString() ?? "未知"),
      MapEntry(
        "Volume",
        "${(ohosVolume.value * 100).round()}%",
      ),
      MapEntry("PlaybackSpeed", value?.playbackSpeed.toString() ?? "未知"),
      MapEntry("Media", controller?.dataSource ?? "未创建"),
      if (value?.errorDescription != null)
        MapEntry("Error", value!.errorDescription!),
    ];

    Utils.showBottomSheet(
      title: "播放信息",
      child: ListView(
        children: rows
            .map(
              (row) => ListTile(
                title: Text(row.key),
                subtitle: Text(row.value),
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: "${row.key}\n${row.value}"),
                  );
                },
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> closePlayerResources() async {
    if (_playerClosing) {
      return;
    }
    _playerClosing = true;
    _setKeepScreenAwake(false);
    await releasePlaybackDisplayLease();
    if (Utils.isOhos) {
      if (fullScreenState.value) {
        await exitFull();
      }
      hideControlsTimer?.cancel();
      try {
        await OhosPipService.instance.exit();
      } catch (e) {
        Log.logPrint("鸿蒙画中画关闭失败: $e");
      }
      hideMouseCursorTimer?.cancel();
      final ohosController = _ohosVideoController;
      try {
        await ohosController?.pause();
      } catch (e) {
        Log.logPrint("鸿蒙播放器暂停失败: $e");
      }
      if (ohosController != null) {
        BackgroundPlaybackService.instance.detachOhosController(ohosController);
      }
      await BackgroundPlaybackService.instance.release();
      try {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      } catch (e) {
        Log.logPrint("鸿蒙应用亮度恢复失败: $e");
      }
      // 最终兜底：无论是否处于全屏过渡（此时 exitFull 只会置
      // _pendingExitFullscreen 标记而无法真正退出），都无条件强制恢复
      // 屏幕方向与系统栏，避免 fullScreenState 残留横屏锁死/系统栏消失。
      fullScreenState.value = false;
      ohosFullscreenTransition.value = false;
      _pendingExitFullscreen = false;
      await _runOhosSystemUiOperation(
        SystemChrome.setPreferredOrientations(DeviceOrientation.values),
        "强制恢复屏幕方向",
      );
      await _runOhosSystemUiOperation(
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        ),
        "强制恢复系统栏",
      );
      _ohosVideoController = null;
      disposeDanmakuController();
      await stopLiveLatencyChase();
      return;
    }
    await stopBackgroundPlaybackService();
    await stopLiveLatencyChase();
    await player.stop();
    if (smallWindowState.value) {
      await exitSmallWindow();
    }
    disposeStream();
    disposeDanmakuController();
    await resetSystem();
    await player.dispose();
  }

  @override
  void onClose() async {
    Log.w("播放器关闭");
    await closePlayerResources();
    super.onClose();
  }
}
