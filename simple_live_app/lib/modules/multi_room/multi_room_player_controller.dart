import 'dart:async';
import 'dart:ui';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/platform_utils.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_adaptive_quality.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_live_link_health.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/modules/multi_room/player_mutation_queue.dart';
import 'package:simple_live_app/services/live_latency_telemetry_service.dart'
    as health_telemetry;
import 'package:simple_live_app/services/live_link_health_collector.dart'
    show canonicalizeLivePlaybackSource, didLivePlaybackHostChange;
import 'package:simple_live_app/services/live_link_health_media_kit_adapter.dart';
import 'package:simple_live_app/services/live_link_health_models.dart';
import 'package:simple_live_app/services/mpv_live_latency_chase_service.dart';
import 'package:simple_live_app/services/mpv_live_latency_chase_sampling_loop.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

bool shouldSampleMultiRoomLiveHealth({
  required bool appActive,
  required bool paused,
  required bool playbackDesired,
  required bool liveStatus,
  required bool hasActiveSource,
}) {
  return appActive &&
      !paused &&
      playbackDesired &&
      liveStatus &&
      hasActiveSource;
}

bool shouldChaseMultiRoomLiveLatency({
  required bool healthSamplingEligible,
  required MpvLiveLatencyPlaybackRole role,
}) {
  return healthSamplingEligible &&
      role == MpvLiveLatencyPlaybackRole.multiRoomPrimaryVisible;
}

List<DanmakuContentPart>? buildMultiRoomDanmakuContentParts(
  List<LiveMessageSpan>? spans,
) {
  final source = spans ?? const <LiveMessageSpan>[];
  if (source.isEmpty) {
    return null;
  }

  final parts = <DanmakuContentPart>[];
  for (final span in source) {
    if (span.isText) {
      final text = span.text ?? "";
      if (text.isNotEmpty) {
        parts.add(DanmakuContentPart.text(text));
      }
    } else if (span.isImage) {
      final imageUrl = (span.imageUrl ?? "").trim();
      if (imageUrl.isNotEmpty) {
        parts.add(
          DanmakuContentPart.image(
            imageUrl,
            fallbackText: span.fallbackText,
          ),
        );
      }
    }
  }
  return parts.isEmpty ? null : parts;
}

class MultiRoomRefreshResult {
  const MultiRoomRefreshResult({
    required this.roomKey,
    required this.success,
    this.error,
  });

  final String roomKey;
  final bool success;
  final String? error;
}

/// Controls the visibility and auto-hide timer for one multi-room tile.
///
/// Keeping the timer state separate from the player makes the interaction
/// deterministic and testable without constructing a media player.
class MultiRoomTileControlsVisibility {
  MultiRoomTileControlsVisibility({
    this.hideDelay = const Duration(seconds: 5),
  });

  final Duration hideDelay;
  final visible = true.obs;

  Timer? _hideTimer;
  bool _autoHidePaused = false;
  bool _disposed = false;

  /// Shows the controls and starts a fresh auto-hide countdown.
  void showTemporarily() {
    if (_disposed) return;
    visible.value = true;
    _scheduleHide();
  }

  /// Toggles the controls. Showing them always starts a fresh countdown.
  void toggle() {
    if (_disposed) return;
    if (visible.value) {
      if (_autoHidePaused) return;
      visible.value = false;
      _hideTimer?.cancel();
      _hideTimer = null;
      return;
    }
    showTemporarily();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_autoHidePaused) return;
    _hideTimer = Timer(hideDelay, () {
      if (!_disposed) {
        visible.value = false;
      }
      _hideTimer = null;
    });
  }

  /// Keeps the controls visible while an overlay control is being used.
  void pauseAutoHide() {
    if (_disposed) return;
    _autoHidePaused = true;
    _hideTimer?.cancel();
    _hideTimer = null;
    visible.value = true;
  }

  /// Starts a fresh countdown when the overlay control is closed.
  void resumeAutoHide() {
    if (_disposed || !_autoHidePaused) return;
    _autoHidePaused = false;
    if (visible.value) {
      _scheduleHide();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _hideTimer?.cancel();
    _hideTimer = null;
  }
}

class MultiRoomPlayerController extends GetxController {
  final MultiRoomItem item;
  final void Function()? onPlayerOpened;

  MultiRoomPlayerController(
    this.item, {
    this.onPlayerOpened,
    double? initialVolume,
    bool? initialShowDanmaku,
    int? initialQualityIndex,
    int? initialLineIndex,
    bool initialPaused = false,
    bool initialPlaybackSuspendedForFocus = false,
    bool initialAppActive = true,
    MpvLiveLatencyPlaybackRole initialLiveLatencyRole =
        MpvLiveLatencyPlaybackRole.multiRoomSecondaryOrInactive,
    PlayerMutationQueue? mutationQueue,
  })  : _mutationQueue = mutationQueue ?? PlayerMutationQueue(),
        _ownsMutationQueue = mutationQueue == null,
        _liveLatencyAppActive = initialAppActive,
        _liveLatencyRole = initialLiveLatencyRole {
    if (initialVolume != null) {
      volume.value = initialVolume.clamp(0, 100).toDouble();
    }
    if (initialShowDanmaku != null) {
      showDanmaku.value = initialShowDanmaku;
    }
    _restoreQualityIndex = initialQualityIndex;
    _restoreLineIndex = initialLineIndex;
    paused.value = initialPaused;
    _playbackSuspendedForFocus = initialPlaybackSuspendedForFocus;
  }

  late final Player player = Player(
    configuration: PlayerConfiguration(
      title: item.userName,
      logLevel: AppSettingsController.instance.logEnable.value
          ? MPVLogLevel.info
          // Audio underruns are emitted by libmpv at warning level. Keep this
          // structured health event available without enabling verbose logs.
          : MPVLogLevel.warn,
    ),
  );
  late final VideoController videoController = VideoController(
    player,
    configuration: MpvOptionsService.videoControllerConfiguration(),
  );

  final detail = Rx<LiveRoomDetail?>(null);
  final loading = true.obs;
  final liveStatus = false.obs;
  final errorText = "".obs;
  final muted = true.obs;
  final paused = false.obs;
  final qualityLocked = false.obs;
  final qualityInfo = "".obs;
  final lineInfo = "".obs;

  /// 本格弹幕开关。多开只收不发，不提供发送入口。
  final showDanmaku = true.obs;

  /// 本格独立音量（0-100），互不影响。
  final volume = 100.0.obs;

  /// 本格操作按钮（右下角）是否显示：点格子呼出，5 秒不操作自动隐藏。
  final _tileControls = MultiRoomTileControlsVisibility();
  RxBool get showTileControls => _tileControls.visible;

  /// 取消静音/激活音频时回调（iOS 共享 audio session 会中断其他格，
  /// 由 MultiRoomController 借此恢复所有播放器）。
  VoidCallback? onActivateAudio;

  /// 点击本格画面：呼出/收起本格按钮，并重置 5 秒自动隐藏计时。
  void toggleTileControls() => _tileControls.toggle();

  void pauseTileControlsAutoHide() => _tileControls.pauseAutoHide();

  void resumeTileControlsAutoHide() => _tileControls.resumeAutoHide();

  /// 状态徽标：空=正常；"重试中…"=流错误重试；"弹幕重连…"=弹幕重连。
  final streamStatus = "".obs;

  // --- 流错误自动重试 ---
  int _streamErrorRetryCount = 0;
  DateTime? _lastStreamErrorTime;
  static const int _maxStreamRetry = 3;

  // --- 弹幕断线自动重连 ---
  int _danmakuReconnectCount = 0;
  Timer? _danmakuReconnectTimer;
  bool _danmakuManuallyStopped = false;
  static const int _maxDanmakuReconnect = 5;

  /// 每格一条独立的弹幕长连接。
  late LiveDanmaku liveDanmaku = item.site.liveSite.getDanmaku();

  /// 弹幕渲染层的控制器，由 `DanmakuScreen` 在 build 时回传。
  DanmakuController? danmakuController;

  /// 聊天区竖向弹幕消息列表（独立于画面弹幕，不受弹幕开关控制）。
  final chatMessages = <LiveMessage>[].obs;
  static const int _maxChatMessages = 200;

  /// 重复弹幕去重（对齐正常直播间行为）。
  final List<String> _recentDanmuFingerprints = [];
  static const int _recentDanmuWindow = 10;

  List<LivePlayQuality> _qualities = const [];
  List<String> _playUrls = const [];
  Map<String, String>? _playHeaders;
  int _qualityIndex = -1;
  int _lineIndex = 0;
  bool _disposed = false;
  bool _playerDisposed = false;
  bool _routeTransitionClosed = false;
  Future<void>? _routeTransitionFuture;
  bool _playbackDesired = false;
  bool _playbackSuspendedForFocus = false;
  int _playbackIntentRevision = 0;
  bool _danmakuActive = false;
  Future<void>? _danmakuStopFuture;
  Future<void> _operationChain = Future<void>.value();
  Future<void>? _loadFuture;
  final PlayerMutationQueue _mutationQueue;
  final bool _ownsMutationQueue;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription? _logSubscription;
  bool _isBuffering = false;
  int _bufferingCount = 0;
  Duration _bufferingDuration = Duration.zero;
  DateTime? _bufferingSince;
  DateTime? _lastOpenedAt;
  final MultiRoomLiveLinkHealthCoordinator _liveLinkHealth =
      MultiRoomLiveLinkHealthCoordinator();
  late final MpvLiveLatencyChaseService _liveLatencyChaser =
      MpvLiveLatencyChaseService(
    writeSpeed: _writeLiveLatencyChaseSpeed,
    readSpeed: _readLiveLatencyChaseSpeed,
    onWriteError: (error) => Log.d(
      'multi-room live latency chase speed skipped: '
      '${item.site.id}/${item.roomId} $error',
    ),
  );
  late final MpvLiveLatencyChaseSamplingLoop _liveLatencySamplingLoop =
      MpvLiveLatencyChaseSamplingLoop(
    sample: _sampleLiveLatencyTick,
    nextInterval: _nextLiveLatencySampleDelay,
    onError: (error) => Log.d(
      'multi-room live latency sample skipped: '
      '${item.site.id}/${item.roomId} $error',
    ),
  );
  static const Duration _healthTelemetryInterval = Duration(seconds: 5);
  static const Duration _audioUnderrunProtectionDeduplication =
      Duration(milliseconds: 500);
  bool _liveLatencyAppActive;
  MpvLiveLatencyPlaybackRole _liveLatencyRole;
  LiveStreamProtocol? _activeLiveProtocol;
  DateTime? _nextHealthTelemetryDueAt;
  MultiRoomPlaybackTelemetry? _latestNativeTelemetry;
  DateTime? _lastAudioUnderrunProtectionAt;
  int _liveLatencyControlToken = 0;
  int? _userQualityIndex;
  int? _memoryPressureQualityIndex;

  /// 上次会话的画质/线路索引（布局恢复用，load 后应用）。
  int? _restoreQualityIndex;
  int? _restoreLineIndex;

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

  /// 当前格子的可选清晰度列表。
  List<LivePlayQuality> get qualities => _qualities;

  /// 当前清晰度索引。
  int get qualityIndex => _qualityIndex;

  int? get userQualityIndex => _userQualityIndex;

  bool get isMemoryQualityDegraded => _memoryPressureQualityIndex != null;

  bool get playbackDesired =>
      _playbackDesired && !paused.value && !_playbackSuspendedForFocus;

  bool get shouldRecoverPlayback =>
      !_disposed &&
      !_playerDisposed &&
      !_routeTransitionClosed &&
      playbackDesired &&
      liveStatus.value;

  /// 当前线路列表。
  List<String> get playUrls => _playUrls;

  /// 当前线路索引。
  int get lineIndex => _lineIndex;

  String get title {
    final roomTitle = detail.value?.title.trim();
    if (roomTitle != null && roomTitle.isNotEmpty) {
      return roomTitle;
    }
    return item.userName;
  }

  @override
  void onInit() {
    super.onInit();
    _tileControls.showTemporarily();
    unawaited(MpvOptionsService.applyToPlayer(player));
    // 流错误自动重试（对齐单直播间行为）。
    player.stream.error.listen((event) {
      if (_disposed || paused.value || !liveStatus.value) return;
      if (_isStreamError(event)) {
        unawaited(_handleStreamError(event));
      }
    });
    _bufferingSubscription =
        player.stream.buffering.listen(_onBufferingChanged);
    _logSubscription = player.stream.log.listen((event) {
      final type = classifyMpvLiveLinkLog(
        prefix: event.prefix,
        text: event.text,
      );
      if (type != null) {
        _liveLinkHealth.recordEvent(type);
        if (type == LiveLinkEventType.audioUnderrun) {
          _protectLiveLatencyForAudioUnderrun();
        }
      }
    });
    unawaited(load());
  }

  static bool _isStreamError(String error) {
    return error.contains('mbedtls_ssl_read') ||
        error.contains('Packet corrupt') ||
        error.contains('Packet corupt') ||
        error.contains('tls:') ||
        error.contains('Invalid NAL unit') ||
        error.contains('missing picture');
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _mutationQueue.run<void>(() async {
      if (_disposed || _routeTransitionClosed) return;
      await operation();
    });
    _operationChain = result.catchError((Object _) {});
    return result;
  }

  void _onBufferingChanged(bool value) {
    if (_disposed || paused.value) return;
    final now = DateTime.now();
    _liveLinkHealth.recordBuffering(value, at: now);
    if (value && !_isBuffering) {
      _isBuffering = true;
      _bufferingCount += 1;
      _bufferingSince = now;
      unawaited(
        _liveLatencyChaser.protect(
          sampledAt: now,
          reason: MpvLiveLatencyProtectionReason.buffering,
          generation: _liveLatencyChaser.generation,
        ),
      );
    } else if (!value && _isBuffering) {
      _finishBuffering(now);
    }
  }

  void _protectLiveLatencyForAudioUnderrun() {
    final now = DateTime.now();
    final previous = _lastAudioUnderrunProtectionAt;
    if (previous != null &&
        now.difference(previous) < _audioUnderrunProtectionDeduplication) {
      return;
    }
    _lastAudioUnderrunProtectionAt = now;
    unawaited(
      _liveLatencyChaser.protect(
        sampledAt: now,
        reason: MpvLiveLatencyProtectionReason.audioUnderrun,
        generation: _liveLatencyChaser.generation,
      ),
    );
  }

  void _finishBuffering(DateTime now) {
    final since = _bufferingSince;
    if (since != null) {
      _bufferingDuration += now.difference(since);
    }
    _bufferingSince = null;
    _isBuffering = false;
  }

  MultiRoomPlaybackTelemetry telemetrySnapshot({
    DateTime? sampledAt,
    double? bandwidthBytesPerSecond,
    double? demuxerCacheDurationSeconds,
    int? width,
    int? height,
    double? framesPerSecond,
    bool isPrimary = false,
    bool isFocused = false,
    bool isChatTarget = false,
  }) {
    final now = sampledAt ?? DateTime.now();
    final ongoing = _isBuffering && _bufferingSince != null
        ? now.difference(_bufferingSince!)
        : Duration.zero;
    return MultiRoomPlaybackTelemetry(
      roomKey: item.key,
      sampledAt: now,
      paused: paused.value,
      isBuffering: _isBuffering,
      bufferingCount: _bufferingCount,
      bufferingDuration: _bufferingDuration + ongoing,
      qualityIndex: _qualityIndex,
      qualityCount: _qualities.length,
      userTargetQualityIndex: _userQualityIndex,
      // Keep this null when the backend cannot expose libmpv's raw-input-rate;
      // unknown bandwidth must not be interpreted as zero.
      bandwidthBytesPerSecond: bandwidthBytesPerSecond,
      demuxerCacheDurationSeconds: demuxerCacheDurationSeconds,
      width: width,
      height: height,
      framesPerSecond: framesPerSecond,
      lastOpenedAt: _lastOpenedAt,
      isQualityLocked: qualityLocked.value,
      isPrimary: isPrimary,
      isFocused: isFocused,
      isChatTarget: isChatTarget,
    );
  }

  /// Returns the latest snapshot produced by the shared per-player sampling
  /// loop. This method intentionally performs no native reads and never feeds
  /// the latency chaser, so the 5-second adaptive-quality pass cannot sample
  /// `demuxer-cache-duration` a second time.
  Future<MultiRoomPlaybackTelemetry> sampleTelemetry({
    DateTime? sampledAt,
    bool isPrimary = false,
    bool isFocused = false,
    bool isChatTarget = false,
  }) async {
    final now = sampledAt ?? DateTime.now();
    final latest = _latestNativeTelemetry;
    return telemetrySnapshot(
      // Preserve the native sample age. Re-labelling a stale cached reading
      // with `now` would make adaptive quality treat old telemetry as fresh.
      sampledAt: latest?.sampledAt ?? now,
      bandwidthBytesPerSecond: latest?.bandwidthBytesPerSecond,
      demuxerCacheDurationSeconds: latest?.demuxerCacheDurationSeconds,
      width: latest?.width,
      height: latest?.height,
      framesPerSecond: latest?.framesPerSecond,
      isPrimary: isPrimary,
      isFocused: isFocused,
      isChatTarget: isChatTarget,
    );
  }

  Duration? _nextLiveLatencySampleDelay() {
    if (!_isLiveHealthSamplingEligible) return null;
    return MpvLiveLatencyChaseSamplingLoop.nextDelay(
      chaseInterval: _isLiveLatencyChaseEligible
          ? _liveLatencyChaser.recommendedSampleInterval
          : null,
      healthDueAt: _nextHealthTelemetryDueAt,
    );
  }

  bool get _isLiveHealthSamplingEligible =>
      !_disposed &&
      !_playerDisposed &&
      !_routeTransitionClosed &&
      shouldSampleMultiRoomLiveHealth(
        appActive: _liveLatencyAppActive,
        paused: paused.value,
        playbackDesired: playbackDesired,
        liveStatus: liveStatus.value,
        hasActiveSource:
            _activeLiveProtocol != null && _liveLinkHealth.current != null,
      );

  bool get _isLiveLatencyChaseEligible => shouldChaseMultiRoomLiveLatency(
        healthSamplingEligible: _isLiveHealthSamplingEligible,
        role: _liveLatencyRole,
      );

  Future<void> _sampleLiveLatencyTick() async {
    if (!_isLiveHealthSamplingEligible) return;
    final controlToken = _liveLatencyControlToken;
    final healthGeneration = _liveLinkHealth.current;
    final chaseGeneration = _liveLatencyChaser.generation;
    if (healthGeneration == null ||
        !_isCurrentLiveLatencySamplingContext(
          controlToken: controlToken,
          healthGeneration: healthGeneration,
          chaseGeneration: chaseGeneration,
        )) {
      return;
    }
    final sampledAt = DateTime.now();
    final healthDueAt = _nextHealthTelemetryDueAt;
    final includeHealthTelemetry =
        healthDueAt == null || !sampledAt.isBefore(healthDueAt);
    if (includeHealthTelemetry) {
      // Reserve the next low-frequency slot before any async/native work. A
      // temporarily unavailable backend or a rejected stale read must not
      // turn an overdue health deadline into a zero-delay spin loop.
      _nextHealthTelemetryDueAt = sampledAt.add(_healthTelemetryInterval);
    }
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final properties = <String>[
      mpvDemuxerCacheDurationProperty,
      if (includeHealthTelemetry) ...[
        mpvCacheSpeedProperty,
        mpvVideoWidthProperty,
        mpvVideoHeightProperty,
        mpvEstimatedFpsProperty,
        health_telemetry.mpvVideoBitrateProperty,
        health_telemetry.mpvAudioBitrateProperty,
        health_telemetry.mpvSpeedProperty,
      ],
    ];
    final values = await Future.wait([
      for (final property in properties)
        _readNativeProperty(platform, property),
    ]);
    final raw = <String, String?>{
      for (var index = 0; index < properties.length; index += 1)
        properties[index]: values[index],
    };
    if (!_isCurrentLiveLatencySamplingContext(
      controlToken: controlToken,
      healthGeneration: healthGeneration,
      chaseGeneration: chaseGeneration,
    )) {
      return;
    }
    final native = parseMpvTelemetryProperties(raw);
    if (_isLiveLatencyChaseEligible) {
      await _liveLatencyChaser.observe(
        cacheDurationSeconds: native.demuxerCacheDurationSeconds,
        isBuffering: _isBuffering || !player.state.playing,
        sampledAt: sampledAt,
        generation: chaseGeneration,
      );
    }
    if (!includeHealthTelemetry ||
        !_isCurrentLiveLatencySamplingContext(
          controlToken: controlToken,
          healthGeneration: healthGeneration,
          chaseGeneration: chaseGeneration,
        )) {
      return;
    }
    final throughput = health_telemetry.parseMpvLiveHealthThroughputProperties(
      cacheSpeed: raw[mpvCacheSpeedProperty],
      videoBitrate: raw[health_telemetry.mpvVideoBitrateProperty],
      audioBitrate: raw[health_telemetry.mpvAudioBitrateProperty],
    );
    final state = player.state;
    final speed = double.tryParse(
          raw[health_telemetry.mpvSpeedProperty]?.trim() ?? '',
        ) ??
        _liveLatencyChaser.currentSpeed;
    final summary = _liveLinkHealth.addSample(
      generation: healthGeneration,
      sample: LiveLinkHealthSample(
        generation: healthGeneration.generation,
        sampledAt: sampledAt,
        position: state.position,
        playing: state.playing,
        buffering: state.buffering,
        playbackSpeed: speed.isFinite && speed > 0 ? speed : 1,
        streamActive: state.playing || state.buffering,
        demuxerCacheSeconds: native.demuxerCacheDurationSeconds,
        receiveBytesPerSecond: throughput.receiveBytesPerSecond,
        estimatedMediaBitsPerSecond: throughput.estimatedMediaBitsPerSecond,
      ),
    );
    if (summary != null) Log.writeLog(summary);
    _latestNativeTelemetry = telemetrySnapshot(
      sampledAt: sampledAt,
      bandwidthBytesPerSecond: native.bandwidthBytesPerSecond,
      demuxerCacheDurationSeconds: native.demuxerCacheDurationSeconds,
      width: native.width,
      height: native.height,
      framesPerSecond: native.framesPerSecond,
    );
  }

  bool _isCurrentLiveLatencySamplingContext({
    required int controlToken,
    required MultiRoomLiveLinkHealthGeneration healthGeneration,
    required int chaseGeneration,
  }) {
    return controlToken == _liveLatencyControlToken &&
        chaseGeneration == _liveLatencyChaser.generation &&
        _isLiveHealthSamplingEligible &&
        _isCurrentHealthGeneration(healthGeneration);
  }

  /// Updates whether this tile is allowed to run the latency/health sampler.
  /// Every active tile retains the 5-second health cadence, while only the
  /// currently visible primary tile enables chase observations and cadence.
  Future<void> updateLiveLatencyParticipation({
    required MpvLiveLatencyPlaybackRole role,
    required bool appActive,
  }) async {
    if (_liveLatencyRole == role && _liveLatencyAppActive == appActive) {
      return;
    }
    _liveLatencyRole = role;
    _liveLatencyAppActive = appActive;
    final reason = appActive
        ? MpvLiveLatencyProtectionReason.sourceChanged
        : MpvLiveLatencyProtectionReason.lifecycleInterrupted;
    await _stopLiveLatencySampling(reason: reason);
    if (_isLiveHealthSamplingEligible) {
      await _startLiveLatencySampling();
    }
  }

  Future<void> _startLiveLatencySampling() async {
    final protocol = _activeLiveProtocol;
    if (protocol == null || !_isLiveHealthSamplingEligible) return;
    final controlToken = ++_liveLatencyControlToken;
    _liveLatencySamplingLoop.stop();
    await _liveLatencyChaser.start(
      latencyMode: AppSettingsController.instance.mpvLiveLatencyMode.value,
      protocol: protocol,
      platformProfile: PlatformUtils.isMobileApp
          ? MpvLiveLatencyPlatformProfile.resourceConstrained
          : MpvLiveLatencyPlatformProfile.conservative,
      playbackRole: _liveLatencyRole,
    );
    if (controlToken != _liveLatencyControlToken ||
        !_isLiveHealthSamplingEligible) {
      return;
    }
    _nextHealthTelemetryDueAt = DateTime.now();
    _liveLatencySamplingLoop.start();
  }

  Future<void> _stopLiveLatencySampling({
    required MpvLiveLatencyProtectionReason reason,
  }) async {
    _liveLatencyControlToken += 1;
    _liveLatencySamplingLoop.stop();
    _nextHealthTelemetryDueAt = null;
    _latestNativeTelemetry = null;
    _lastAudioUnderrunProtectionAt = null;
    final generation = _liveLatencyChaser.generation;
    await _liveLatencyChaser.protect(
      reason: reason,
      generation: generation,
    );
    await _liveLatencyChaser.stop();
  }

  bool _isCurrentHealthGeneration(
    MultiRoomLiveLinkHealthGeneration generation,
  ) {
    if (_disposed || _playerDisposed) return false;
    final current = _liveLinkHealth.current;
    if (current == null ||
        current.generation != generation.generation ||
        current.source != generation.source) {
      return false;
    }
    final playlist = player.state.playlist;
    if (playlist.medias.isEmpty ||
        playlist.index < 0 ||
        playlist.index >= playlist.medias.length) {
      return false;
    }
    final dynamic media = playlist.medias[playlist.index];
    final source = canonicalizeLivePlaybackSource(
      media.uri?.toString() ?? '',
    );
    return source == generation.source;
  }

  Future<String?> _readNativeProperty(
    NativePlayer nativePlayer,
    String property,
  ) async {
    try {
      // NativePlayer's web stub intentionally omits getProperty. The runtime
      // type check above plus a dynamic call keeps web compilation safe.
      final dynamic native = nativePlayer;
      final dynamic value = await native.getProperty(property);
      return value is String ? value : value?.toString();
    } catch (_) {
      return null;
    }
  }

  /// 流错误自动重试：最多 3 次，每次重开当前线路。
  Future<void> _handleStreamError(String error) {
    return _enqueue(() => _handleStreamErrorInternal(error));
  }

  Future<void> _handleStreamErrorInternal(String error) async {
    final now = DateTime.now();
    if (_lastStreamErrorTime != null &&
        now.difference(_lastStreamErrorTime!) < const Duration(seconds: 2)) {
      return;
    }
    _lastStreamErrorTime = now;
    if (_streamErrorRetryCount >= _maxStreamRetry) {
      Log.e("多开流错误重试次数已达上限：${item.site.id}/${item.roomId} $error",
          StackTrace.current);
      streamStatus.value = "";
      errorText.value = "播放中断，请手动刷新";
      return;
    }
    _streamErrorRetryCount += 1;
    streamStatus.value = "重试中($_streamErrorRetryCount/$_maxStreamRetry)…";
    Log.w("多开检测到流错误，自动重试：${item.site.id}/${item.roomId} $error", false);
    await Future.delayed(const Duration(seconds: 1));
    if (_disposed || paused.value) return;
    try {
      await player.pause();
      await Future.delayed(const Duration(milliseconds: 200));
      await _openCurrentUrl(
        automaticReconnectReason: LiveReconnectReason.mediaError,
      );
      streamStatus.value = "";
    } catch (e) {
      Log.e("多开重启解码器失败：${item.site.id}/${item.roomId} $e", StackTrace.current);
      streamStatus.value = "";
    }
  }

  Future<void> load() {
    final activeLoad = _loadFuture;
    if (activeLoad != null) return activeLoad;
    final result = _enqueue(_loadInternal);
    _loadFuture = result;
    void clearActiveLoad() {
      if (identical(_loadFuture, result)) _loadFuture = null;
    }

    unawaited(result.then<void>(
      (_) => clearActiveLoad(),
      onError: (Object _, StackTrace __) => clearActiveLoad(),
    ));
    return result;
  }

  /// 读取多开格子房间详情。
  ///
  /// 快手请求通过 [KuaishouRequestTrace] 标记为多开来源，保留高优先级但
  /// 仍遵守协调器最小间隔，避免多个格子形成突发请求；其他平台不标记来源。
  Future<LiveRoomDetail> _fetchRoomDetail() {
    if (item.site.id != Constant.kKuaishou) {
      return item.site.liveSite.getRoomDetail(roomId: item.roomId);
    }
    return KuaishouRequestTrace.run(
      KuaishouRequestSource.multiRoom,
      () => item.site.liveSite.getRoomDetail(roomId: item.roomId),
    );
  }

  Future<void> _loadInternal() async {
    loading.value = true;
    errorText.value = "";
    liveStatus.value = false;
    _playbackDesired = false;
    if (_qualityIndex >= 0) {
      _restoreQualityIndex = _qualityIndex;
    }
    if (_lineIndex >= 0) {
      _restoreLineIndex = _lineIndex;
    }
    try {
      await _stopLiveLatencySampling(
        reason: MpvLiveLatencyProtectionReason.sourceChanged,
      );
      _activeLiveProtocol = null;
      _liveLinkHealth.stop();
      await player.stop();
      if (_disposed) return;
      // 重新加载前断开旧连接，避免刷新后同一格挂着两条长连接。
      await _stopDanmaku();
      chatMessages.clear();
      _recentDanmuFingerprints.clear();
      final roomDetail = await _fetchRoomDetail();
      if (_disposed) {
        return;
      }
      detail.value = roomDetail;
      liveStatus.value = roomDetail.status || roomDetail.isRecord;
      if (!liveStatus.value) {
        return;
      }
      await _loadQualities(roomDetail);
      if (_disposed) return;
      await _loadPlayUrls(roomDetail);
      if (_disposed) return;
      await _openCurrentUrl();
      if (_disposed) return;
      unawaited(_startDanmaku(roomDetail));
    } catch (e) {
      Log.e(
        "多开直播间加载失败：${item.site.id}/${item.roomId} $e",
        StackTrace.current,
      );
      errorText.value = e.toString();
    } finally {
      if (!_disposed) {
        loading.value = false;
      }
    }
  }

  Future<void> _loadQualities(LiveRoomDetail roomDetail) async {
    _qualities = await item.site.liveSite.getPlayQualites(detail: roomDetail);
    if (_qualities.isEmpty) {
      throw Exception("无法读取播放清晰度");
    }
    // 优先恢复上次会话的画质。
    final restore = _restoreQualityIndex;
    _restoreQualityIndex = null;
    if (restore != null && restore >= 0 && restore < _qualities.length) {
      _qualityIndex = restore;
      qualityInfo.value = _qualities[_qualityIndex].quality;
      _userQualityIndex ??= _qualityIndex;
      return;
    }
    final qualityLevel = AppSettingsController.instance.qualityLevel.value;
    if (qualityLevel == 2) {
      _qualityIndex = 0;
    } else if (qualityLevel == 0) {
      _qualityIndex = _qualities.length - 1;
    } else {
      _qualityIndex = (_qualities.length / 2).floor();
    }
    qualityInfo.value = _qualities[_qualityIndex].quality;
    _userQualityIndex ??= _qualityIndex;
  }

  Future<void> _loadPlayUrls(LiveRoomDetail roomDetail) async {
    final playUrl = await item.site.liveSite.getPlayUrls(
      detail: roomDetail,
      quality: _qualities[_qualityIndex],
    );
    if (playUrl.urls.isEmpty) {
      throw Exception("无法读取播放地址");
    }
    _playUrls = sortLiveStreamUrlsByLatency(playUrl.urls);
    _playHeaders = playUrl.headers;
    final restore = _restoreLineIndex;
    _restoreLineIndex = null;
    final bestLineIndices = lowestLatencyLineIndices(_playUrls);
    final autoSelect =
        AppSettingsController.instance.autoSelectFastestLine.value;
    _lineIndex = bestLineIndices.first;
    if (!autoSelect &&
        restore != null &&
        restore >= 0 &&
        restore < _playUrls.length &&
        bestLineIndices.contains(restore)) {
      _lineIndex = restore;
    } else if (autoSelect && bestLineIndices.length > 1) {
      final candidates = [
        for (final index in bestLineIndices) _playUrls[index],
      ];
      final fastest = await NetworkDiagnoseService.findFastestLine(candidates);
      final candidateIndex = fastest.clamp(0, candidates.length - 1).toInt();
      _lineIndex = bestLineIndices[candidateIndex];
    }
    lineInfo.value = "线路${_lineIndex + 1}";
  }

  Future<void> _openCurrentUrl({
    LiveLinkEventType? userOperation,
    LiveReconnectReason? automaticReconnectReason,
  }) async {
    if (_disposed || _routeTransitionClosed || _playUrls.isEmpty) return;
    final previousSource = _liveLinkHealth.current?.source;
    final reconnectStartedAt =
        automaticReconnectReason == null ? null : DateTime.now();
    var url = _playUrls[_lineIndex];
    if (AppSettingsController.instance.playerForceHttps.value) {
      url = url.replaceAll("http://", "https://");
    }
    await _stopLiveLatencySampling(
      reason: MpvLiveLatencyProtectionReason.sourceChanged,
    );
    _activeLiveProtocol = null;
    if (_disposed || _routeTransitionClosed) return;
    final healthOpenAttempt = _liveLinkHealth.prepareSource(source: url);
    final protocol = classifyLiveStreamProtocol(url);
    await MpvOptionsService.applyLiveLatencyOptions(player, protocol);
    if (_disposed || _routeTransitionClosed) return;
    _playbackDesired = true;
    await player.open(
      Media(url, httpHeaders: _playHeaders),
      play: playbackDesired,
    );
    if (_disposed || _routeTransitionClosed) return;
    final completedAt = DateTime.now();
    final healthGeneration = _liveLinkHealth.beginSource(
      target: '${item.site.id}/${item.roomId}',
      openAttempt: healthOpenAttempt,
      openedAt: completedAt,
      userOperation: userOperation,
    );
    if (healthGeneration == null) return;
    _activeLiveProtocol = protocol;
    _lastOpenedAt = completedAt;
    if (automaticReconnectReason != null &&
        reconnectStartedAt != null &&
        _isCurrentHealthGeneration(healthGeneration)) {
      _liveLinkHealth.recordEvent(
        LiveLinkEventType.cdnReconnect,
        at: completedAt,
        reconnectReason: automaticReconnectReason,
        reconnectHostChanged: didLivePlaybackHostChange(
          previousSource,
          url,
        ),
        reconnectRecoveryDuration: completedAt.difference(reconnectStartedAt),
        expectedGeneration: healthGeneration,
      );
    }
    await player.setVolume(muted.value ? 0 : volume.value);
    if (paused.value) {
      await player.pause();
    }
    if (_isLiveHealthSamplingEligible) {
      await _startLiveLatencySampling();
    }
    // iOS 上多个 libmpv Player 共享 audio session。任意一格重新 open
    // 都可能中断其他格，由页面级控制器统一恢复仍应播放的播放器。
    if (!_disposed) {
      onPlayerOpened?.call();
    }
  }

  /// iOS 上其他 Player.open() 可能抢占共享音频会话。首轮仅幂等发起
  /// play；只有播放位置仍不推进的格子才在重试时执行 pause/play，重建
  /// 已被中断的原生输出。
  Future<void> ensurePlaying(bool forceRestart) {
    return _enqueue(() async {
      if (_disposed || !playbackDesired || !liveStatus.value) {
        return;
      }
      if (forceRestart) {
        await player.pause();
        if (_disposed || !playbackDesired || !liveStatus.value) {
          return;
        }
      }
      await player.play();
    });
  }

  /// Temporarily pauses a tile that is hidden by focus mode without changing
  /// the user's explicit paused state.
  Future<void> setFocusSuspended(bool value) {
    if (_playbackSuspendedForFocus == value) {
      return Future<void>.value();
    }
    _playbackSuspendedForFocus = value;
    if (value && _isBuffering) {
      _finishBuffering(DateTime.now());
    }
    return _enqueue(() async {
      if (_disposed || _playbackSuspendedForFocus != value) {
        return;
      }
      if (value) {
        await _stopLiveLatencySampling(
          reason: MpvLiveLatencyProtectionReason.lifecycleInterrupted,
        );
        if (_disposed || _playbackSuspendedForFocus != value) {
          return;
        }
        await player.pause();
      } else if (playbackDesired && liveStatus.value) {
        await player.play();
        if (_disposed || _playbackSuspendedForFocus != value) {
          return;
        }
        await _startLiveLatencySampling();
      }
    });
  }

  /// Waits for media time to advance instead of trusting `state.playing`.
  ///
  /// media_kit sets its Dart-side playing state to true before the native mpv
  /// command has proved that decoding resumed. Position movement is the
  /// observable signal that the live stream is really running.
  Future<bool> waitUntilActuallyPlaying(Duration timeout) async {
    if (!shouldRecoverPlayback) return true;

    final initialPosition = player.state.position;
    StreamSubscription<Duration>? subscription;
    final completer = Completer<bool>();
    try {
      subscription = player.stream.position.listen(
        (position) {
          if (!shouldRecoverPlayback && !completer.isCompleted) {
            completer.complete(true);
            return;
          }
          final delta = (position - initialPosition).inMilliseconds.abs();
          if (delta >= 20 && !completer.isCompleted) {
            completer.complete(true);
          }
        },
        onError: (Object _, StackTrace __) {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      return await completer.future.timeout(
        timeout,
        onTimeout: () => !shouldRecoverPlayback,
      );
    } catch (_) {
      return !shouldRecoverPlayback;
    } finally {
      await subscription?.cancel();
    }
  }

  /// Applies the user's explicit playback intent. Reopens and lifecycle
  /// recovery never override this state.
  Future<void> setPaused(bool value) {
    if (paused.value == value) return Future<void>.value();
    final intentRevision = ++_playbackIntentRevision;
    paused.value = value;
    _liveLinkHealth.recordEvent(
      value
          ? LiveLinkEventType.playbackPausedByUser
          : LiveLinkEventType.playbackResumedByUser,
    );
    if (value && _isBuffering) {
      _finishBuffering(DateTime.now());
    }
    // Queue the native mutation immediately so rapid pause/resume taps retain
    // their intent order. The revision checks discard work that became stale
    // while an asynchronous stop/play operation was in flight.
    return _enqueue(() async {
      if (intentRevision != _playbackIntentRevision || paused.value != value) {
        return;
      }
      if (value) {
        await _stopLiveLatencySampling(
          reason: MpvLiveLatencyProtectionReason.userPaused,
        );
        if (intentRevision != _playbackIntentRevision ||
            paused.value != value) {
          return;
        }
        await player.pause();
      } else if (playbackDesired && liveStatus.value) {
        await player.play();
        if (intentRevision != _playbackIntentRevision ||
            paused.value != value) {
          return;
        }
        await _startLiveLatencySampling();
        if (intentRevision != _playbackIntentRevision ||
            paused.value != value) {
          return;
        }
        // 恢复播放激活 audio session，可能中断其他格，通知恢复。
        onActivateAudio?.call();
      }
    });
  }

  Future<void> togglePaused() => setPaused(!paused.value);

  void recordLiveLinkHealthEvent(LiveLinkEventType type) {
    _liveLinkHealth.recordEvent(type);
  }

  /// 切换本格清晰度（独立于其他格）。
  Future<void> changeQuality(
    int index, {
    bool userInitiated = true,
  }) {
    if (index < 0 || index >= _qualities.length) {
      return Future<void>.value();
    }
    if (userInitiated) {
      _userQualityIndex = index;
      qualityLocked.value = true;
      if (_memoryPressureQualityIndex != null) {
        // Remember the newest user target, but retain the emergency override.
        _memoryPressureQualityIndex = index;
        return Future<void>.value();
      }
    }
    return _enqueue(() async {
      if (index == _qualityIndex) {
        return;
      }
      _qualityIndex = index;
      qualityInfo.value = _qualities[index].quality;
      final roomDetail = detail.value;
      if (roomDetail == null) return;
      try {
        await _loadPlayUrls(roomDetail);
        if (_disposed) return;
        await _openCurrentUrl(
          userOperation:
              userInitiated ? LiveLinkEventType.qualityChangedByUser : null,
        );
      } catch (e) {
        Log.e(
            "多开切换清晰度失败：${item.site.id}/${item.roomId} $e", StackTrace.current);
        errorText.value = e.toString();
      }
    });
  }

  Future<void> changeQualityAutomatically(int index) {
    if (qualityLocked.value || _memoryPressureQualityIndex != null) {
      return Future<void>.value();
    }
    return changeQuality(index, userInitiated: false);
  }

  void useAutomaticQuality() {
    qualityLocked.value = false;
  }

  /// 切换本格线路（独立于其他格）。
  Future<void> changeLine(int index) {
    return _enqueue(() async {
      if (index < 0 || index >= _playUrls.length || index == _lineIndex) {
        return;
      }
      _lineIndex = index;
      lineInfo.value = "线路${_lineIndex + 1}";
      try {
        await _openCurrentUrl(
          userOperation: LiveLinkEventType.lineChangedByUser,
        );
      } catch (e) {
        Log.e("多开切换线路失败：${item.site.id}/${item.roomId} $e", StackTrace.current);
        errorText.value = e.toString();
      }
    });
  }

  /// 低内存降级：暂停本格弹幕连接（降级状态由调用方记录）。
  Future<void> degradeDanmaku() async {
    await _stopDanmaku();
    danmakuController?.clear();
  }

  /// 低内存恢复：重建本格弹幕连接。
  Future<void> restoreDanmaku() async {
    final roomDetail = detail.value;
    if (_disposed ||
        _danmakuActive ||
        roomDetail == null ||
        !liveStatus.value) {
      return;
    }
    await _startDanmaku(roomDetail);
  }

  /// 低内存降级：切到最低清晰度（若当前不是最低）。
  Future<void> degradeQuality() async {
    if (_qualities.length <= 1 || _qualityIndex == _qualities.length - 1) {
      return;
    }
    _memoryPressureQualityIndex ??= _userQualityIndex ?? _qualityIndex;
    await changeQuality(
      _qualities.length - 1,
      userInitiated: false,
    );
  }

  /// Restores the most recent user target after a temporary memory override.
  Future<void> restoreQualityAfterMemoryPressure() async {
    final target = _memoryPressureQualityIndex;
    _memoryPressureQualityIndex = null;
    if (target == null || target < 0 || target >= _qualities.length) return;
    await changeQuality(target, userInitiated: false);
  }

  /// 由 `DanmakuScreen` 创建后回传渲染控制器。
  void initDanmakuController(DanmakuController e) {
    danmakuController = e;
  }

  Future<void> _startDanmaku(LiveRoomDetail roomDetail) async {
    final pendingStop = _danmakuStopFuture;
    if (pendingStop != null) {
      await pendingStop;
    }
    if (_disposed || _danmakuActive) return;
    _danmakuActive = true;
    _danmakuManuallyStopped = false;
    liveDanmaku.onMessage = _onDanmakuMessage;
    liveDanmaku.onClose = (msg) {
      _danmakuActive = false;
      Log.d("多开弹幕关闭：${item.site.id}/${item.roomId} $msg");
      _addSysMessage(msg);
      _scheduleDanmakuReconnect();
    };
    liveDanmaku.onReady = () {
      Log.d("多开弹幕已连接：${item.site.id}/${item.roomId}");
      _danmakuReconnectCount = 0;
      _danmakuReconnectTimer?.cancel();
      streamStatus.value = "";
    };
    try {
      await liveDanmaku.start(roomDetail.danmakuData);
    } catch (e) {
      _danmakuActive = false;
      if (!_disposed && !_danmakuManuallyStopped) {
        // 弹幕连不上不影响看画面，只记日志。
        Log.e("多开弹幕启动失败：${item.site.id}/${item.roomId} $e", StackTrace.current);
        _addSysMessage("弹幕连接失败");
      }
    }
  }

  /// 弹幕意外断开后指数退避自动重连（3s/6s/12s…最多 5 次）。
  void _scheduleDanmakuReconnect() {
    if (_disposed || _danmakuManuallyStopped || !liveStatus.value) {
      return;
    }
    if (_danmakuReconnectCount >= _maxDanmakuReconnect) {
      streamStatus.value = "";
      return;
    }
    _danmakuReconnectCount += 1;
    streamStatus.value = "弹幕重连($_danmakuReconnectCount/$_maxDanmakuReconnect)…";
    final delay = Duration(seconds: 3 * (1 << (_danmakuReconnectCount - 1)));
    _danmakuReconnectTimer?.cancel();
    _danmakuReconnectTimer = Timer(delay, () {
      if (_disposed || _danmakuManuallyStopped || !liveStatus.value) {
        return;
      }
      final roomDetail = detail.value;
      if (roomDetail != null) {
        unawaited(_startDanmaku(roomDetail));
      }
    });
  }

  /// 追加一条系统消息到聊天区（对齐正常直播间 LiveSysMessage 样式）。
  void _addSysMessage(String msg) {
    if (_disposed || msg.isEmpty) return;
    chatMessages.add(
      LiveMessage(
        type: LiveMessageType.chat,
        userName: "LiveSysMessage",
        message: msg,
        color: LiveMessageColor.white,
      ),
    );
    while (chatMessages.length > _maxChatMessages) {
      chatMessages.removeAt(0);
    }
  }

  /// 用户/关键词/重复弹幕过滤（对齐正常直播间行为）。
  bool _shouldFilterDanmu(LiveMessage msg) {
    final settings = AppSettingsController.instance;
    if (settings.shouldShieldUser(msg.userName, siteId: item.site.id)) {
      Log.d("多开过滤被屏蔽用户: ${msg.userName}");
      return true;
    }
    if (settings.danmuShieldEnable.value &&
        settings.danmuKeywordShieldEnable.value) {
      for (final keyword in settings.shieldList) {
        Pattern? pattern;
        if (Utils.isRegexFormat(keyword)) {
          final removedSlash = Utils.removeRegexFormat(keyword);
          try {
            pattern = RegExp(removedSlash);
          } catch (e) {
            Log.d("正则屏蔽词 $keyword 无法编译，已跳过");
          }
        } else {
          pattern = keyword;
        }
        if (pattern != null && msg.message.contains(pattern)) {
          Log.d("多开命中屏蔽词 $keyword");
          return true;
        }
      }
    }
    if (settings.danmuDedupeEnable.value) {
      final fingerprint = "${msg.userName}|${msg.message}";
      if (_recentDanmuFingerprints.contains(fingerprint)) {
        return true;
      }
      _recentDanmuFingerprints.add(fingerprint);
      if (_recentDanmuFingerprints.length > _recentDanmuWindow) {
        _recentDanmuFingerprints.removeAt(0);
      }
    }
    return false;
  }

  void _onDanmakuMessage(LiveMessage msg) {
    if (_disposed || msg.type != LiveMessageType.chat || !liveStatus.value) {
      return;
    }
    // 对齐正常直播间：屏蔽/去重过滤后仍记录到聊天区（不受弹幕开关控制）。
    if (_shouldFilterDanmu(msg)) {
      return;
    }
    chatMessages.add(msg);
    while (chatMessages.length > _maxChatMessages) {
      chatMessages.removeAt(0);
    }
    // 画面弹幕由开关控制。
    if (!showDanmaku.value) return;
    final settings = AppSettingsController.instance;
    final renderEmoji = settings.danmuRenderEmoji.value;
    final parts =
        renderEmoji ? buildMultiRoomDanmakuContentParts(msg.spans) : null;
    danmakuController?.addDanmaku(
      DanmakuContentItem(
        msg.message,
        color: Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b),
        imageUrls: renderEmoji && parts == null ? msg.imageUrls : null,
        parts: parts,
      ),
    );
  }

  Future<void> _stopDanmaku() {
    final activeStop = _danmakuStopFuture;
    if (activeStop != null) return activeStop;
    late final Future<void> trackedStop;
    trackedStop = _stopDanmakuInternal().whenComplete(() {
      if (identical(_danmakuStopFuture, trackedStop)) {
        _danmakuStopFuture = null;
      }
    });
    _danmakuStopFuture = trackedStop;
    return trackedStop;
  }

  Future<void> _stopDanmakuInternal() async {
    _danmakuManuallyStopped = true;
    _danmakuActive = false;
    _danmakuReconnectTimer?.cancel();
    liveDanmaku.onMessage = null;
    liveDanmaku.onClose = null;
    liveDanmaku.onReady = null;
    try {
      await liveDanmaku.stop();
    } catch (e) {
      Log.d("多开弹幕停止异常：${item.site.id}/${item.roomId} $e");
    }
    danmakuController?.clear();
    // stop() 后的实例不可复用，重新取一个干净的。
    liveDanmaku = item.site.liveSite.getDanmaku();
  }

  void toggleDanmaku() {
    showDanmaku.value = !showDanmaku.value;
    if (!showDanmaku.value) {
      danmakuController?.clear();
    }
  }

  Future<MultiRoomRefreshResult> refreshRoom({bool showToast = true}) async {
    await load();
    final error = errorText.value.trim();
    final result = MultiRoomRefreshResult(
      roomKey: item.key,
      success: error.isEmpty,
      error: error.isEmpty ? null : error,
    );
    if (showToast) {
      SmartDialog.showToast(
        result.success ? "已刷新 ${item.userName}" : "刷新失败 ${item.userName}",
      );
    }
    return result;
  }

  Future<void> toggleMute() async {
    await setMuted(!muted.value);
  }

  Future<void> setMuted(bool value) async {
    if (muted.value == value) return;
    muted.value = value;
    await player.setVolume(muted.value ? 0 : volume.value);
    // 取消静音激活 audio session，可能中断其他格，通知恢复。
    if (!muted.value && volume.value > 0) {
      onActivateAudio?.call();
    }
  }

  /// 设置本格音量（0-100）。静音归属只由 [setMuted] 控制。
  Future<void> setVolume(double value) async {
    volume.value = value.clamp(0, 100).toDouble();
    if (muted.value) {
      await player.setVolume(0);
    } else {
      await player.setVolume(volume.value);
      if (volume.value > 0) {
        onActivateAudio?.call();
      }
    }
  }

  /// Stops native resources before the focused room opens as a single room.
  /// Normal controller disposal remains safe after this method completes.
  Future<void> closeForRouteTransition() async {
    final activeTransition = _routeTransitionFuture;
    if (activeTransition != null) return activeTransition;
    if (_disposed || _playerDisposed) return;
    late final Future<void> transition;
    transition = _mutationQueue.run<void>(() async {
      if (_playerDisposed) return;
      _routeTransitionClosed = true;
      _playbackDesired = false;
      await _stopLiveLatencySampling(
        reason: MpvLiveLatencyProtectionReason.lifecycleInterrupted,
      );
      _activeLiveProtocol = null;
      _liveLinkHealth.stop();
      if (_isBuffering) _finishBuffering(DateTime.now());
      try {
        await _stopDanmaku();
        await player.stop();
        await player.dispose();
        _playerDisposed = true;
      } catch (_) {
        _routeTransitionClosed = false;
        rethrow;
      }
    });
    _routeTransitionFuture = transition;
    _operationChain = transition.catchError((Object _) {});
    await transition;
  }

  @override
  void onClose() {
    _disposed = true;
    _playbackDesired = false;
    _activeLiveProtocol = null;
    _liveLatencyControlToken += 1;
    _liveLatencySamplingLoop.stop();
    final liveLatencyProtection = _liveLatencyChaser.protect(
      reason: MpvLiveLatencyProtectionReason.lifecycleInterrupted,
      generation: _liveLatencyChaser.generation,
    );
    _liveLinkHealth.stop();
    if (_isBuffering) _finishBuffering(DateTime.now());
    unawaited(_bufferingSubscription?.cancel());
    _bufferingSubscription = null;
    unawaited(_logSubscription?.cancel());
    _logSubscription = null;
    _danmakuActive = false;
    // 必须断开弹幕长连接，否则移除格子后连接和心跳会泄漏。
    liveDanmaku.onMessage = null;
    liveDanmaku.onClose = null;
    liveDanmaku.onReady = null;
    _danmakuReconnectTimer?.cancel();
    _tileControls.dispose();
    unawaited(liveDanmaku.stop());
    danmakuController = null;
    // 等当前串行的 open/load 收尾后再释放 Player，避免异步回调操作已释放实例。
    unawaited(_operationChain.whenComplete(() async {
      await liveLatencyProtection;
      await _liveLatencyChaser.stop();
      if (!_playerDisposed) {
        await player.stop();
        await player.dispose();
        _playerDisposed = true;
      }
      if (_ownsMutationQueue) {
        await _mutationQueue.close();
      }
    }));
    super.onClose();
  }
}
