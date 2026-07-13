import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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
  final BoxFit fit;
  final double? forcedAspectRatio;
  final double initialVolume;

  @override
  State<OhosVideoPlayer> createState() => _OhosVideoPlayerState();
}

class _OhosVideoPlayerState extends State<OhosVideoPlayer> {
  static const _initializationTimeout = Duration(seconds: 15);

  VideoPlayerController? _controller;
  VoidCallback? _controllerListener;
  int _initializationGeneration = 0;
  bool _ready = false;
  bool _errorReported = false;
  String? _error;

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
    if (mounted) {
      setState(() {});
    }

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: widget.headers ?? const <String, String>{},
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
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
    widget.onValueChanged?.call(value);
    if (value.hasError) {
      _reportError(value.errorDescription ?? '播放器发生未知错误');
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
