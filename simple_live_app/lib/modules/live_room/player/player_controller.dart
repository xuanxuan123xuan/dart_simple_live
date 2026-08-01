import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:auto_orientation_v2/auto_orientation_v2.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:simple_live_app/services/background_playback_service.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';
import 'package:simple_live_app/services/network_diagnose_service.dart';
import 'package:simple_live_app/services/ohos_pip_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:video_player/video_player.dart';

const _windowsChromeChannel = MethodChannel('simple_live/windows_chrome');
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
          : MPVLogLevel.error,
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
  }

  void detachOhosVideoController(VideoPlayerController controller) {
    if (identical(_ohosVideoController, controller)) {
      BackgroundPlaybackService.instance.detachOhosController(controller);
      _ohosVideoController = null;
      ohosPlaying.value = false;
      ohosBuffering.value = false;
    }
  }

  void updateOhosVideoState(VideoPlayerValue value) {
    final wasPlaying = ohosPlaying.value;
    ohosPlaying.value = value.isPlaying;
    ohosBuffering.value = value.isBuffering || !value.isInitialized;
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
      await controller.pause();
    } else {
      await controller.play();
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
  double _volumeBeforeMute = 100.0;

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
    if (!Platform.isWindows) {
      return;
    }
    hideMouseCursorTimer?.cancel();
    hideMouseCursorState.value = true;
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

  /// 开始隐藏鼠标光标计时
  void resetHideMouseCursorTimer() {
    if (!Platform.isWindows) {
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
  int _mobileSystemUiRequest = 0;
  bool _systemUiAppActive = true;

  //final VolumeController volumeController = VolumeController();

  /// 初始化一些系统状态
  void initSystem() async {
    if (Platform.isAndroid || Platform.isIOS) {
      VolumeController.instance.showSystemUI = false;
    }

    if (Utils.isOhos) {
      _ensureOhosPipStatusListener();
    }

    // 屏幕常亮
    //WakelockPlus.enable();

    // 开始隐藏计时
    resetHideControlsTimer();

    // 进入全屏模式
    if (AppSettingsController.instance.autoFullScreen.value) {
      enterFullScreen();
    }
  }

  /// 释放一些系统状态
  Future resetSystem() async {
    _systemUiAppActive = false;
    _mobileSystemUiRequest += 1;
    _pipSubscription?.cancel();
    _ohosPipSubscription?.cancel();
    //pip.dispose();
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );

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
      ohosFullscreenTransition.value = true;
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
    } else if (Platform.isAndroid || Platform.isIOS) {
      fullScreenState.value = true;
      if (!isVertical.value) {
        //横屏
        await setLandscapeOrientation();
      }
      await restoreFullScreenSystemUi();
    } else {
      fullScreenState.value = true;
      _windowMaximizedBeforeFullScreen = await windowManager.isMaximized();
      await _applyWindowsFullScreenChrome();
      await windowManager.setFullScreen(true);
      await _waitForWindowsFullScreenState(true);
      await _applyWindowsFullScreenChrome();
      unawaited(
        Future.delayed(const Duration(milliseconds: 900), () async {
          if (!fullScreenState.value || smallWindowState.value) {
            return;
          }
          await _applyWindowsFullScreenChrome();
        }),
      );
      await Future.delayed(const Duration(milliseconds: 32));
    }
    //danmakuController?.clear();
  }

  /// 隐藏移动端系统栏。
  ///
  /// iOS 不支持 Android 的 immersiveSticky 语义，需要明确传入空 overlays。
  /// 该方法也会在 App 回到前台时重新调用，防止 iOS 恢复状态栏。
  Future<void> restoreFullScreenSystemUi() async {
    if ((!Platform.isAndroid && !Platform.isIOS) ||
        !_systemUiAppActive ||
        !fullScreenState.value ||
        smallWindowState.value) {
      return;
    }
    final request = ++_mobileSystemUiRequest;
    await WidgetsBinding.instance.endOfFrame;
    if (!_isCurrentMobileSystemUiRequest(request)) {
      return;
    }
    await _hideMobileSystemUi();
    if (Platform.isIOS) {
      // iOS may restore the status bar once more while a route/orientation
      // transition is finishing. Reapply only if this is still the latest
      // fullscreen request, so an exit request can never be overwritten.
      await Future.delayed(const Duration(milliseconds: 120));
      if (_isCurrentMobileSystemUiRequest(request)) {
        await _hideMobileSystemUi();
      }
    }
  }

  bool _isCurrentMobileSystemUiRequest(int request) {
    return request == _mobileSystemUiRequest &&
        _systemUiAppActive &&
        fullScreenState.value &&
        !smallWindowState.value &&
        !isPlayerClosing;
  }

  /// Cancels stale fullscreen UI work while backgrounded. The caller should
  /// request a restore after marking the app active again.
  void updateSystemUiAppLifecycle(bool active) {
    _systemUiAppActive = active;
    _mobileSystemUiRequest += 1;
  }

  Future<void> _hideMobileSystemUi() {
    if (Platform.isIOS) {
      return SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: const [],
      );
    }
    return SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
        return;
      }
      // Keep the fullscreen surface alive until HarmonyOS reports a portrait
      // viewport. This avoids rebuilding the room in a landscape viewport and
      // also keeps the native AVPlayer texture attached throughout the move.
      ohosFullscreenTransition.value = true;
      lockControlsState.value = false;
      showLockEdgeState.value = false;
      // System-bar restoration can take hundreds of milliseconds on some
      // HarmonyOS builds. Do not hold the portrait page behind that operation.
      unawaited(
        _runOhosSystemUiOperation(
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.edgeToEdge,
            overlays: SystemUiOverlay.values,
          ),
          "恢复系统栏",
        ),
      );
      unawaited(
        _runOhosSystemUiOperation(
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]),
          "恢复屏幕方向",
        ),
      );
      await _waitForOhosViewport(portrait: true);
      fullScreenState.value = false;
      ohosFullscreenTransition.value = false;
      onPlayerWindowModeExited();
      showControls();
      return;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      _mobileSystemUiRequest += 1;
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
      await resetPreferredOrientation();
      await Future.delayed(const Duration(milliseconds: 32));
    } else {
      await windowManager.setFullScreen(false);
      await _waitForWindowsFullScreenState(false);
      await _restoreWindowsWindowChrome();
      await _refreshWindowsWindowBounds();
      if (_windowMaximizedBeforeFullScreen) {
        await windowManager.maximize();
        await _waitForWindowMaximizedState(true);
      }
      _windowMaximizedBeforeFullScreen = false;
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
    final deadline = DateTime.now().add(const Duration(milliseconds: 450));
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
  bool _windowMaximizedBeforeFullScreen = false;
  bool _windowMaximizedBeforeSmallWindow = false;

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

  Future<void> _applyWindowsFullScreenChrome() async {
    if (!Platform.isWindows) {
      return;
    }

    try {
      await _windowsChromeChannel.invokeMethod<void>('apply');
    } catch (e) {
      Log.logPrint(e);
    }
  }

  ///小窗模式()
  Future<void> _restoreWindowsWindowChrome() async {
    if (!Platform.isWindows) {
      return;
    }

    try {
      await _windowsChromeChannel.invokeMethod<void>('restore');
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
        final restoreVolume = _volumeBeforeMute <= 0
            ? AppSettingsController.instance.playerVolume.value
            : _volumeBeforeMute;
        await setSessionPlayerVolume(restoreVolume);
      } else {
        _volumeBeforeMute = ohosVolume.value * 100;
        await setSessionPlayerVolume(0);
      }
      return;
    }
    if (mutedState.value) {
      final restoreVolume =
          _volumeBeforeMute <= 0 ? 100.0 : _volumeBeforeMute.clamp(0.0, 100.0);
      await setSessionPlayerVolume(restoreVolume);
      return;
    }
    _volumeBeforeMute = player.state.volume <= 0
        ? AppSettingsController.instance.playerVolume.value
        : player.state.volume;
    mutedState.value = true;
    await player.setVolume(0);
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
      } catch (e, stackTrace) {
        Log.e("鸿蒙原生窗口截图失败，回退 Flutter 截图：$e", stackTrace);
      }

      if (renderObject is! RenderRepaintBoundary) {
        return null;
      }
      final flutterImage = await renderObject.toImage(pixelRatio: pixelRatio);
      try {
        final byteData =
            await flutterImage.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      } finally {
        flutterImage.dispose();
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
    if (lockControlsState.value && fullScreenState.value) {
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
      ohosVolume.value =
          AppSettingsController.instance.playerVolume.value / 100;
      if (AppSettingsController.instance.autoFullScreen.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!isPlayerClosing && !fullScreenState.value) {
            unawaited(enterFullScreen());
          }
        });
      }
      mutedState.value = ohosVolume.value <= 0;
      showControls();
      super.onInit();
      return;
    }
    initSystem();
    initStream();
    //设置音量
    player.setVolume(AppSettingsController.instance.playerVolume.value);
    super.onInit();
  }

  StreamSubscription<String>? _errorSubscription;
  StreamSubscription? _completedSubscription;
  StreamSubscription? _widthSubscription;
  StreamSubscription? _heightSubscription;
  StreamSubscription? _logSubscription;
  StreamSubscription? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  bool _wakelockAppActive = true;
  bool _ownsWakelock = true;
  bool? _pendingWakelockState;
  Future<void>? _wakelockDrain;

  // Fix Issue #57: 流错误重试计数器
  int _streamErrorRetryCount = 0;
  DateTime? _lastStreamErrorTime;
  Timer? _surfaceHealthCheckTimer;

  /// 自动网络诊断提示（缓冲 2 次以上触发，显示在画面左上角）。
  final networkHint = "".obs;
  int _bufferingCount = 0;
  DateTime? _lastBufferingTime;
  bool _autoDiagnoseRunning = false;
  Timer? _networkHintTimer;

  void initStream() {
    _errorSubscription = player.stream.error.listen((event) {
      Log.d("播放器错误：$event");
      // 跳过无音频输出的错误
      // Could not open/initialize audio device -> no sound.
      if (event.contains('no sound.')) {
        return;
      }

      // Fix Issue #57: 检测流错误并自动重试
      if (_isStreamError(event)) {
        _handleStreamError(event);
        return;
      }

      //SmartDialog.showToast(event);
      mediaError(event);
    });

    _playingSubscription = player.stream.playing.listen((event) {
      _requestWakelockEnabled(
        _wakelockAppActive && !isPlayerClosing && event,
      );
      unawaited(_syncBackgroundPlaybackService(event));
      if (event) {
        Log.d("Playing");
        // 播放成功，重置流错误计数
        _streamErrorRetryCount = 0;
      }
    });

    _completedSubscription = player.stream.completed.listen((event) {
      if (event) {
        mediaEnd();
      }
    });
    _logSubscription = player.stream.log.listen((event) {
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

    // 缓冲转圈 2 次以上自动触发网络诊断提示。
    _bufferingSubscription = player.stream.buffering.listen((buffering) {
      if (!buffering || isPlayerClosing) {
        return;
      }
      final now = DateTime.now();
      if (_lastBufferingTime != null &&
          now.difference(_lastBufferingTime!) <
              const Duration(milliseconds: 300)) {
        return;
      }
      _lastBufferingTime = now;
      _bufferingCount += 1;
      if (_bufferingCount >= 2 && networkHint.value.isEmpty) {
        unawaited(_runAutoNetworkDiagnose());
      }
    });
  }

  /// 自动网络诊断：缓冲 2 次以上时测延迟/丢包，提示显示在画面左上角，
  /// 8 秒后自动消失。
  Future<void> _runAutoNetworkDiagnose() async {
    if (_autoDiagnoseRunning) {
      return;
    }
    _autoDiagnoseRunning = true;
    networkHint.value = "网络检测中…";
    final results = await NetworkDiagnoseService.diagnose(
      NetworkDiagnoseService.defaultTargets,
      samples: 3,
    );
    _autoDiagnoseRunning = false;
    if (isPlayerClosing) {
      return;
    }
    networkHint.value = NetworkDiagnoseService.summarize(results);
    _networkHintTimer?.cancel();
    _networkHintTimer = Timer(const Duration(seconds: 8), () {
      if (networkHint.value.isNotEmpty) {
        networkHint.value = "";
      }
    });
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

  /// Keeps the screen awake only while this foreground room is actually
  /// playing. Playback can be paused internally even though the UI has no
  /// pause button (for example while opening multi-room or losing focus).
  void updateWakelockAppLifecycle(bool active) {
    _wakelockAppActive = active;
    _syncWakelockForCurrentState();
  }

  void _syncWakelockForCurrentState() {
    if (Utils.isOhos || !_ownsWakelock) {
      return;
    }
    _requestWakelockEnabled(
      _wakelockAppActive && !isPlayerClosing && player.state.playing,
    );
  }

  void _requestWakelockEnabled(bool enabled) {
    if (Utils.isOhos || !_ownsWakelock) {
      return;
    }
    _pendingWakelockState = enabled;
    _wakelockDrain ??= _drainWakelockState();
  }

  Future<void> _drainWakelockState() async {
    try {
      while (_ownsWakelock && _pendingWakelockState != null) {
        final enabled = _pendingWakelockState!;
        _pendingWakelockState = null;
        if (enabled) {
          await WakelockPlus.enable();
        } else {
          await WakelockPlus.disable();
        }
      }
    } catch (e) {
      Log.d("同步屏幕常亮状态失败: $e");
    } finally {
      _wakelockDrain = null;
      if (_ownsWakelock && _pendingWakelockState != null) {
        _wakelockDrain = _drainWakelockState();
      }
    }
  }

  /// Transfers the global wakelock to another player surface. Waiting for the
  /// in-flight operation prevents this controller from disabling multi-room's
  /// wakelock after the new route has already opened.
  Future<void> releaseWakelockOwnership() async {
    if (Utils.isOhos || !_ownsWakelock) {
      return;
    }
    _ownsWakelock = false;
    _pendingWakelockState = null;
    try {
      await _wakelockDrain;
      if (!_ownsWakelock) {
        await WakelockPlus.disable();
      }
    } catch (e) {
      Log.d("释放屏幕常亮所有权失败: $e");
    }
  }

  void reclaimWakelockOwnership() {
    if (Utils.isOhos) {
      return;
    }
    _ownsWakelock = true;
    _syncWakelockForCurrentState();
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
    if (_lastStreamErrorTime != null &&
        now.difference(_lastStreamErrorTime!) < const Duration(seconds: 2)) {
      return;
    }
    _lastStreamErrorTime = now;

    if (_streamErrorRetryCount >= 3) {
      Log.e("流错误重试次数已达上限(3次)，停止重试: $error", StackTrace.current);
      mediaError(error);
      return;
    }

    _streamErrorRetryCount++;
    Log.w(
      "检测到流错误，自动重试解码器 ($_streamErrorRetryCount/3): $error",
      false,
    );

    // 等待1秒后重新打开当前流
    await Future.delayed(const Duration(seconds: 1));

    try {
      final currentMedia = player.state.playlist.medias.isNotEmpty
          ? player.state.playlist.medias[player.state.playlist.index]
          : null;

      if (currentMedia != null && !_playerClosing) {
        Log.i("正在重启解码器...");
        await player.pause();
        await Future.delayed(const Duration(milliseconds: 200));
        await player.open(currentMedia);
      }
    } catch (e, stackTrace) {
      Log.e("重启解码器失败: $e", stackTrace);
      mediaError(error);
    }
  }

  // Fix Issue #57: 处理异常的视频尺寸（Surface失效）
  Future<void> _handleInvalidVideoSize() async {
    Log.w("检测到视频尺寸异常，尝试恢复Surface");

    // 短暂暂停再恢复，触发Surface重建
    try {
      if (player.state.playing && !_playerClosing) {
        await player.pause();
        await Future.delayed(const Duration(milliseconds: 300));
        await player.play();
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
    _requestWakelockEnabled(false);
    unawaited(stopBackgroundPlaybackService());
  }

  void mediaError(String error) {
    _requestWakelockEnabled(false);
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
    await releaseWakelockOwnership();
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
      _ohosVideoController = null;
      disposeDanmakuController();
      return;
    }
    await stopBackgroundPlaybackService();
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
