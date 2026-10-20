import 'dart:async';
import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/controller/base_controller.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/modules/live_room/player/playback_stall_tracker.dart';
import 'package:simple_live_tv_app/services/mpv_options_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

mixin PlayerMixin {
  GlobalKey<VideoState> globalPlayerKey = GlobalKey<VideoState>();
  GlobalKey globalDanmuKey = GlobalKey();

  /// 播放器实例
  late final player = Player(
    configuration: const PlayerConfiguration(
      title: "Simple Live Player",
      // bufferSize:
      //     // media-kit #549
      //     AppSettingsController.instance.playerBufferSize.value * 1024 * 1024,
    ),
  );

  VideoController? _videoController;

  /// 渲染降级重建次数，页面据此重建 Video 组件
  final playerRenderGeneration = 0.obs;

  /// 视频控制器（惰性创建；渲染降级后可重建）
  VideoController get videoController => _videoController ??= VideoController(
        player,
        configuration: MpvOptionsService.videoControllerConfiguration(),
      );

  /// 渲染降级档位变更后重建视频控制器与 Video 组件。
  Future<void> rebuildVideoControllerForRenderStage() async {
    _videoController = VideoController(
      player,
      configuration: MpvOptionsService.videoControllerConfiguration(),
    );
    globalPlayerKey = GlobalKey<VideoState>();
    playerRenderGeneration.value++;
  }

  Future<void> initializePlayer() async {
    final startedAt = DateTime.now();
    // The Video widget creates the Android Surface asynchronously after the
    // first frame. Do not let mpv open the stream before that output is ready.
    await videoController.platform.future;
    Log.i(
      '视频输出初始化完成：耗时=${DateTime.now().difference(startedAt).inMilliseconds}ms',
    );
    await MpvOptionsService.applyToPlayer(player);
  }
}
mixin PlayerStateMixin on PlayerMixin {
  /// 是否显示弹幕
  RxBool showDanmakuState = false.obs;

  /// 是否显示控制器
  RxBool showControlsState = false.obs;

  /// 是否显示设置窗口
  RxBool showSettingState = false.obs;

  /// 是否显示弹幕设置窗口
  RxBool showDanmakuSettingState = false.obs;

  /// 是否处于锁定控制器状态
  RxBool lockControlsState = false.obs;

  /// 是否处于全屏状态
  RxBool fullScreenState = false.obs;

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

  /// 自动隐藏提示计时器
  Timer? hideSeekTipTimer;

  Widget? danmakuView;

  var showQualites = false.obs;
  var showLines = false.obs;

  /// 隐藏控制器
  void hideControls() {
    showControlsState.value = false;
    hideControlsTimer?.cancel();
  }

  void setLockState() {
    lockControlsState.value = !lockControlsState.value;
    if (lockControlsState.value) {
      showControlsState.value = false;
    } else {
      showControlsState.value = true;
    }
  }

  /// 显示控制器
  void showControls() {
    showControlsState.value = true;
    resetHideControlsTimer();
  }

  /// 开始隐藏控制器计时
  /// - 当点击控制器上时功能时需要重新计时
  void resetHideControlsTimer() {
    hideControlsTimer?.cancel();

    hideControlsTimer = Timer(
      const Duration(
        seconds: 5,
      ),
      hideControls,
    );
  }

  void updateScaleMode() {
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

  void initDanmakuController(DanmakuController e) {
    danmakuController = e;
    // danmakuController?.updateOption(
    //   DanmakuOption(
    //     fontSize: AppSettingsController.instance.danmuSize.value.w,
    //     area: AppSettingsController.instance.danmuArea.value,
    //     duration: AppSettingsController.instance.danmuSpeed.value,
    //     opacity: AppSettingsController.instance.danmuOpacity.value,
    //     strokeWidth: AppSettingsController.instance.danmuStrokeWidth.value.w,
    //   ),
    // );
  }

  void updateDanmuOption(DanmakuOption? option) {
    if (danmakuController == null || option == null) return;
    danmakuController!.updateOption(option);
  }

  void disposeDanmakuController() {
    danmakuController?.clear();
  }

  void addDanmaku(List<DanmakuContentItem> items) {
    if (!showDanmakuState.value) {
      return;
    }
    danmakuController?.addDanmakuBatch(items);
  }
}
mixin PlayerSystemMixin on PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin {
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  /// 初始化一些系统状态
  void initSystem() async {
    // 屏幕常亮
    WakelockPlus.enable();

    // 开始隐藏计时
    resetHideControlsTimer();
  }

  /// 释放一些系统状态
  Future resetSystem() async {
    await WakelockPlus.disable();
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
}

class PlayerController extends BaseController
    with PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin, PlayerSystemMixin {
  @override
  void onInit() {
    initSystem();
    initStream();
    super.onInit();
  }

  var width = 0.obs;
  var height = 0.obs;

  StreamSubscription<String>? _errorSubscription;
  StreamSubscription? _completedSubscription;
  StreamSubscription? _widthSubscription;
  StreamSubscription? _heightSubscription;
  StreamSubscription? _logSubscription;
  Timer? _playbackStallWatchdogTimer;
  Timer? _startupVideoWatchdog;
  int _startupWatchdogGeneration = -1;
  bool _renderFallbackReopening = false;
  static const Duration _startupVideoTimeout = Duration(seconds: 8);
  final PlaybackStallTracker _playbackStallTracker = PlaybackStallTracker();
  int playbackGeneration = 0;
  int _playbackDiagnosticsLoggedGeneration = -1;
  DateTime? _playbackGenerationStartedAt;
  int _startupDimensionsLoggedGeneration = -1;

  void initStream() {
    _errorSubscription = player.stream.error.listen((event) {
      Log.d("播放器错误：$event");
      if (event.contains('no sound.')) {
        return;
      }
      //SmartDialog.showToast(event);
      unawaited(mediaError(event));
    });

    _completedSubscription = player.stream.completed.listen((event) {
      if (event) {
        unawaited(mediaEnd());
      }
    });
    _logSubscription = player.stream.log.listen((event) {
      Log.d("播放器日志：$event");
    });
    _widthSubscription = player.stream.width.listen((event) {
      Log.w(
          'width:$event  W:${(player.state.width)}  H:${(player.state.height)}');
      width.value = event ?? 0;
      _maybeLogStartupDimensions();
      _maybeLogPlaybackDiagnostics();
      // isVertical.value =
      //     (player.state.height ?? 9) > (player.state.width ?? 16);
    });
    _heightSubscription = player.stream.height.listen((event) {
      Log.w(
          'height:$event  W:${(player.state.width)}  H:${(player.state.height)}');
      height.value = event ?? 0;
      _maybeLogStartupDimensions();
      _maybeLogPlaybackDiagnostics();
      // isVertical.value =
      //     (player.state.height ?? 9) > (player.state.width ?? 16);
    });
    _playbackStallWatchdogTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkPlaybackStall(),
    );
  }

  void _checkPlaybackStall() {
    if (playbackRecoveryInFlight) return;
    final state = player.state;
    final playlist = state.playlist;
    final media = playlist.medias.isNotEmpty &&
            playlist.index >= 0 &&
            playlist.index < playlist.medias.length
        ? playlist.medias[playlist.index]
        : null;
    final activeUri = media?.uri.toString() ?? "";
    final source =
        activeUri.isEmpty ? "" : playbackStallSourceIdentity(activeUri);
    final shouldRecover = observePlaybackProgress(
      now: DateTime.now(),
      generation: playbackGeneration,
      source: source,
      position: state.position,
      playing: state.playing,
      buffering: state.buffering,
      completed: state.completed,
    );
    if (!shouldRecover) return;
    Log.w(
      "检测到直播画面长时间无进度，自动恢复 "
      "(${_playbackStallTracker.recoveryAttempts}/3)",
    );
    unawaited(mediaError("直播流停滞，自动刷新"));
  }

  @protected
  bool observePlaybackProgress({
    required DateTime now,
    required int generation,
    required String source,
    required Duration position,
    required bool playing,
    required bool buffering,
    required bool completed,
  }) {
    final shouldRecover = _playbackStallTracker.observe(
      now: now,
      generation: generation,
      source: source,
      position: position,
      playing: playing,
      buffering: buffering,
      completed: completed,
      recoveryPending: playbackRecoveryPending,
      allowRecovery: !playbackRecoveryBlocked,
    );
    if (_playbackStallTracker.stableRecoveryCompleted) {
      playbackStable();
    }
    return shouldRecover;
  }

  void beginPlaybackGeneration() {
    playbackGeneration += 1;
    _playbackGenerationStartedAt = DateTime.now();
    _startupDimensionsLoggedGeneration = -1;
    Log.i('播放起播开始：generation=$playbackGeneration');
    _armStartupVideoWatchdog();
  }

  /// 清除当前播放的卡顿预算并使已排队的起播看门狗失效。
  /// 手动重试和换房间会在新的播放请求开始前调用。
  void resetPlaybackRecoveryTracking() {
    _playbackStallTracker.reset();
    _startupVideoWatchdog?.cancel();
    _startupVideoWatchdog = null;
    _startupWatchdogGeneration = -1;
  }

  void invalidatePlaybackGeneration() {
    playbackGeneration += 1;
    resetPlaybackRecoveryTracking();
  }

  /// 起播看门狗：仅监测"从未出画面"的场景；播中卡顿由
  /// [PlaybackStallTracker] 负责。
  void _armStartupVideoWatchdog() {
    _startupVideoWatchdog?.cancel();
    _startupWatchdogGeneration = playbackGeneration;
    if (!Platform.isAndroid) {
      return;
    }
    _startupVideoWatchdog = Timer(
      _startupVideoTimeout,
      () => unawaited(_handleStartupVideoWatchdog()),
    );
  }

  Future<void> _handleStartupVideoWatchdog() async {
    if (playbackRecoveryBlocked ||
        _startupWatchdogGeneration != playbackGeneration) {
      return;
    }
    if ((player.state.width ?? 0) > 0 && (player.state.height ?? 0) > 0) {
      return;
    }
    if (player.platform is NativePlayer) {
      final voConfigured = await _readVoConfigured();
      if (playbackRecoveryBlocked ||
          _startupWatchdogGeneration != playbackGeneration) {
        return;
      }
      // vo 已配置但从未上报尺寸：交给卡顿看门狗，不做渲染降级。
      if (voConfigured) return;
    }
    final settings = AppSettingsController.instance;
    if (playbackRecoveryBlocked) return;
    final currentStage = settings.renderFallbackStage.value;
    final nextStage = MpvOptionsService.nextRenderFallbackStage(currentStage);
    if (nextStage < 0) {
      Log.w("起播看门狗：所有渲染降级档位均未出画面，恢复默认渲染配置");
      settings.resetRenderFallbackStage();
      return;
    }
    Log.w(
      "起播 ${_startupVideoTimeout.inSeconds}s 未获得画面，"
      "渲染降级：${MpvOptionsService.renderStageLabels[currentStage] ?? currentStage}"
      " → ${MpvOptionsService.renderStageLabels[nextStage] ?? nextStage}",
    );
    settings.setRenderFallbackStage(nextStage);
    await _reopenWithRenderStage(nextStage);
  }

  Future<bool> _readVoConfigured() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return true;
    try {
      final value = await platform.getProperty('vo-configured');
      return value.trim().toLowerCase() == 'yes';
    } catch (e) {
      Log.d("读取 mpv 属性 vo-configured 失败: $e");
      return true;
    }
  }

  Future<void> _reopenWithRenderStage(int stage) async {
    if (_renderFallbackReopening || playbackRecoveryBlocked) return;
    _renderFallbackReopening = true;
    try {
      await rebuildVideoControllerForRenderStage();
      if (playbackRecoveryBlocked ||
          _startupWatchdogGeneration != playbackGeneration) {
        return;
      }
      Log.i("渲染降级：应用档位 $stage 后重新打开播放流");
      await reopenPlaybackForRenderFallback();
    } catch (e, stackTrace) {
      Log.e("渲染降级重开播放流失败: $e", stackTrace);
    } finally {
      _renderFallbackReopening = false;
    }
  }

  /// 渲染降级后需要重开播放流；由具体房间控制器覆盖实现。
  Future<void> reopenPlaybackForRenderFallback() async {}

  void _maybeLogPlaybackDiagnostics() {
    final generation = playbackGeneration;
    if (generation <= 0 ||
        _playbackDiagnosticsLoggedGeneration == generation ||
        (player.state.width ?? 0) <= 0 ||
        (player.state.height ?? 0) <= 0) {
      return;
    }
    _playbackDiagnosticsLoggedGeneration = generation;
    unawaited(_logPlaybackDiagnostics(generation));
  }

  void _maybeLogStartupDimensions() {
    final generation = playbackGeneration;
    if (generation <= 0 ||
        _startupDimensionsLoggedGeneration == generation ||
        width.value <= 0 ||
        height.value <= 0) {
      return;
    }
    _startupDimensionsLoggedGeneration = generation;
    final startedAt = _playbackGenerationStartedAt;
    Log.i(
      '首个有效视频尺寸：generation=$generation '
      'size=${width.value}x${height.value} '
      '耗时=${startedAt == null ? 'unknown' : '${DateTime.now().difference(startedAt).inMilliseconds}ms'}',
    );
  }

  Future<void> _logPlaybackDiagnostics(int generation) async {
    // Let mpv finish selecting tracks & the hardware decoder before sampling.
    await Future<void>.delayed(const Duration(seconds: 1));
    if (generation != playbackGeneration || player.platform is! NativePlayer) {
      return;
    }

    final nativePlayer = player.platform as NativePlayer;
    final properties = <String, String>{};
    for (final name in const [
      'hwdec-current',
      'video-codec',
      'video-bitrate',
      'estimated-vf-fps',
      'avsync',
    ]) {
      try {
        final value = (await nativePlayer.getProperty(name)).trim();
        if (value.isNotEmpty) {
          properties[name] = value;
        }
      } catch (e) {
        Log.d("读取 mpv 播放属性 $name 失败: $e");
      }
    }

    if (generation != playbackGeneration) return;
    final sourceResolution =
        '${player.state.width ?? 0}x${player.state.height ?? 0}';
    Log.i(
      '播放诊断：${MpvOptionsService.diagnosticsSummary()}, '
      'actualHwdec=${properties['hwdec-current'] ?? 'none'}, '
      'codec=${properties['video-codec'] ?? 'unknown'}, '
      'bitrate=${properties['video-bitrate'] ?? 'unknown'}, '
      'fps=${properties['estimated-vf-fps'] ?? 'unknown'}, '
      'resolution=$sourceResolution, '
      'avsync=${properties['avsync'] ?? 'unknown'}',
    );
  }

  String playbackStallSourceIdentity(String activeUri) => activeUri;

  bool get playbackRecoveryInFlight => false;

  bool get playbackRecoveryBlocked => false;

  bool get playbackRecoveryPending => false;

  void playbackStable() {}

  void disposeStream() {
    _errorSubscription?.cancel();
    _completedSubscription?.cancel();
    _widthSubscription?.cancel();
    _heightSubscription?.cancel();
    _logSubscription?.cancel();
    _playbackStallWatchdogTimer?.cancel();
    _playbackStallWatchdogTimer = null;
    _startupVideoWatchdog?.cancel();
    _startupVideoWatchdog = null;
    _playbackStallTracker.reset();
  }

  Future<void> mediaEnd() async {}

  Future<void> mediaError(String error) async {}

  @protected
  Future<void> disposePlayer() => player.dispose();

  Future<void>? _closePlayerFuture;

  Future<void> closePlayerSession() => _closePlayerFuture ??= _closePlayer();

  Future<void> _closePlayer() async {
    disposeStream();
    hideControlsTimer?.cancel();
    hideSeekTipTimer?.cancel();
    disposeDanmakuController();
    await resetSystem();
    await disposePlayer();
  }

  @override
  void onClose() {
    Log.w("播放器关闭");
    unawaited(closePlayerSession());
    super.onClose();
  }
}
