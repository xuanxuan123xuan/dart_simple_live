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
//  - visualReady    : native video-frame-presented event for this stream
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

  bool _visualReady = false;
  bool _fileLoaded = false;
  Completer<void>? _fileLoadedWaiter;

  // Surface geometry currently applied to the native window. Dart is the
  // SINGLE writer: the buffer follows the STREAM's display aspect (never the
  // widget layout), so the vo hot-reconfig only ever runs right after a
  // room/quality switch while the loading spinner is already up. Fullscreen
  // and rotation change the box, not the video, and reconfigure nothing.
  // The widget scales the buffer uniformly with FittedBox(contain), so the
  // texture can never be stretched and the video always keeps its aspect.
  Size _appliedSurfaceSize = const Size(1920, 1080);
  Size? _reportedDisplaySize;
  Size? _pendingGeometry;
  Timer? _geometryDebounce;
  bool _geometryReconfiguring = false;
  Timer? _geometryResumeTimer;
  DateTime? _lastGeometryReconfigCompletedAt;

  /// Current native buffer size (video display aspect). The widget wraps
  /// the texture in a SizedBox of exactly this size under FittedBox(contain).
  Size get surfaceSize => _appliedSurfaceSize;

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

  /// True after native mpv reports that a video frame was presented for the
  /// current stream. This is deliberately driven by the native
  /// `video-frame-presented` event rather than `time-pos`: the playback clock
  /// can advance while the shared texture is still black.
  bool get visualReady => _visualReady;

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
    // The native buffer is SHARED across controllers (mpv + texture are a
    // plugin-wide singleton; create() only bumps the generation). A brand-new
    // controller therefore must NOT assume the buffer is 1920x1080: if the
    // previous room was portrait, the buffer is still 1080x1920 and blindly
    // trusting the field default would make the next landscape stream look
    // "squashed" (rendered into a portrait buffer the Dart side thinks is
    // landscape, so _scheduleGeometryReconfig skips the reconfig). Re-sync
    // _appliedSurfaceSize from the native buffer's real geometry instead.
    await _syncAppliedSurfaceSize();
    return;
  }

  /// Re-reads the native buffer geometry into [_appliedSurfaceSize]. The
  /// shared surface outlives any single controller, so this is the single
  /// source of truth whenever a new controller is created.
  Future<void> _syncAppliedSurfaceSize() async {
    try {
      final result = await _method.invokeMethod('getSurfaceSize');
      if (result is! Map) {
        return;
      }
      final w = (result['width'] as num?)?.toInt() ?? 0;
      final h = (result['height'] as num?)?.toInt() ?? 0;
      if (w >= 16 && h >= 16) {
        _appliedSurfaceSize = Size(w.toDouble(), h.toDouble());
        Log.i('[mpv-ctrl] synced surface size ${w}x$h');
      }
    } on PlatformException {
      // Player not ready yet; keep the default until the first geometry
      // event resyncs it.
    }
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
    final wasVisualReady = _visualReady;
    _visualReady = false;
    _fileLoaded = false;
    _eofReached = false;
    _timePosSeconds = null;
    _demuxerCacheTime = null;
    // A fresh stream must not inherit the previous room's idle/buffering
    // flags: a leftover _coreIdle=true (from a torn-down vo) would otherwise
    // surface the new room as "buffering" before its first frame presents.
    _coreIdle = true;
    _pausedForCache = false;
    _reportedDisplaySize = null;
    _pendingGeometry = null;
    _geometryDebounce?.cancel();
    _geometryReconfiguring = false;
    _geometryResumeTimer?.cancel();
    value = value.copyWith(size: Size.zero, position: Duration.zero);
    if (wasVisualReady && !_mpvDisposed) {
      notifyListeners();
    }
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
    // Keep startup A/V alignment consistent across both profiles. The
    // low-latency profile used to select `desync`, which allowed audio to
    // start several seconds before the first video frame.
    await _setProperty('video-sync', 'audio');
    await _setProperty('initial-audio-sync', 'yes');
    if (lowLatency) {
      await _setProperty('cache', 'no');
      await _setProperty('cache-pause', 'no');
      await _setProperty('demuxer-lavf-o', 'fflags=+nobuffer');
    } else {
      // The native player is reused across room switches. Restore the
      // low-latency options explicitly so a stable stream never inherits the
      // previous room's no-cache settings.
      await _setProperty('cache', 'auto');
      await _setProperty('cache-pause', 'yes');
      await _setProperty('demuxer-lavf-o', '');
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

  /// Resizes the shared native buffer when the stream's display aspect maps
  /// to a different canonical buffer (portrait vs landscape). Targets are
  /// quantized to 1080x1920 / 1920x1080 so streams whose reported dw/dh
  /// oscillates (adaptive streams, rotate metadata) cannot chain reconfigs
  /// back and forth, and a short cooldown keeps any remaining churn bounded.
  /// This only ever happens right after a room/quality switch — while the
  /// loading spinner is already up — so the vo hot-reconfig (one black frame)
  /// is never visible. Layout changes like fullscreen toggles never reach
  /// this path.
  void _scheduleGeometryReconfig(Size displaySize) {
    if (_mpvDisposed) {
      return;
    }
    final target = displaySize.width / displaySize.height < 1
        ? const Size(1080, 1920)
        : const Size(1920, 1080);
    if (target == _appliedSurfaceSize) {
      return;
    }
    // An orientation change (portrait <-> landscape) must always reconfigure:
    // the 5s cooldown below is meant to suppress same-orientation size
    // churn (adaptive streams, rotate metadata), but skipping a real
    // orientation flip leaves a landscape stream rendered into a portrait
    // buffer (or vice versa), which the uniform FittedBox(contain) then
    // letterboxes into a visually squashed picture.
    final orientationChanged =
        (target.width < target.height) !=
        (_appliedSurfaceSize.width < _appliedSurfaceSize.height);
    if (!orientationChanged) {
      final lastCompleted = _lastGeometryReconfigCompletedAt;
      if (lastCompleted != null &&
          DateTime.now().difference(lastCompleted) <
              const Duration(seconds: 5)) {
        return;
      }
    }
    if (_pendingGeometry == target) {
      return;
    }
    _pendingGeometry = target;
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
    // Fire-time verification: the stream may have settled back to the
    // applied buffer's aspect while the debounce ran, in which case the
    // reconfig must not happen at all.
    final dw = int.tryParse(await _getProperty('video-out-params/dw') ?? '') ??
        0;
    final dh = int.tryParse(await _getProperty('video-out-params/dh') ?? '') ??
        0;
    if (dw > 0 && dh > 0) {
      final currentTarget =
          dw / dh < 1 ? const Size(1080, 1920) : const Size(1920, 1080);
      if (currentTarget == _appliedSurfaceSize) {
        Log.i('[mpv-ctrl] geometry reconfig skipped (settled)');
        return;
      }
    }
    _geometryReconfiguring = true;
    Log.i(
        '[mpv-ctrl] geometry reconfig -> ${target.width.toInt()}x${target.height.toInt()}');
    // The ohosvk vo cannot follow an in-place buffer resize (it keeps
    // rendering the old canvas into the top-left corner), so the vo must be
    // rebuilt — which blanks the surface for a moment. Report "playing, not
    // buffering" until playback actually resumes so the room UI never spins
    // for this; the flash stays hidden behind the room-loading spinner
    // because reconfigs only ever happen right after a switch.
    notifyListeners();
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
      if (!_mpvDisposed) {
        _appliedSurfaceSize = target;
        _lastGeometryReconfigCompletedAt = DateTime.now();
        Log.i(
            '[mpv-ctrl] geometry reconfig done -> ${target.width.toInt()}x${target.height.toInt()}');
      }
    } on PlatformException {
      // Player gone mid-sequence.
    } finally {
      _geometryResumeTimer?.cancel();
      _geometryResumeTimer = Timer(const Duration(seconds: 5), () {
        if (_geometryReconfiguring && !_mpvDisposed) {
          _geometryReconfiguring = false;
          notifyListeners();
        }
      });
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
    } else if (kind == 'event' && name == 'video-frame-presented') {
      _markVisualReady();
    } else if (kind == 'event' && name == 'file-loaded') {
      _fileLoaded = true;
      final waiter = _fileLoadedWaiter;
      if (waiter != null) {
        _fileLoadedWaiter = null;
        waiter.complete();
      }
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
        if (_geometryReconfiguring && !_coreIdle) {
          // Playback resumed after a buffer reconfig: end the spinner
          // suppression exactly when frames flow again.
          _geometryReconfiguring = false;
        }
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
      case 'video-out-params':
        // dw/dh includes rotation and pixel aspect ratio; width/height is
        // only the decoded storage size. Prefer dw/dh for Flutter state.
        unawaited(_refreshDisplaySize());
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

  Future<void> _refreshDisplaySize() async {
    final dw = int.tryParse(await _getProperty('video-out-params/dw') ?? '') ??
        0;
    final dh = int.tryParse(await _getProperty('video-out-params/dh') ?? '') ??
        0;
    if (dw <= 0 || dh <= 0 || _mpvDisposed) {
      return;
    }
    final displaySize = Size(dw.toDouble(), dh.toDouble());
    Log.i('[mpv-ctrl] display $dw'
        'x$dh buffer=${_appliedSurfaceSize.width.toInt()}x${_appliedSurfaceSize.height.toInt()}');
    _reportedDisplaySize = displaySize;
    if (value.size != displaySize) {
      value = value.copyWith(size: displaySize);
    }
    _scheduleGeometryReconfig(displaySize);
  }

  Future<void> _refreshSize() async {
    final w = int.tryParse(await _getProperty('width') ?? '') ?? 0;
    final h = int.tryParse(await _getProperty('height') ?? '') ?? 0;
    if (w > 0 && h > 0 && !_mpvDisposed) {
      // video-out-params/dw/dh includes rotation and pixel aspect ratio;
      // width/height is only the decoded storage size. Prefer the former for
      // Flutter layout once mpv has reported it.
      final next = value.copyWith(
        size: _reportedDisplaySize ?? Size(w.toDouble(), h.toDouble()),
      );
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
    // A vo hot-reconfig (vo=null -> setGeometry -> vo=gpu-next) is a
    // same-room transient: audio keeps playing and the video clock keeps
    // advancing while the gpu-next vo re-initializes. During that window mpv
    // reports core-idle=true, but that is NOT a buffering stall — surfacing
    // it as isBuffering would flash the room-level spinner (black screen with
    // a spinner) over a picture that is about to come back on its own. Hold
    // the previous playing state across the reconfig and never report
    // buffering because of it.
    final playing = initialized &&
        !_paused &&
        !_pausedForCache &&
        (!_coreIdle || _geometryReconfiguring);
    final buffering = initialized &&
        !_eofReached &&
        !_geometryReconfiguring &&
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
  }

  void _markVisualReady() {
    if (_mpvDisposed || _visualReady) {
      return;
    }
    _visualReady = true;
    // visualReady is controller state but is intentionally not duplicated in
    // VideoPlayerValue. Notify the widget listener exactly once so it can
    // replace the loading surface on the next frame without rebuilding for
    // every time-pos heartbeat.
    notifyListeners();
    onFirstFrameDecoded?.call();
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
    _geometryResumeTimer?.cancel();
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
