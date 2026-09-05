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
import 'package:simple_live_app/modules/live_room/player/mpv_ohos_decoder_policy.dart';
import 'package:video_player/video_player.dart';

const double _maxSafeDurationMilliseconds = 9223372036854775.0;

/// Parses an mpv seconds property without allowing invalid values to become
/// misleading zero or overflowing [Duration] values.
Duration? parseMpvOhosDurationSeconds(String value) {
  final seconds = double.tryParse(value.trim());
  if (seconds == null || !seconds.isFinite || seconds < 0) {
    return null;
  }
  final milliseconds = seconds * 1000;
  if (!milliseconds.isFinite || milliseconds > _maxSafeDurationMilliseconds) {
    return null;
  }
  return Duration(milliseconds: milliseconds.round());
}

/// The native buffer geometry handed to `SET_BUFFER_GEOMETRY` and written to
/// `ohos-surface-size`. This MUST be the video's DISPLAY size in physical
/// pixels — i.e. `video-out-params/dw x dh` verbatim (rotation/SAR already
/// applied by mpv) — NOT an independently scaled "long edge = 1920" value.
///
/// Rationale: mpv's gpu-next VO renders into a target of exactly `dwidth x
/// dheight` (see vo_gpu_next.c `resize()` → `gpu_ctx_resize(context, dwidth,
/// dheight)`), and the OHOS reference player syncs `ohos-surface-size` to the
/// media size in physical pixels (`vp2px(playerMediaW) x vp2px(playerMediaH)`),
/// NOT a re-scaled canvas. Scaling the buffer away from dw/dh makes the
/// surface geometry disagree with the VO's render target, so the picture is
/// stretched to fill the mismatched buffer — landscape streams get squashed
/// vertically and portrait streams horizontally. Returning dw x dh (only
/// rounded to even for codec friendliness) keeps buffer == render target, and
/// Flutter's FittedBox(contain) handles the actual layout scaling.
Size mpvOhosSurfaceSize(Size display) {
  if (!display.width.isFinite ||
      !display.height.isFinite ||
      display.width <= 0 ||
      display.height <= 0) {
    return const Size(1920, 1080);
  }
  double even(double dimension) =>
      dimension >= 16 ? (dimension / 2).round() * 2.0 : 16.0;
  return Size(even(display.width), even(display.height));
}

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
  MpvOhosDecoderPolicy _decoderPolicy = MpvOhosDecoderPolicy();
  MpvOhosHwdecMode _initialHwdecMode = MpvOhosHwdecMode.direct;
  Timer? _hwdecConfirmationTimer;
  Future<void> _decoderTransition = Future<void>.value();
  StreamSubscription? _eventSub;

  // Raw mpv state used to synthesize VideoPlayerValue.
  bool _paused = false;
  bool _coreIdle = true;
  bool _pausedForCache = false;
  bool _eofReached = false;
  double? _timePosSeconds;
  Duration? _demuxerCacheDuration;

  bool _visualReady = false;
  // Set once the native first-frame event has arrived for the current
  // stream, distinct from _visualReady: the frame may have been rendered
  // into a buffer whose geometry is still pending reconfiguration, so we
  // keep the reveal gated on _visualReady (see _tryReveal).
  bool _firstFrameArrived = false;
  bool _fileLoaded = false;
  Completer<void>? _fileLoadedWaiter;
  // A missed native event triggers a state check, never an unconditional
  // success: opening a stream alone does not prove video is rendering.
  Timer? _revealFallbackTimer;

  // The buffer follows the stream's display size; Flutter scales its layout.
  // Coalesce pending sizes while allowing only one native update at a time.
  Size _appliedSurfaceSize = const Size(1920, 1080);
  Size? _reportedDisplaySize;
  Size? _pendingGeometry;
  Timer? _geometryDebounce;
  bool _geometryReconfiguring = false;
  int _geometryEpoch = 0;
  // Transient surface failures retry up to 20 times without ending playback.
  int _geometryReconfigFailures = 0;

  /// Current native buffer size (video display aspect). The widget wraps
  /// the texture in a SizedBox of exactly this size under FittedBox(contain).
  Size get surfaceSize => _appliedSurfaceSize;

  /// Called on the first decoded frame; wired by the owning widget to the
  /// first-frame watchdog plumbing.
  VoidCallback? onFirstFrameDecoded;

  /// Called (throttled natively) whenever mpv reports a fresh playback clock.
  void Function(DateTime at, Duration position)? onHeartbeat;

  /// Called whenever the demuxer cache depth estimate changes.
  void Function(DateTime? sampledAt, Duration? cacheTime)? onCacheDuration;

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
    if (_mpvDisposed) {
      await _method.invokeMethod('dispose', {'generation': _generation});
      return;
    }
    if (_mpvTextureId < 0 || _generation <= 0) {
      throw StateError('鸿蒙播放器未能创建视频输出');
    }
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
      final result = await _method.invokeMethod('getSurfaceSize', {
        'generation': _generation,
      });
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
    _hwdecConfirmationTimer?.cancel();
    await _applyDecoderActions(
        _decoderPolicy.beginStream(mode: _initialHwdecMode));
    if (_mpvDisposed) return;
    _clearCache();
    _eventGenFilter = _generation;
    // Reset per-stream visible state: the shared surface still holds the
    // previous stream's last frame, and width/height events of the new
    // stream fire before its first frame is presented. Closing the
    // visibility gate here keeps the widget on its loading state until the
    // new stream really presents.
    final wasVisualReady = _visualReady;
    _visualReady = false;
    _firstFrameArrived = false;
    _fileLoaded = false;
    _eofReached = false;
    _timePosSeconds = null;
    _demuxerCacheDuration = null;
    // A fresh stream must not inherit the previous room's idle/buffering
    // flags: a leftover _coreIdle=true (from a torn-down vo) would otherwise
    // surface the new room as "buffering" before its first frame presents.
    _coreIdle = true;
    _pausedForCache = false;
    _reportedDisplaySize = null;
    // NOTE: do NOT reset _appliedSurfaceSize here. It mirrors the native
    // buffer geometry (g_geoW/g_geoH) which does NOT change on a room switch
    // (loadfile replace does not touch SET_BUFFER_GEOMETRY). Keeping it lets
    // the first frame of a same-direction room skip the vo rebuild entirely;
    // resetting it to Size(0,0) would force a full vo=null→…→vo rebuild on
    // EVERY switch (even same-direction), causing a ~10s black spinner.
    _pendingGeometry = null;
    _geometryDebounce?.cancel();
    _geometryEpoch++;
    _geometryReconfigFailures = 0;
    _revealFallbackTimer?.cancel();
    _revealFallbackTimer = null;
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
    // Live streams (B 站 HTTP-FLV 等) use a no-cache / low-latency profile
    // aligned with the reference player (聚映) and libmpv integration README
    // §6.2. cache-pause=yes on a live stream would pause on cache underrun
    // with no way to seek-recover, repeatedly stalling playback — the root
    // cause of "live stream playback failed" on B 站.
    //
    // Both playback profiles are now unified to this live low-latency set;
    // the `lowLatency` parameter is kept only for interface compatibility.
    await _setProperty('video-sync', 'desync');
    await _setProperty('cache', 'no');
    await _setProperty('cache-pause', 'no');
    await _setProperty('demuxer-lavf-o', 'fflags=+nobuffer');
    await _setProperty('demuxer-max-back-bytes', '100KiB');
    await _setProperty('demuxer-max-bytes', '8MiB');
    await _setProperty('framedrop', 'vo');
    await _setProperty('demuxer-lavf-analyzeduration', '0.5');
    await _setProperty('demuxer-lavf-probesize', '1500000');
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
      try {
        await _setProperty(entry.key, entry.value);
      } on PlatformException {
        Log.w('[mpv-ctrl] unsupported option: ${entry.key}');
      }
    }
    final hwdec = _mapOhosHwdec(settings.videoHardwareDecoder.value) ??
        advanced['hwdec'] ??
        'ohcodec';
    _decoderPolicy = MpvOhosDecoderPolicy(preferredHwdec: hwdec != 'no');
    _initialHwdecMode =
        MpvOhosHwdecMode.fromCurrentValue(hwdec) ?? MpvOhosHwdecMode.direct;
  }

  Future<void> _applyDecoderActions(List<MpvOhosDecoderAction> actions) {
    _decoderTransition = _decoderTransition.then((_) async {
      for (final action in actions) {
        if (_mpvDisposed) return;
        switch (action.type) {
          case MpvOhosDecoderActionType.setHwdec:
            await _setProperty('hwdec', action.mpvValue!);
            break;
          case MpvOhosDecoderActionType.armConfirmation:
            _hwdecConfirmationTimer?.cancel();
            _hwdecConfirmationTimer = Timer(action.delay!, () {
              unawaited(
                  _applyDecoderActions(_decoderPolicy.onConfirmationTimeout()));
            });
            break;
          case MpvOhosDecoderActionType.cancelConfirmation:
            _hwdecConfirmationTimer?.cancel();
            break;
          case MpvOhosDecoderActionType.hardwareActive:
          case MpvOhosDecoderActionType.softwareResolved:
            Log.i(
                '[mpv-ctrl] decoder=${action.mpvValue} reason=${action.reason}');
            break;
        }
      }
    }).catchError((Object error) {
      if (!_mpvDisposed) onFatal?.call('解码器切换失败，请切换线路重试');
    });
    return _decoderTransition;
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
      await _method.invokeMethod('setProperty', {
        'name': name,
        'value': value,
        'generation': _generation,
      });
    } on PlatformException {
      if (!_mpvDisposed) rethrow;
    }
  }

  Future<String?> _getProperty(String name) async {
    if (_mpvDisposed) return null;
    try {
      return await _method.invokeMethod('getProperty', {
        'name': name,
        'generation': _generation,
      });
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

  /// Keep the newest requested size, including updates received in flight.
  void _scheduleGeometryReconfig(Size displaySize) {
    if (_mpvDisposed) return;
    _pendingGeometry = mpvOhosSurfaceSize(displaySize);
    _geometryDebounce?.cancel();
    if (_geometryReconfiguring) return;
    _queueGeometryReconfig();
  }

  void _queueGeometryReconfig({Duration? retryDelay}) {
    if (_mpvDisposed || _geometryReconfiguring) return;
    final target = _pendingGeometry;
    if (target == null || target == _appliedSurfaceSize) {
      _pendingGeometry = null;
      _tryReveal();
      return;
    }
    final orientationChanged = (target.width < target.height) !=
        (_appliedSurfaceSize.width < _appliedSurfaceSize.height);
    final delay = retryDelay ??
        (!_visualReady || orientationChanged
            ? Duration.zero
            : const Duration(milliseconds: 300));
    _geometryDebounce?.cancel();
    _geometryDebounce = Timer(delay, () {
      unawaited(_runGeometryReconfig());
    });
  }

  Future<void> _runGeometryReconfig() async {
    if (_mpvDisposed || _geometryReconfiguring) return;
    final target = _pendingGeometry;
    if (target == null) return;
    _pendingGeometry = null;
    // Acquire before the first await so property events cannot start a second
    // update. A later request replaces the pending size, never this transaction.
    _geometryReconfiguring = true;
    final epoch = _geometryEpoch;
    Duration? retryDelay;
    try {
      await _method.invokeMethod('reconfigureSurface', {
        'width': target.width.toInt(),
        'height': target.height.toInt(),
        'generation': _generation,
      });
      if (_mpvDisposed || epoch != _geometryEpoch) return;
      _geometryReconfigFailures = 0;
      _appliedSurfaceSize = target;
      // surfaceSize is separate from VideoPlayerValue.size. Notify even when
      // the metadata arrived earlier, so the widget uses the applied buffer.
      notifyListeners();
    } on PlatformException catch (error) {
      if (_mpvDisposed || epoch != _geometryEpoch) return;
      if (error.code == 'stale_player') {
        _pendingGeometry = null;
        return;
      }
      _geometryReconfigFailures++;
      Log.w('[mpv-ctrl] reconfigureSurface failed '
          '(${error.code}/${error.message}); attempt $_geometryReconfigFailures');
      if (_geometryReconfigFailures < 20) {
        // Prefer any newer size received while the failed call was in flight.
        _pendingGeometry ??= target;
        retryDelay = const Duration(milliseconds: 400);
      } else {
        _pendingGeometry = null;
      }
    } finally {
      _geometryReconfiguring = false;
      if (!_mpvDisposed) {
        _queueGeometryReconfig(retryDelay: retryDelay);
        _publish();
      }
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
    if (kind == 'decoder') {
      unawaited(_applyDecoderActions(_decoderPolicy.onMpvLog(
        event['text'] as String? ?? '',
      )));
    } else if (kind == 'property' && name != null) {
      _handleProperty(name, valueText);
    } else if (kind == 'event' && name == 'video-frame-presented') {
      _markVisualReady();
    } else if (kind == 'event' && name == 'file-loaded') {
      _fileLoaded = true;
      unawaited(_applyDecoderActions(_decoderPolicy.onFileLoaded()));
      final waiter = _fileLoadedWaiter;
      if (waiter != null) {
        _fileLoadedWaiter = null;
        waiter.complete();
      }
      unawaited(_refreshDisplaySize());
      _revealFallbackTimer?.cancel();
      _revealFallbackTimer = Timer(const Duration(seconds: 3), () {
        unawaited(_verifyVideoRendering());
      });
    } else if (kind == 'event' && name == 'end-file') {
      _fileLoaded = false;
      _hwdecConfirmationTimer?.cancel();
      _decoderPolicy.reset();
      _revealFallbackTimer?.cancel();
      _clearCache();
      if (valueText == 'error') {
        final code = event['code'];
        final text = event['text'] as String? ?? '';
        Log.w('[mpv-ctrl] end-file error code=${code ?? '?'} text=$text');
        unawaited(_confirmFatal());
      }
    } else if (kind == 'event' && name == 'shutdown') {
      onFatal?.call('player shut down');
    }
  }

  void _handleProperty(String name, String valueText) {
    switch (name) {
      case 'hwdec-current':
        unawaited(
            _applyDecoderActions(_decoderPolicy.onHwdecCurrent(valueText)));
        break;
      case 'pause':
        _paused = _containsYes(valueText);
        break;
      case 'core-idle':
        _coreIdle = _containsYes(valueText);
        // core-idle=no is mpv's authoritative "the video core is running"
        // signal and doubles as the primary first-frame marker. The native
        // "video-frame-presented" event can be lost to a cross-room
        // generation race (its gate never catches up), which would otherwise
        // leave the spinner up forever while audio plays. Reveal on
        // core-idle=no instead, mirroring the reference player's
        // notifyVideoRendering path, but only once the stream is confirmed
        // open so a stale idle flip cannot flash the previous room's frame.
        if (!_coreIdle && _fileLoaded && _reportedDisplaySize != null) {
          _markVisualReady();
        }
        break;
      case 'paused-for-cache':
        _pausedForCache = _containsYes(valueText);
        break;
      case 'eof-reached':
        _eofReached = _containsYes(valueText);
        break;
      case 'time-pos':
        if (!_fileLoaded) {
          break;
        }
        final position = parseMpvOhosDurationSeconds(valueText);
        if (position != null) {
          _timePosSeconds = position.inMicroseconds / 1000000.0;
          onHeartbeat?.call(DateTime.now(), position);
        }
        break;
      case 'demuxer-cache-duration':
        if (!_fileLoaded) {
          break;
        }
        final sampledAt = DateTime.now();
        _demuxerCacheDuration = parseMpvOhosDurationSeconds(valueText);
        onCacheDuration?.call(sampledAt, _demuxerCacheDuration);
        break;
      case 'video-out-params':
      case 'video-out-params/dw':
      case 'video-out-params/dh':
        // dw/dh is the display size (SAR applied, the authoritative aspect for
        // Flutter). The parent map serializes to an empty STRING and its
        // change event can fire before dw/dh are readable, so the individual
        // dw/dh leaf events (observed natively) are the reliable trigger.
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
    final dw =
        int.tryParse(await _getProperty('video-out-params/dw') ?? '') ?? 0;
    final dh =
        int.tryParse(await _getProperty('video-out-params/dh') ?? '') ?? 0;
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

  Future<void> _verifyVideoRendering() async {
    if (_mpvDisposed || !_fileLoaded || _firstFrameArrived) return;
    await _refreshDisplaySize();
    final idle = await _getProperty('core-idle');
    if (!_mpvDisposed &&
        _fileLoaded &&
        _reportedDisplaySize != null &&
        idle == 'no') {
      _markVisualReady();
    }
  }

  Future<void> _refreshSize() async {
    // width/height is the decoded STORAGE size (rotation not applied); for a
    // portrait stream encoded landscape with a 90-degree rotation matrix it
    // reports e.g. 1920x1080 while the real display is 1080x1920. Using it to
    // set value.size would make Flutter lay the texture out in the wrong
    // orientation (portrait squashed horizontally / landscape squashed
    // vertically). Always go through the rotation-aware dw/dh path instead;
    // the raw width/height event is only a hint that the stream has a video
    // track and a fresh display size may now be readable.
    await _refreshDisplaySize();
  }

  Duration _positionFromSeconds(double seconds) {
    final ms = (seconds * 1000).round();
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  void _clearCache() {
    _demuxerCacheDuration = null;
    onCacheDuration?.call(null, null);
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
    if (_mpvDisposed || !_fileLoaded || _firstFrameArrived) {
      return;
    }
    _firstFrameArrived = true;
    _revealFallbackTimer?.cancel();
    _revealFallbackTimer = null;
    // The first-frame watchdog stops on the decoded frame, even if the frame
    // was rendered into a buffer whose geometry still needs reconfiguring.
    onFirstFrameDecoded?.call();
    _tryReveal();
  }

  /// Reveals the texture (sets _visualReady) once the first frame has arrived
  /// and the display size is known. Reveal is deliberately decoupled from the
  /// surface-geometry reconfig: the native reconfigure no longer tears the vo
  /// down (only the first resize does), so there is no black frame to hide.
  /// The buffer geometry follows the stream on its own via mpv's VIDEO_RECONFIG,
  /// and Flutter's FittedBox(contain) keeps the picture undistorted throughout,
  /// exactly like the reference player (Juying) which reveals videoVisible
  /// independently of setSurfaceSize/forceVoResize.
  void _tryReveal() {
    if (_mpvDisposed || _visualReady) {
      return;
    }
    if (!_firstFrameArrived) {
      return;
    }
    // Never reveal before the display size is known: doing so would show the
    // first frame rendered into the previous room's buffer for one frame
    // before the geometry reconfig catches up (the "比例残留" flash). The
    // size is guaranteed known by the time _refreshDisplaySize schedules the
    // reconfig, which re-enters _tryReveal once it settles.
    if (_reportedDisplaySize == null) {
      return;
    }
    _visualReady = true;
    // visualReady is controller state but is intentionally not duplicated in
    // VideoPlayerValue. Notify the widget listener exactly once so it can
    // replace the loading surface on the next frame without rebuilding for
    // every time-pos heartbeat.
    notifyListeners();
  }

  @override
  Future<void> initialize() async {
    // The mpv path does not talk to the video_player platform; initialization
    // happens through mpvCreate/mpvLoad driven by the owning widget.
    if (!_mpvDisposed && _mpvTextureId >= 0) {
      value = value.copyWith(isInitialized: true);
    }
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
    if (_mpvDisposed) return;
    final clamped = volume.clamp(0.0, 1.0);
    if (value.volume != clamped) {
      value = value.copyWith(volume: clamped);
    }
    await _setProperty('volume', (clamped * 100).toStringAsFixed(1));
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    if (_mpvDisposed) return;
    if (!speed.isFinite || speed <= 0) {
      throw ArgumentError.value(speed, 'speed', '必须为有限正数');
    }
    await _setProperty('speed', speed.toString());
    if (!_mpvDisposed) value = value.copyWith(playbackSpeed: speed);
  }

  @override
  Future<void> setLooping(bool looping) async {
    await _setProperty('loop-file', looping ? 'inf' : 'no');
    if (!_mpvDisposed) value = value.copyWith(isLooping: looping);
  }

  Future<String?> readProperty(String name) => _getProperty(name);

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
    _clearCache();
    _mpvDisposed = true;
    _hwdecConfirmationTimer?.cancel();
    _decoderPolicy.reset();
    _geometryDebounce?.cancel();
    _revealFallbackTimer?.cancel();
    _revealFallbackTimer = null;
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
