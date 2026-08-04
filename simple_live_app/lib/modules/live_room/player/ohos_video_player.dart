import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

enum OhosPlaybackHealthIssue { bufferingTimeout, playbackStall }

const ohosBufferingTimeout = Duration(seconds: 8);
const ohosPlaybackStallTimeout = Duration(seconds: 12);

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
    this.onCompleted,
    this.fit = BoxFit.contain,
    this.forcedAspectRatio,
    this.initialVolume = 1.0,
  });

  final String url;
  final int revision;
  final Map<String, String>? headers;
  final ValueChanged<String>? onError;
  final ValueChanged<VideoPlayerController>? onControllerReady;
  final ValueChanged<VideoPlayerController>? onControllerDisposed;
  final ValueChanged<VideoPlayerValue>? onValueChanged;
  final VoidCallback? onCompleted;
  final BoxFit fit;
  final double? forcedAspectRatio;
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
  DateTime? _bufferingSince;
  DateTime _lastProgressAt = DateTime.now();
  Duration _lastPosition = Duration.zero;
  bool _hasObservedProgress = false;
  bool _completionReported = false;
  VideoPlayerValue? _previousValue;

  /// 首次有效视频宽高比缓存。
  ///
  /// 方向切换（竖↔横）期间 OHOS 会把 surface size 误报为横屏窗口尺寸
  /// （如 800x360），若用实时的 value.size 渲染，FittedBox 会把画面压成
  /// 细长横条或拉伸填满，直到方向切换完成后 ~1s 才恢复。缓存首次有效的
  /// 固有比例，方向切换时画面等比缩放（letterbox），不再变形。
  double? _cachedAspectRatio;

  @override
  void initState() {
    super.initState();
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
    _cachedAspectRatio = null;
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
        _startWatchdog();
      }
      _handleValueChanged(controller);
    } catch (e) {
      if (!_isCurrent(generation, controller)) {
        return;
      }
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
    if (_cachedAspectRatio == null &&
        value.size.width > 0 &&
        value.size.height > 0) {
      _cachedAspectRatio = value.size.width / value.size.height;
    }
    widget.onValueChanged?.call(value);
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
    _bufferingSince = null;
    _lastProgressAt = DateTime.now();
    _lastPosition = Duration.zero;
    _hasObservedProgress = false;
    _completionReported = false;
    _previousValue = null;
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

    // 方向切换期间 OHOS 的 value.size 不可靠（见 _cachedAspectRatio 注释），
    // 因此绕开 VideoPlayer widget 内部基于实时 size 的 AspectRatio，改用
    // Texture 直出 + 缓存的固有比例 + FittedBox 等比缩放。
    final displayRatio =
        widget.forcedAspectRatio ?? _cachedAspectRatio ?? 16 / 9;
    final rotation = controller.value.rotationCorrection;
    // textureId 虽标了 @visibleForTesting（官方包限制），运行时可用；
    // 用它直出 Texture 以绕开 VideoPlayer widget 内部基于实时 size 的比例。
    // ignore: invalid_use_of_visible_for_testing_member
    Widget texture = Texture(textureId: controller.textureId);
    if (rotation == 90 || rotation == 270) {
      texture = RotatedBox(
        quarterTurns: (rotation ~/ 90) % 4,
        child: texture,
      );
    }
    final video = ClipRect(
      child: FittedBox(
        fit: widget.fit,
        child: AspectRatio(
          aspectRatio: displayRatio,
          child: texture,
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
