// libmpv-backed HarmonyOS live room player. Drop-in replacement for
// [OhosVideoPlayer]: identical constructor surface and identical external
// behavior contract (error/telemetry/first-frame/completed callbacks), but
// rendering goes mpv (gpu-next + Vulkan) -> Flutter texture and decoding is
// OHCodec hardware via libmpv.
//
// The playback health watchdogs are reused verbatim from ohos_video_player.dart
// (detectOhosPlaybackHealthIssue et al., marked visibleForTesting there) so the
// room-level failover policies behave identically across the two backends.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/modules/live_room/player/mpv_ohos_controller.dart';
import 'package:simple_live_app/modules/live_room/player/ohos_playback_profile_policy.dart';
// ignore: implementation_imports
import 'package:simple_live_app/modules/live_room/player/ohos_video_player.dart';
import 'package:simple_live_app/services/ohos_playback_capabilities_service.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_ohos/video_player_ohos.dart'
    show OhosPlaybackProfile;

class MpvOhosPlayer extends StatefulWidget {
  const MpvOhosPlayer({
    super.key,
    required this.url,
    required this.revision,
    this.headers,
    this.onError,
    this.onControllerReady,
    this.onControllerDisposed,
    this.onValueChanged,
    this.onGenerationValueChanged,
    this.onTelemetry,
    this.onFirstFrame,
    this.onPlaybackProfileChanged,
    this.onCompleted,
    this.fit = BoxFit.contain,
    this.forcedAspectRatio,
    required this.initialVolume,
    required this.sessionGeneration,
    required this.requestedPlaybackProfile,
  });

  final String url;
  final int revision;
  final Map<String, String>? headers;
  final ValueChanged<String>? onError;
  final ValueChanged<VideoPlayerController>? onControllerReady;
  final ValueChanged<VideoPlayerController>? onControllerDisposed;
  final ValueChanged<VideoPlayerValue>? onValueChanged;
  final OhosVideoValueChanged? onGenerationValueChanged;
  final OhosVideoTelemetryChanged? onTelemetry;
  final ValueChanged<int>? onFirstFrame;
  final OhosPlaybackProfileChanged? onPlaybackProfileChanged;
  final VoidCallback? onCompleted;
  final BoxFit fit;
  final double? forcedAspectRatio;
  final double initialVolume;
  final int sessionGeneration;
  final String requestedPlaybackProfile;

  @override
  State<MpvOhosPlayer> createState() => _MpvOhosPlayerState();
}

class _MpvOhosPlayerState extends State<MpvOhosPlayer> {
  static const _initializationTimeout = Duration(seconds: 15);
  static const _watchdogInterval = Duration(seconds: 1);

  /// Overall bound for opening the stream. Nothing else guards this window:
  /// short buffering/first-frame watchdogs would false-positive while mpv is
  /// still busy with the previous room's teardown during fast switching.
  static const _connectTimeout = Duration(seconds: 20);

  /// First frame must present within this window once the stream opened.
  static const _firstFrameAfterLoadedTimeout = Duration(seconds: 8);

  MpvOhosVideoController? _controller;
  VoidCallback? _controllerListener;
  int _initializationGeneration = 0;
  bool _ready = false;
  bool _errorReported = false;
  String? _error;
  Timer? _watchdogTimer;
  Timer? _firstFrameTimer;
  DateTime? _bufferingSince;
  DateTime _lastProgressAt = DateTime.now();
  Duration _lastPosition = Duration.zero;
  bool _hasObservedProgress = false;
  DateTime? _lastHeartbeatAt;
  bool _hasObservedHeartbeat = false;
  Duration? _lastCacheDuration;
  DateTime? _monitoringSince;
  bool _unobservableReported = false;
  bool _completionReported = false;
  bool _firstFrameRendered = false;
  Size? _lastRenderedSize;
  bool _lastRenderedVisualReady = false;
  String? _lastRenderedError;
  int? _lowLatencyDisabledSessionGeneration;
  bool _profileFallbackInProgress = false;
  OhosPlaybackProfileDecision _activePlaybackProfileDecision =
      const OhosPlaybackProfileDecision(
    profile: OhosPlaybackProfile.stable,
    reason: OhosPlaybackProfileDecisionReason.stableRequested,
  );

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant MpvOhosPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionGeneration != widget.sessionGeneration) {
      _lowLatencyDisabledSessionGeneration = null;
      _profileFallbackInProgress = false;
    }
    if (oldWidget.revision != widget.revision ||
        oldWidget.url != widget.url ||
        !mapEquals(oldWidget.headers, widget.headers) ||
        oldWidget.sessionGeneration != widget.sessionGeneration ||
        oldWidget.requestedPlaybackProfile != widget.requestedPlaybackProfile) {
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final generation = ++_initializationGeneration;
    final profileDecision = await _resolvePlaybackProfileDecision();
    if (!mounted || generation != _initializationGeneration) {
      return;
    }
    _activePlaybackProfileDecision = profileDecision;
    _profileFallbackInProgress = false;
    widget.onPlaybackProfileChanged?.call(
      widget.sessionGeneration,
      widget.revision,
      profileDecision,
    );
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
    _lastRenderedSize = null;
    _lastRenderedVisualReady = false;
    _lastRenderedError = null;
    _ready = false;
    _errorReported = false;
    _error = null;
    _resetPlaybackHealth();
    if (mounted) {
      setState(() {});
    }

    final controller = MpvOhosVideoController(
      url: widget.url,
      httpHeaders: widget.headers ?? const <String, String>{},
    );
    _controller = controller;
    _controllerListener = () => _handleValueChanged(controller);
    controller.addListener(_controllerListener!);
    _wireMpvCallbacks(controller);
    widget.onControllerReady?.call(controller);
    try {
      await controller
          .mpvCreate()
          .timeout(_initializationTimeout, onTimeout: () => false);
      if (!_isCurrent(generation, controller)) {
        return;
      }
      await controller.initialize();
      await controller.applyPlaybackProfile(
          lowLatency: profileDecision.isExperimental);
      await controller.applyUserOverrides();
      await controller.mpvLoad(
        url: widget.url,
        headers: widget.headers ?? const <String, String>{},
      );
      await controller.setVolume(widget.initialVolume.clamp(0.0, 1.0));
      await controller.play();
      if (!_isCurrent(generation, controller)) {
        return;
      }
      setState(() => _ready = true);
      // Stream-open window: only the long connect timeout guards it; the
      // spinner keeps running until the stream opens and the first frame
      // presents. Buffering watchdog starts with the first presented frame.
      await controller.waitForFileLoaded(_connectTimeout);
      if (!_isCurrent(generation, controller)) {
        return;
      }
      _startFirstFrameTimeout(generation, controller);
      _handleValueChanged(controller);
    } catch (e) {
      if (!_isCurrent(generation, controller)) {
        return;
      }
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
        e is TimeoutException
            ? 'player initialization timed out, check the network or switch lines'
            : e.toString(),
      );
    }
  }

  void _wireMpvCallbacks(MpvOhosVideoController controller) {
    controller.onFirstFrameDecoded = () {
      if (!mounted || _firstFrameRendered) {
        return;
      }
      _firstFrameRendered = true;
      _firstFrameTimer?.cancel();
      _firstFrameTimer = null;
      widget.onFirstFrame?.call(widget.revision);
      _startWatchdog();
    };
    controller.onHeartbeat = (DateTime at, Duration position) {
      if (!mounted) {
        return;
      }
      _lastHeartbeatAt = at;
      _hasObservedHeartbeat = true;
      widget.onTelemetry?.call(
        widget.revision,
        OhosPlaybackTelemetry(
          heartbeatAt: at,
          position: position,
          cacheDuration: _lastCacheDuration,
        ),
      );
    };
    controller.onCacheDuration = (Duration? cacheTime) {
      if (!mounted) {
        return;
      }
      _lastCacheDuration = cacheTime;
      widget.onTelemetry?.call(
        widget.revision,
        OhosPlaybackTelemetry(
          heartbeatAt: _lastHeartbeatAt,
          position: _controller?.value.position,
          cacheDuration: cacheTime,
        ),
      );
    };
    controller.onFatal = (String message) {
      _reportError(message);
    };
  }

  Future<OhosPlaybackProfileDecision> _resolvePlaybackProfileDecision() async {
    final disabledForSession =
        _lowLatencyDisabledSessionGeneration == widget.sessionGeneration;
    var supported = false;
    if (!disabledForSession &&
        widget.requestedPlaybackProfile ==
            ohosLowLatencyExperimentalProfileValue) {
      supported =
          (await OhosPlaybackCapabilitiesService.instance.getCapabilities())
              .lowLatencyExperimentalSupported;
    }
    return resolveOhosPlaybackProfile(
      requestedProfile: widget.requestedPlaybackProfile,
      source: widget.url,
      lowLatencyExperimentalSupported: supported,
      disabledForSession: disabledForSession,
    );
  }

  bool _isCurrent(int generation, MpvOhosVideoController controller) {
    return mounted &&
        generation == _initializationGeneration &&
        identical(_controller, controller);
  }

  void _handleValueChanged(MpvOhosVideoController controller) {
    if (!identical(_controller, controller)) {
      return;
    }
    final value = controller.value;
    final shouldRebuild = _lastRenderedSize != value.size ||
        _lastRenderedVisualReady != controller.visualReady ||
        _lastRenderedError != value.errorDescription;
    _lastRenderedSize = value.size;
    _lastRenderedVisualReady = controller.visualReady;
    _lastRenderedError = value.errorDescription;
    if (shouldRebuild && mounted) {
      setState(() {});
    }
    widget.onValueChanged?.call(value);
    widget.onGenerationValueChanged?.call(widget.revision, value);
    if (_controller?.eofReached == true && !_completionReported) {
      _completionReported = true;
      widget.onCompleted?.call();
    }
    if (value.hasError) {
      _reportError(value.errorDescription ?? 'unknown player error');
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
    _lastHeartbeatAt = null;
    _hasObservedHeartbeat = false;
    _lastCacheDuration = null;
    _monitoringSince = null;
    _unobservableReported = false;
    _completionReported = false;
    _firstFrameRendered = false;
  }

  void _startFirstFrameTimeout(
    int generation,
    MpvOhosVideoController controller,
  ) {
    _firstFrameTimer?.cancel();
    if (_firstFrameRendered) {
      return;
    }
    _firstFrameTimer = Timer(_firstFrameAfterLoadedTimeout, () {
      if (_isCurrent(generation, controller) && !_firstFrameRendered) {
        _reportError(
          'first frame took over ${_firstFrameAfterLoadedTimeout.inSeconds} seconds, retrying',
        );
      }
    });
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _monitoringSince = DateTime.now();
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
    } else {
      _bufferingSince = null;

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
    }

    switch (detectOhosPlaybackHealthIssue(
      value: value,
      now: now,
      bufferingSince: _bufferingSince,
      lastProgressAt: _lastProgressAt,
      hasObservedProgress: _hasObservedProgress,
      lastHeartbeatAt: _lastHeartbeatAt,
      hasObservedHeartbeat: _hasObservedHeartbeat,
      monitoringSince: _monitoringSince,
    )) {
      case OhosPlaybackHealthIssue.bufferingTimeout:
        _reportError(
          'buffering for over ${ohosBufferingTimeout.inSeconds} seconds, retrying',
        );
      case OhosPlaybackHealthIssue.playbackStall:
        _reportError(
          'playback stalled for over ${ohosPlaybackStallTimeout.inSeconds} seconds, retrying',
        );
      case OhosPlaybackHealthIssue.playbackUnobservable:
        if (!_unobservableReported) {
          _unobservableReported = true;
          Log.d('[mpv-player] progress and heartbeat unavailable, watchdog '
              'reduced to buffering timeout only');
        }
      case null:
        break;
    }
  }

  void _reportError(String message) {
    if (_errorReported) {
      return;
    }
    if (_fallbackExperimentalProfile(message)) {
      return;
    }
    _errorReported = true;
    if (mounted) {
      setState(() => _error = message);
    }
    widget.onError?.call(message);
  }

  bool _fallbackExperimentalProfile(String message) {
    if (!_activePlaybackProfileDecision.isExperimental ||
        _profileFallbackInProgress ||
        _lowLatencyDisabledSessionGeneration == widget.sessionGeneration) {
      return false;
    }
    _profileFallbackInProgress = true;
    _lowLatencyDisabledSessionGeneration = widget.sessionGeneration;
    Log.w(
      '[mpv-player] experimental low-latency profile fell back to stable '
      'session=${widget.sessionGeneration} player=${widget.revision} '
      'reason=${message.replaceAll(RegExp(r'https?://\S+'), '<redacted>')}',
    );
    widget.onPlaybackProfileChanged?.call(
      widget.sessionGeneration,
      widget.revision,
      const OhosPlaybackProfileDecision(
        profile: OhosPlaybackProfile.stable,
        reason: OhosPlaybackProfileDecisionReason.sessionFallback,
      ),
    );
    unawaited(_initialize());
    return true;
  }

  @override
  void dispose() {
    _initializationGeneration++;
    _watchdogTimer?.cancel();
    _firstFrameTimer?.cancel();
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
          child: Text('Failed to play\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    if (!_ready) {
      return const SizedBox.expand(
        child: ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const SizedBox.expand(
        child: ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final size = controller.value.size;
    // Mirrors media_kit_video's visibility gating (video_texture.dart):
    // keep the Texture hidden until the video dimensions are known. The mpv
    // surface is shared across rooms, so rendering it before the first frame
    // would briefly show the previous room's last picture.
    final sizeKnown =
        size.width > 0 && size.height > 0 && controller.visualReady;
    final video = sizeKnown
        ? ClipRect(
            child: FittedBox(
              fit: widget.fit,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Texture(textureId: controller.textureId),
              ),
            ),
          )
        : const SizedBox.expand(
            child: ColoredBox(
              color: Colors.black,
              child: Center(child: CircularProgressIndicator()),
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
