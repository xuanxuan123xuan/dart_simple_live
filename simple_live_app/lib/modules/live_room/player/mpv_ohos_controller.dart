// libmpv-backed controller for HarmonyOS live playback.
//
// Extends [VideoPlayerController] so every downstream consumer
// (PlayerController, BackgroundPlaybackService, diagnostics) keeps working
// with zero changes: `value` is a real [VideoPlayerValue], and
// play/pause/setVolume/dispose are overridden to drive libmpv through the
// temporary OhosMpvPlugin method channel instead of the AVPlayer platform.
//
// State model (kept deliberately conservative):
//  - isInitialized   : after mpv_initialize + texture registration
//  - isPlaying       : !pause && !core-idle
//  - isBuffering     : paused-for-cache, or core-idle without EOF and
//                      without an explicit user pause
//  - position        : mpv time-pos (throttled to ~4 updates/s natively)
//  - size/aspectRatio: mpv width x height
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';
import 'package:video_player/video_player.dart';

class MpvOhosVideoController extends VideoPlayerController {
  MpvOhosVideoController({
    required String url,
    Map<String, String> httpHeaders = const <String, String>{},
  }) : super.networkUrl(Uri.parse(url), httpHeaders: httpHeaders);

  static const MethodChannel _method = MethodChannel('simple_live/ohos_mpv');
  static const EventChannel _events =
      EventChannel('simple_live/ohos_mpv_events');

  int _mpvTextureId = -1;
  int _generation = -1;
  int _eventGenFilter = -1;
  bool _mpvDisposed = false;
  StreamSubscription? _eventSub;

  // Raw mpv state used to synthesize VideoPlayerValue.
  bool _paused = false;
  bool _coreIdle = true;
  bool _pausedForCache = false;
  bool _eofReached = false;
  double? _timePosSeconds;
  Duration? _demuxerCacheTime;

  bool _firstFrameReported = false;
  bool _firstTimePosSeen = false;
  bool _fileLoaded = false;
  Completer<void>? _fileLoadedWaiter;

  // Surface geometry currently applied to the native window. The Dart side
  // owns the vo hot-reconfig sequence so the mpv event pump is never blocked
  // by a synchronous vo teardown (that caused black-frame loops and UI jank).
  Size _appliedSurfaceSize = const Size(1920, 1080);
  Size? _pendingGeometry;
  Timer? _geometryDebounce;

  /// Called on the first decoded frame; wired by the owning widget to the
  /// first-frame watchdog plumbing.
  VoidCallback? onFirstFrameDecoded;

  /// Called (throttled natively) whenever mpv reports a fresh playback clock.
  void Function(DateTime at, Duration position)? onHeartbeat;

  /// Called whenever the demuxer cache depth estimate changes.
  void Function(Duration? cacheTime)? onCacheDuration;

  /// Called when mpv reports an unrecoverable playback failure.
  void Function(String message)? onFatal;

  @override
  int get textureId => _mpvTextureId;

  /// True once the new stream's playback clock has ticked at least once:
  /// the first frame has actually been presented to the shared surface, so
  /// it is safe to make the [Texture] visible (older frames may still sit in
  /// the surface buffer before that point).
  bool get firstFramePresented => _firstTimePosSeen;

  /// True once mpv finished opening the current stream (file-loaded).
  bool get fileLoaded => _fileLoaded;

  /// Whether mpv has reported end-of-stream for the current file.
  bool get eofReached => _eofReached;

  bool _containsYes(String v) => v == 'yes' || v == 'true';

  Future<void> mpvCreate() async {
    final result = await _method.invokeMethod('create');
    final id = result['textureId'];
    if (id is int) {
      _mpvTextureId = id;
    }
    final gen = result['generation'];
    if (gen is int && gen > 0) {
      _generation = gen;
    }
    Log.d('[mpv-ctrl] create textureId=$_mpvTextureId gen=$_generation');
    value = value.copyWith(isInitialized: _mpvTextureId >= 0);
    startEventListening();
    return;
  }

  Future<void> mpvLoad({
    required String url,
    Map<String, String> headers = const <String, String>{},
  }) async {
    if (_mpvDisposed) {
      // An orphaned load after the controller was disposed (fast room exit
      // racing the initialization chain) would keep playing audio with no
      // widget left to stop it.
      return;
    }
    _eventGenFilter = _generation;
    // Reset per-stream visible state: the shared surface still holds the
    // previous stream's last frame, and width/height events of the new
    // stream fire before its first frame is presented. Closing the
    // visibility gate here keeps the widget on its loading state until the
    // new stream really presents.
    _firstTimePosSeen = false;
    _fileLoaded = false;
    _eofReached = false;
    _timePosSeconds = null;
    _demuxerCacheTime = null;
    value = value.copyWith(size: Size.zero, position: Duration.zero);
    if (_mpvDisposed) {
      return;
    }
    await _method.invokeMethod('loadFile', {
      'url': url,
      'headers': headers,
      'generation': _generation,
    });
  }

  /// Waits until mpv finished opening the current stream ([fileLoaded]),
  /// bounded by [timeout]. Throws [TimeoutException] when the stream does
  /// not open in time.

  Future<void> waitForFileLoaded(Duration timeout) async {
    if (_fileLoaded || _mpvDisposed) {
      return;
    }
    final completer = Completer<void>();
    _fileLoadedWaiter = completer;
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      if (identical(_fileLoadedWaiter, completer)) {
        _fileLoadedWaiter = null;
      }
      rethrow;
    }
  }

  /// Applies the live latency option set. [lowLatency] mirrors the
  /// `lowLatencyExperimental` playback profile from the AVPlayer era; the
  /// values follow integration README section 6.2.
  Future<void> applyPlaybackProfile({required bool lowLatency}) async {
    if (lowLatency) {
      await _setProperty('cache', 'no');
      await _setProperty('cache-pause', 'no');
      await _setProperty('demuxer-lavf-o', 'fflags=+nobuffer');
      await _setProperty('video-sync', 'desync');
    }
  }

  /// Applies the user's own mpv tweaks on top of the built-in playback
  /// profile: free-form "advanced mpv options" (one key=value per line) and
  /// the hardware decoder preference mapped onto the decoder names this OHOS
  /// libmpv build provides. Runs after [applyPlaybackProfile] so user values
  /// override built-ins, and before the first loadfile so they affect the
  /// incoming stream. Unknown keys fail silently inside [_setProperty].
  Future<void> applyUserOverrides() async {
    final settings = AppSettingsController.instance;
    final advanced =
        MpvOptionsService.parseOptions(settings.mpvAdvancedOptions.value);
    for (final entry in advanced.entries) {
      await _setProperty(entry.key, entry.value);
    }
    final hwdec = _mapOhosHwdec(settings.videoHardwareDecoder.value);
    if (hwdec != null) {
      await _setProperty('hwdec', hwdec);
    }
  }

  /// Maps the cross-platform hardware decoder preference onto OHOS decoder
  /// names. Desktop-only decoders (d3d11va, videotoolbox, ...) keep the
  /// native default (OHCodec) by returning null.
  String? _mapOhosHwdec(String value) {
    switch (value.trim()) {
      case 'no':
        return 'no';
      case 'auto':
      case 'auto-safe':
      case 'yes':
        return 'ohcodec';
      case 'auto-copy':
        return 'ohcodec-copy';
      default:
        return null;
    }
  }
  Future<void> _setProperty(String name, String value) async {
    if (_mpvDisposed) return;
    try {
      await _method.invokeMethod('setProperty', {'name': name, 'value': value});
    } on PlatformException {
      // A dead player must not take the room UI down with it.
    }
  }

  Future<String?> _getProperty(String name) async {
    if (_mpvDisposed) return null;
    try {
      return await _method.invokeMethod('getProperty', {'name': name});
    } on PlatformException {
      return null;
    }
  }

  void startEventListening() {
    _eventSub?.cancel();
    _eventSub = _events.receiveBroadcastStream().listen(_handleEvent,
        onError: (dynamic e) {
      // The channel dies with the player; dispose paths cancel this
      // subscription explicitly.
    });
  }

  Future<void> _confirmFatal() async {
    final idle = await _getProperty('idle-active');
    if (_mpvDisposed) {
      return;
    }
    // idle-active == no means another file is already active: the error
    // belonged to a stream that was replaced in the meantime.
    if (idle == 'no') {
      return;
    }
    onFatal?.call('live stream playback failed');
  }

  Future<void> _applyGeometryChange(String sizeText) async {
    final parts = sizeText.split('x');
    final w = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final h = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    if (w < 16 || h < 16 || _mpvDisposed) {
      return;
    }
    if (_appliedSurfaceSize.width == w && _appliedSurfaceSize.height == h) {
      return;
    }
    // Once the first frame is on screen, a vo reconfig would flash black in
    // the middle of playback; later resolution changes are rendered
    // letterboxed by mpv into the existing surface instead.
    if (_firstFrameReported) {
      return;
    }
    // Skip sub-2% aspect changes (1088 vs 1080 heights, minor adaptive
    // quality fluctuations): every reconfig costs one black window.
    final oldAspect = _appliedSurfaceSize.width / _appliedSurfaceSize.height;
    final newAspect = w / h;
    if ((newAspect - oldAspect).abs() / oldAspect < 0.02) {
      return;
    }
    _pendingGeometry = Size(w.toDouble(), h.toDouble());
    _geometryDebounce?.cancel();
    _geometryDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_runGeometryReconfig());
    });
  }

  Future<void> _runGeometryReconfig() async {
    final target = _pendingGeometry;
    if (target == null || _mpvDisposed) {
      return;
    }
    _pendingGeometry = null;
    _appliedSurfaceSize = target;
    try {
      await _setProperty('vo', 'null');
      if (_mpvDisposed) {
        return;
      }
      await _method.invokeMethod('setGeometry', {
        'width': target.width.toInt(),
        'height': target.height.toInt(),
      });
      await _setProperty('ohos-surface-size',
          '${target.width.toInt()}x${target.height.toInt()}');
      await _setProperty('vo', 'gpu-next');
    } on PlatformException {
      // Player gone mid-sequence.
    }
  }

  void _handleEvent(dynamic event) {
    if (event is! Map || _mpvDisposed) {
      return;
    }
    // Events carry the loadfile generation they belong to; stale events from
    // a previous room's stream must not reach this controller (they caused
    // phantom "playback failed" reports during fast room switches).
    final eventGen = event['gen'];
    if (eventGen is int && eventGen != _eventGenFilter) {
      return;
    }
    final kind = event['kind'] as String?;
    final name = event['name'] as String?;
    final valueText = event['value'] as String? ?? '';
    if (kind == 'property' && name != null) {
      _handleProperty(name, valueText);
    } else if (kind == 'event' && name == 'file-loaded') {
      _fileLoaded = true;
      final waiter = _fileLoadedWaiter;
      if (waiter != null) {
        _fileLoadedWaiter = null;
        waiter.complete();
      }
    } else if (kind == 'event' && name == 'geometry-changed') {
      unawaited(_applyGeometryChange(valueText));
    } else if (kind == 'event' && name == 'end-file') {
      if (valueText == 'error') {
        unawaited(_confirmFatal());
      }
    } else if (kind == 'event' && name == 'shutdown') {
      onFatal?.call('player shut down');
    }
  }

  void _handleProperty(String name, String valueText) {
    switch (name) {
      case 'pause':
        _paused = _containsYes(valueText);
        break;
      case 'core-idle':
        _coreIdle = _containsYes(valueText);
        break;
      case 'paused-for-cache':
        _pausedForCache = _containsYes(valueText);
        break;
      case 'eof-reached':
        _eofReached = _containsYes(valueText);
        break;
      case 'time-pos':
        final seconds = double.tryParse(valueText);
        if (seconds != null) {
          _timePosSeconds = seconds;
          _firstTimePosSeen = true;
          onHeartbeat?.call(DateTime.now(), _positionFromSeconds(seconds));
        }
        break;
      case 'demuxer-cache-time':
        final seconds = double.tryParse(valueText);
        if (seconds != null) {
          _demuxerCacheTime = _positionFromSeconds(seconds);
          onCacheDuration?.call(_demuxerCacheTime);
        }
        break;
      case 'width':
      case 'height':
        unawaited(_refreshSize());
        break;
      default:
        break;
    }
    _publish();
  }

  Future<void> _refreshSize() async {
    final w = int.tryParse(await _getProperty('width') ?? '') ?? 0;
    final h = int.tryParse(await _getProperty('height') ?? '') ?? 0;
    if (w > 0 && h > 0 && !_mpvDisposed) {
      final next = value.copyWith(size: Size(w.toDouble(), h.toDouble()));
      if (next != value) {
        value = next;
      }

    }
  }

  Duration _positionFromSeconds(double seconds) {
    final ms = (seconds * 1000).round();
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  /// Recomputes the synthesized [VideoPlayerValue] and notifies listeners.
  void _publish() {
    if (_mpvDisposed) {
      return;
    }
    final initialized = _mpvTextureId >= 0;
    final playing = initialized && !_paused && !_coreIdle && !_pausedForCache;
    final buffering = initialized &&
        !_eofReached &&
        (_pausedForCache || (_coreIdle && !_paused));
    final previous = value;
    final next = previous.copyWith(
      isInitialized: initialized,
      isPlaying: playing,
      isBuffering: buffering,
      position: _timePosSeconds != null
          ? _positionFromSeconds(_timePosSeconds!)
          : null,
    );
    if (next != previous) {
      value = next;
    }
    if (initialized && !_firstFrameReported && !_coreIdle) {
      _firstFrameReported = true;
      onFirstFrameDecoded?.call();
    }
  }

  @override
  Future<void> initialize() async {
    // The mpv path does not talk to the video_player platform; initialization
    // happens through mpvCreate/mpvLoad driven by the owning widget.
    value = value.copyWith(isInitialized: true);
  }

  @override
  Future<void> play() async {
    if (_mpvDisposed) {
      return;
    }
    _paused = false;
    _coreIdle = false;
    await _setProperty('pause', 'no');
    _publish();
  }

  @override
  Future<void> pause() async {
    _paused = true;
    await _setProperty('pause', 'yes');
    _publish();
  }

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    if (value.volume != clamped) {
      value = value.copyWith(volume: clamped);
    }
    await _setProperty('volume', (clamped * 100).toStringAsFixed(1));
  }

  /// Explicit stop for the room close path. Generation-guarded on the
  /// native side: a stale controller (room already switched) cannot kill the
  /// new stream, while the closing room always stops its own playback even
  /// when the widget dispose races the controller teardown.
  Future<void> stopPlayback() async {
    if (_mpvDisposed) return;
    try {
      await _method.invokeMethod('dispose', {'generation': _generation});
    } on PlatformException {
      // Player already gone.
    }
  }

  @override
  Future<void> seekTo(Duration position) async {
    // Live streams: seeking is a no-op; the latency chaser owns catch-up.
  }

  @override
  Future<void> dispose() async {
    Log.d('[mpv-ctrl] dispose gen=$_generation');
    _mpvDisposed = true;
    _geometryDebounce?.cancel();
    _fileLoadedWaiter = null;
    _eventSub?.cancel();
    _eventSub = null;
    try {
      await _method.invokeMethod('dispose', {'generation': _generation});
    } on PlatformException {
      // Player may already be gone.
    }
    await super.dispose();
  }
}
