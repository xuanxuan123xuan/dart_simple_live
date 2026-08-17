import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_ohos/video_player_ohos.dart' as ohos_plugin;

enum OhosPlaybackHealthIssue { bufferingTimeout, playbackStall }

typedef OhosVideoValueChanged = void Function(
  int playerGeneration,
  VideoPlayerValue value,
);

const ohosBufferingTimeout = Duration(seconds: 8);
const ohosPlaybackStallTimeout = Duration(seconds: 12);
const ohosFirstFrameTimeout = Duration(seconds: 12);

@visibleForTesting
OhosPlaybackHealthIssue? detectOhosPlaybackHealthIssue({
  required VideoPlayerValue value,
  required DateTime now,
  required DateTime? bufferingSince,
  required DateTime lastProgressAt,
  required bool hasObservedProgress,
}) {
  if (value.isBuffering &&
      bufferingSince != null &&
      (now.difference(bufferingSince) >= ohosBufferingTimeout ||
          (hasObservedProgress &&
              now.difference(lastProgressAt) >= ohosPlaybackStallTimeout))) {
    return OhosPlaybackHealthIssue.bufferingTimeout;
  }
  if (!value.isBuffering &&
      value.isPlaying &&
      hasObservedProgress &&
      now.difference(lastProgressAt) >= ohosPlaybackStallTimeout) {
    return OhosPlaybackHealthIssue.playbackStall;
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

/// HarmonyOS native AVPlayer texture surface (HLS and HTTP-FLV).
class OhosVideoPlayer extends StatefulWidget {
  const OhosVideoPlayer({
    super.key,
    required this.url,
    required this.revision,
    this.headers,
    this.onError,
    this.onControllerReady,
    this.onControllerDisposed,
    this.onValueChanged,
    this.onGenerationValueChanged,
    this.onFirstFrame,
    this.onCompleted,
    this.fit = BoxFit.contain,
    this.forcedAspectRatio,
    required this.initialVolume,
  });

  final String url;
  final int revision;
  final Map<String, String>? headers;
  final ValueChanged<String>? onError;
  final ValueChanged<VideoPlayerController>? onControllerReady;
  final ValueChanged<VideoPlayerController>? onControllerDisposed;
  final ValueChanged<VideoPlayerValue>? onValueChanged;
  final OhosVideoValueChanged? onGenerationValueChanged;
  final ValueChanged<int>? onFirstFrame;
  final VoidCallback? onCompleted;
  final BoxFit fit;
  final double? forcedAspectRatio;

  /// Current session volume on the native 0..1 scale.
  ///
  /// The owning controller keeps the persisted user intent on a 0..100 scale;
  /// every native controller reconstruction must receive its current value.
  final double initialVolume;

  @override
  State<OhosVideoPlayer> createState() => _OhosVideoPlayerState();
}

class _OhosVideoPlayerState extends State<OhosVideoPlayer> {
  static const _initializationTimeout = Duration(seconds: 15);
  static const _watchdogInterval = Duration(seconds: 1);

  VideoPlayerController? _controller;
  VoidCallback? _controllerListener;
  int _initializationGeneration = 0;
  bool _ready = false;
  bool _errorReported = false;
  String? _error;
  Timer? _watchdogTimer;
  Timer? _firstFrameTimer;
  StreamSubscription<ohos_plugin.OhosFirstFrameEvent>? _firstFrameSubscription;
  DateTime? _bufferingSince;
  DateTime _lastProgressAt = DateTime.now();
  Duration _lastPosition = Duration.zero;
  bool _hasObservedProgress = false;
  bool _completionReported = false;
  bool _firstFrameRendered = false;
  VideoPlayerValue? _previousValue;

  @override
  void initState() {
    super.initState();
    _firstFrameSubscription =
        ohos_plugin.OhosVideoPlayer.firstFrameEvents.listen((event) {
      _handleNativeFirstFrame(event);
    });
    _initialize();
  }

  @override
  void didUpdateWidget(covariant OhosVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.url != widget.url ||
        !mapEquals(oldWidget.headers, widget.headers)) {
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final generation = ++_initializationGeneration;
    final previousController = _controller;
    final previousListener = _controllerListener;
    if (previousController != null) {
      if (previousListener != null) {
        previousController.removeListener(previousListener);
      }
      widget.onControllerDisposed?.call(previousController);
      unawaited(previousController.dispose());
    }
    _controller = null;
    _controllerListener = null;
    _ready = false;
    _errorReported = false;
    _error = null;
    _resetPlaybackHealth();
    if (mounted) {
      setState(() {});
    }

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: widget.headers ?? const <String, String>{},
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: false,
        allowBackgroundPlayback: true,
      ),
    );
    _controller = controller;
    _controllerListener = () => _handleValueChanged(controller);
    controller.addListener(_controllerListener!);
    widget.onControllerReady?.call(controller);
    try {
      await controller.initialize().timeout(_initializationTimeout);
      if (!_isCurrent(generation, controller)) {
        return;
      }
      await controller.setVolume(widget.initialVolume.clamp(0.0, 1.0));
      await controller.play();
      if (_isCurrent(generation, controller)) {
        setState(() => _ready = true);
        _startFirstFrameTimeout(generation, controller);
        _startWatchdog();
      }
      _handleValueChanged(controller);
    } catch (e) {
      if (!_isCurrent(generation, controller)) {
        return;
      }
      // 初始化超时/失败后 AVPlayer 可能仍挂在 native 侧：必须像开头释放旧
      // controller 一样把它 detach 并 dispose，避免悬挂的原生播放器泄漏。
      final failedListener = _controllerListener;
      if (failedListener != null) {
        controller.removeListener(failedListener);
      }
      _controllerListener = null;
      if (identical(_controller, controller)) {
        _controller = null;
      }
      widget.onControllerDisposed?.call(controller);
      unawaited(controller.dispose());
      _reportError(
        e is TimeoutException ? '播放器初始化超时，请检查网络或切换线路' : e.toString(),
      );
    }
  }

  bool _isCurrent(int generation, VideoPlayerController controller) {
    return mounted &&
        generation == _initializationGeneration &&
        identical(_controller, controller);
  }

  void _handleValueChanged(VideoPlayerController controller) {
    if (!identical(_controller, controller)) {
      return;
    }
    final value = controller.value;
    widget.onValueChanged?.call(value);
    widget.onGenerationValueChanged?.call(widget.revision, value);
    if (looksLikeOhosPlaybackCompleted(
          current: value,
          previous: _previousValue,
        ) &&
        !_completionReported) {
      _completionReported = true;
      widget.onCompleted?.call();
    }
    _previousValue = value;
    if (value.hasError) {
      _reportError(value.errorDescription ?? '播放器发生未知错误');
    }
  }

  void _resetPlaybackHealth() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _firstFrameTimer?.cancel();
    _firstFrameTimer = null;
    _bufferingSince = null;
    _lastProgressAt = DateTime.now();
    _lastPosition = Duration.zero;
    _hasObservedProgress = false;
    _completionReported = false;
    _firstFrameRendered = false;
    _previousValue = null;
  }

  void _handleNativeFirstFrame(ohos_plugin.OhosFirstFrameEvent event) {
    final controller = _controller;
    if (!mounted || controller == null || _firstFrameRendered) {
      return;
    }
    // This app pins a video_player fork whose texture id is the only stable
    // key shared with the native per-texture EventChannel.
    // ignore: invalid_use_of_visible_for_testing_member
    final currentTextureId = controller.textureId;
    if (event.textureId != currentTextureId) {
      return;
    }
    _firstFrameRendered = true;
    _firstFrameTimer?.cancel();
    _firstFrameTimer = null;
    widget.onFirstFrame?.call(widget.revision);
  }

  void _startFirstFrameTimeout(
    int generation,
    VideoPlayerController controller,
  ) {
    _firstFrameTimer?.cancel();
    if (_firstFrameRendered) {
      return;
    }
    _firstFrameTimer = Timer(ohosFirstFrameTimeout, () {
      if (_isCurrent(generation, controller) && !_firstFrameRendered) {
        _reportError(
          '首帧渲染超过 ${ohosFirstFrameTimeout.inSeconds} 秒，正在重试',
        );
      }
    });
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(
      _watchdogInterval,
      (_) => _checkPlaybackHealth(),
    );
  }

  void _checkPlaybackHealth() {
    final controller = _controller;
    if (!mounted ||
        !_ready ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.hasError ||
        _completionReported ||
        _errorReported) {
      return;
    }

    final value = controller.value;
    final now = DateTime.now();
    if (value.isBuffering) {
      _bufferingSince ??= now;
      if (detectOhosPlaybackHealthIssue(
            value: value,
            now: now,
            bufferingSince: _bufferingSince,
            lastProgressAt: _lastProgressAt,
            hasObservedProgress: _hasObservedProgress,
          ) ==
          OhosPlaybackHealthIssue.bufferingTimeout) {
        _reportError('播放器持续缓冲超过 ${ohosBufferingTimeout.inSeconds} 秒，正在重试');
      }
      return;
    }
    _bufferingSince = null;

    // Paused time must not count toward a later playback stall.
    if (!value.isPlaying) {
      _lastPosition = value.position;
      _lastProgressAt = now;
      return;
    }

    if (didOhosPlaybackTimelineProgress(
      current: value.position,
      previous: _lastPosition,
    )) {
      _hasObservedProgress = true;
      _lastPosition = value.position;
      _lastProgressAt = now;
      return;
    }

    // Some live sources expose no timeline. Only use the progress watchdog
    // after this source has advanced once; buffering still has its own timer.
    if (detectOhosPlaybackHealthIssue(
          value: value,
          now: now,
          bufferingSince: _bufferingSince,
          lastProgressAt: _lastProgressAt,
          hasObservedProgress: _hasObservedProgress,
        ) ==
        OhosPlaybackHealthIssue.playbackStall) {
      _reportError('播放进度停止超过 ${ohosPlaybackStallTimeout.inSeconds} 秒，正在重试');
    }
  }

  void _reportError(String message) {
    if (_errorReported) {
      return;
    }
    _errorReported = true;
    if (mounted) {
      setState(() => _error = message);
    }
    widget.onError?.call(message);
  }

  @override
  void dispose() {
    _initializationGeneration++;
    _watchdogTimer?.cancel();
    _firstFrameTimer?.cancel();
    _firstFrameSubscription?.cancel();
    final controller = _controller;
    final listener = _controllerListener;
    if (controller != null) {
      if (listener != null) {
        controller.removeListener(listener);
      }
      widget.onControllerDisposed?.call(controller);
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('播放失败\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final intrinsicRatio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;
    final displayRatio = widget.forcedAspectRatio ?? intrinsicRatio;
    final size = controller.value.size;
    final width = size.width > 0 ? size.width : displayRatio * 100;
    final height = size.height > 0 ? size.height : 100.0;
    final video = ClipRect(
      child: FittedBox(
        fit: widget.fit,
        child: SizedBox(
          width: width,
          height: height,
          child: VideoPlayer(controller),
        ),
      ),
    );
    if (widget.forcedAspectRatio != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: widget.forcedAspectRatio!,
          child: video,
        ),
      );
    }
    return SizedBox.expand(child: video);
  }
}
