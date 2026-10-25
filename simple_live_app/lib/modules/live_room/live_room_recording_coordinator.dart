import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/modules/recordings/recording_preferences.dart';
import 'package:simple_live_app/services/recording/mpv_recording_source.dart';
import 'package:simple_live_app/services/recording/recording_diagnostics.dart';
import 'package:simple_live_app/services/recording/recording_service.dart';

/// Room-owned binding. Recording persistence and exporting live in the service;
/// this object only binds its player's lifetime and its visible danmaku layer.
class LiveRoomRecordingCoordinator extends ChangeNotifier {
  LiveRoomRecordingCoordinator(
      {required this.player,
      required this.roomId,
      required this.roomTitle,
      required this.platform,
      required this.canRecord,
      required this.danmakuVisible,
      this.protectPlayerMutation,
      this.playerMutationQuiet = _alwaysFalse,
      RecordingService? service,
      this.sourceFactory,
      this.isPlaying,
      this.playingChanges,
      this.mediaPosition,
      this.showMessage = SmartDialog.showToast})
      : _service = service ?? RecordingService.instance {
    capture = DanmakuCaptureController(
      mediaPosition: () =>
          mediaPosition?.call() ?? readMpvRecordingPosition(player()),
      onFrame: _onFrame,
      onError: (_, __) {
        if (_disposed || !active) return;
        _service.markCaptureFailure();
        _stopSafely('弹幕素材写入失败');
      },
    );
    _service.addListener(_changed);
  }

  final Player Function() player;
  final String Function() roomId, roomTitle, platform;
  final bool Function() canRecord, danmakuVisible;
  final Future<void> Function(Future<void> Function())? protectPlayerMutation;
  final bool Function() playerMutationQuiet;
  final RecordingService _service;
  final RecordingSource Function(
      RecordingMode, void Function(Object, StackTrace))? sourceFactory;
  final bool Function()? isPlaying;
  final Stream<bool> Function()? playingChanges;
  final Duration Function()? mediaPosition;
  final void Function(String) showMessage;
  late final DanmakuCaptureController capture;
  StreamSubscription<bool>? _playing;
  Timer? _clock;
  Future<void> _operations = Future<void>.value();
  Future<void>? _closePending;
  Future<void>? _stopPending;
  int _pendingOperations = 0;
  int _intentRevision = 0;
  String? _sessionId;
  RecordingSource? _ownedSource;
  bool _notifierDisposed = false;
  bool _disposed = false, _choosing = false;
  bool _resumeAfterPlayerMutation = false;
  bool _resuming = false;
  bool _stopping = false;
  RecordingMode? _intentMode;
  String? _intentRoom;
  Rect? Function()? videoRect;
  bool get active =>
      _sessionId != null && _service.activeSession?.id == _sessionId;
  bool get busy => _choosing || _pendingOperations > 0;
  bool get mutationInProgress => _pendingOperations > 0;
  bool get hasPendingCleanup =>
      _ownedSource != null && _service.ownsSource(_ownedSource!) && !active;
  bool get requested => active || _intentMode != null || hasPendingCleanup;
  bool get waitingToResume => _resumeAfterPlayerMutation || _resuming;
  bool get _playingNow => isPlaying?.call() ?? player().state.playing;
  String get _roomKey => '${platform()}:${roomId()}';

  bool _current(int revision) =>
      !_disposed &&
      revision == _intentRevision &&
      _intentMode != null &&
      _intentRoom == _roomKey;

  Future<void> _enqueue(Future<void> Function() operation) {
    _pendingOperations++;
    final result = _operations.then((_) => operation());
    void completed() {
      _pendingOperations--;
      if (!_disposed) _changed();
    }

    // Keep the queue usable after failures and observe errors even when a
    // lifecycle callback has no caller that can await its result.
    _operations = result.then<void>((_) => completed(),
        onError: (Object _, StackTrace __) {
      completed();
    });
    if (!_disposed) notifyListeners();
    return result;
  }

  void _cancelIntent() {
    _intentRevision++;
    _intentMode = null;
    _intentRoom = null;
    _resumeAfterPlayerMutation = false;
  }

  void _stopSafely(String reason) {
    unawaited(stop(reason: reason).catchError((Object error) {
      if (!_disposed) showMessage('停止录制失败：$error');
    }));
  }

  Duration get elapsed {
    final session = _service.activeSession;
    return active && session != null
        ? DateTime.now().difference(session.createdAt)
        : Duration.zero;
  }

  void _changed() {
    if (!active && _sessionId != null) {
      capture.enabled = false;
      _sessionId = null;
      _clock?.cancel();
      unawaited(_playing?.cancel());
      _playing = null;
      if (!_stopping) _cancelIntent();
    }
    if (active && !busy && !playerMutationQuiet() && !_playingNow) {
      _stopSafely('播放已暂停');
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> toggle(BuildContext context) async {
    if (requested) {
      try {
        await stop();
      } catch (error) {
        if (!_disposed) showMessage('停止录制失败，原始素材已保留：$error');
      }
      return;
    }
    if (_disposed || busy || !canRecord()) {
      RecordingDiagnostics.instance.write('ui.start.blocked', data: {
        'room': _roomKey,
        'disposed': _disposed,
        'busy': busy,
      });
      return;
    }
    _choosing = true;
    final revision = ++_intentRevision;
    final room = _roomKey;
    notifyListeners();
    var phase = 'chooseMode';
    RecordingDiagnostics.instance
        .write('ui.start.request', data: {'room': room, 'revision': revision});
    try {
      final mode = await chooseRecordingMode(context);
      if (mode == null ||
          _disposed ||
          revision != _intentRevision ||
          room != _roomKey ||
          !canRecord()) {
        return;
      }
      phase = 'resolveDirectory';
      RecordingDiagnostics.instance.write('ui.start.mode',
          data: {'room': room, 'revision': revision, 'mode': mode.name});
      final directory = await resolveOrChooseRecordingDirectory();
      if (directory == null ||
          _disposed ||
          revision != _intentRevision ||
          room != _roomKey ||
          !canRecord()) {
        return;
      }
      phase = 'initializeDirectory';
      RecordingDiagnostics.instance.write('ui.start.directory', data: {
        'room': room,
        'revision': revision,
        'directory': directory.path,
      });
      await _service.initialize(directory.path);
      phase = 'rememberDirectory';
      await rememberRecordingDirectory(directory);
      if (_disposed ||
          revision != _intentRevision ||
          room != _roomKey ||
          !canRecord()) {
        return;
      }
      phase = 'startSource';
      await _requestStart(mode);
    } on Object catch (error, stack) {
      RecordingDiagnostics.instance.write('ui.start.failed',
          data: {
            'room': room,
            'revision': revision,
            'phase': phase,
          },
          error: error,
          stackTrace: stack);
      if (!active) _cancelIntent();
      if (!_disposed) showMessage('无法开始录制：$error');
      await RecordingDiagnostics.instance.flush();
    } finally {
      _choosing = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Starts in an already initialized recording directory. Also used by
  /// room-independent callers and deterministic lifecycle tests.
  Future<void> start(RecordingMode mode) {
    if (_disposed || busy || requested || !canRecord()) {
      return Future<void>.value();
    }
    return _requestStart(mode);
  }

  Future<void> _requestStart(RecordingMode mode) {
    _intentMode = mode;
    _intentRoom = _roomKey;
    final revision = ++_intentRevision;
    return _enqueue(() => _start(mode, revision));
  }

  Future<void> _start(RecordingMode mode, int revision) async {
    if (!_current(revision) || !canRecord()) {
      if (!_disposed && revision == _intentRevision) _cancelIntent();
      return;
    }
    await capture.reset();
    if (!_current(revision) || !canRecord()) {
      if (!_disposed && revision == _intentRevision) _cancelIntent();
      return;
    }
    void onSourceError(Object error, StackTrace stack) {
      RecordingDiagnostics.instance.write('ui.source.error',
          data: {
            'room': _roomKey,
            'revision': revision,
            'current': _current(revision),
            'sessionId': _sessionId,
          },
          error: error,
          stackTrace: stack);
      if (_disposed || !_current(revision)) return;
      _stopSafely('录制写入中断');
    }

    final source = sourceFactory?.call(mode, onSourceError) ??
        MpvRecordingSource(
          player(),
          captureTimeline: mode != RecordingMode.videoOnly,
          protectNativeMutation: protectPlayerMutation,
          onError: onSourceError,
        );
    _ownedSource = source;
    try {
      await _service.start(RecordingStartRequest(
        roomId: roomId(),
        roomTitle: roomTitle(),
        platform: platform(),
        mode: mode,
        source: source,
        beforeStop: () async {
          capture.enabled = false;
          await capture.flush();
        },
      ));
    } on Object {
      if (_current(revision)) _cancelIntent();
      rethrow;
    }
    _sessionId = _service.activeSession?.id;
    RecordingDiagnostics.instance.write('ui.start.ready', data: {
      'room': _roomKey,
      'revision': revision,
      'sessionId': _sessionId,
      'mode': mode.name,
      'current': _current(revision),
    });
    if (!_current(revision)) {
      await _stopCurrent('录制已取消');
      return;
    }
    capture.enabled = mode != RecordingMode.videoOnly;
    _playing =
        (playingChanges?.call() ?? player().stream.playing).listen((playing) {
      if (!playing && active && !playerMutationQuiet()) {
        _stopSafely('播放已暂停');
      }
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
    notifyListeners();
    showMessage('录制已开始');
  }

  Future<void> _onFrame(DanmakuCaptureFrame frame) async {
    if (!active) return;
    final sessionId = _sessionId;
    for (final sprite in frame.sprites) {
      await _service.registerSprite(sprite.id, sprite.pngBytes,
          sessionId: sessionId);
    }
    if (!active || _sessionId != sessionId) return;
    final position = frame.mediaPosition;
    if (position == null) return;
    final video = videoRect?.call();
    _service.recordFrame(
        RecordingOverlayFrame(
          position: position,
          canvasWidth: frame.viewportSize.width,
          canvasHeight: frame.viewportSize.height,
          videoLeft: video?.left ?? 0,
          videoTop: video?.top ?? 0,
          videoWidth: video?.width,
          videoHeight: video?.height,
          opacity: danmakuVisible() ? frame.opacity : 0,
          items: frame.placements
              .map((item) => RecordingOverlayItem(
                    spriteId: item.spriteId,
                    instanceId: item.instanceId,
                    x: item.x,
                    y: item.y,
                    width: item.width,
                    height: item.height,
                    opacity: item.opacity,
                    transform: item.transform,
                    transformOriginX: item.transformOriginX,
                    transformOriginY: item.transformOriginY,
                  ))
              .toList(growable: false),
        ),
        sessionId: sessionId);
  }

  void visibilityChanged(bool visible) {
    if (!active) return;
    final frame = capture.latestFrame;
    if (frame == null) return;
    _service.recordFrame(
        RecordingOverlayFrame(
          position: mediaPosition?.call() ?? readMpvRecordingPosition(player()),
          canvasWidth: frame.viewportSize.width,
          canvasHeight: frame.viewportSize.height,
          items: const [],
        ),
        force: true);
    if (visible) {
      capture.enabled = false;
      capture.enabled = true;
    }
  }

  Future<void> stop({String reason = '手动停止'}) {
    // Invalidate before entering the queue so an in-flight resume wait or
    // source start cannot revive a cancelled recording.
    _cancelIntent();
    final pending = _stopPending;
    if (pending != null) return pending;
    final operation = _enqueue(() => _stopCurrent(reason));
    _stopPending = operation;
    return operation.whenComplete(() => _stopPending = null);
  }

  Future<void> _stopCurrent(String reason) async {
    if (!active) {
      final source = _ownedSource;
      if (source != null && _service.ownsSource(source)) {
        await _service.stop(reason: reason);
      }
      if (source == null || !_service.ownsSource(source)) _ownedSource = null;
      return;
    }
    final session = _service.activeSession!;
    _stopping = true;
    try {
      capture.enabled = false;
      await capture.flush();
      await _playing?.cancel();
      _playing = null;
      _clock?.cancel();
      await _service.stop(reason: reason);
      _ownedSource = null;
      _sessionId = null;
      if (!_disposed) {
        notifyListeners();
        showMessage(session.status == RecordingStatus.failed
            ? '本段录制保存失败，已保留可恢复的素材'
            : '本段录制已保存，可在“录制文件”中查看');
      }
    } finally {
      _stopping = false;
    }
  }

  Future<void> close() {
    final pending = _closePending;
    if (pending != null) return pending;
    _disposed = true;
    _cancelIntent();
    final operation = _enqueue(() async {
      try {
        await _stopCurrent('离开直播间');
      } finally {
        await _playing?.cancel();
        _clock?.cancel();
        if (!_notifierDisposed) {
          _service.removeListener(_changed);
          capture.dispose();
          super.dispose();
          _notifierDisposed = true;
        }
      }
    });
    return _closePending =
        operation.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      _closePending = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> suspendForPlayerMutation({
    bool resumeAfterMutation = false,
  }) async {
    if (_disposed) {
      await close();
      return;
    }
    if (resumeAfterMutation && _intentRoom == _roomKey) {
      _resumeAfterPlayerMutation = true;
    } else {
      _cancelIntent();
    }
    await _enqueue(() => _stopCurrent('播放源或播放状态变化'));
  }

  Future<void> resumeAfterPlayerMutation() async {
    if (!_resumeAfterPlayerMutation) return;
    final revision = _intentRevision;
    final mode = _intentMode;
    _resumeAfterPlayerMutation = false;
    if (!_current(revision) || mode == null) {
      if (!_disposed && revision == _intentRevision) _cancelIntent();
      return;
    }
    _resuming = true;
    await _enqueue(() async {
      try {
        for (var attempt = 0;
            attempt < 20 && _current(revision) && !_playingNow;
            attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!_current(revision)) return;
        if (!canRecord()) {
          _cancelIntent();
          return;
        }
        await _start(mode, revision);
      } catch (_) {
        if (_current(revision)) _cancelIntent();
      } finally {
        _resuming = false;
        if (!_disposed) notifyListeners();
      }
    });
  }

  static bool _alwaysFalse() => false;
}
