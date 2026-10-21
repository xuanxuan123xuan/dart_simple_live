import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/modules/recordings/recording_preferences.dart';
import 'package:simple_live_app/services/recording/mpv_recording_source.dart';
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
      this.playerMutationQuiet = _alwaysFalse}) {
    capture = DanmakuCaptureController(
      mediaPosition: () => readMpvRecordingPosition(player()),
      onFrame: _onFrame,
      onError: (_, __) {
        if (_disposed || !active) return;
        _service.markCaptureFailure();
        unawaited(stop(reason: '弹幕素材写入失败'));
      },
    );
    _service.addListener(_changed);
  }

  final Player Function() player;
  final String Function() roomId, roomTitle, platform;
  final bool Function() canRecord, danmakuVisible;
  final Future<void> Function(Future<void> Function())?
      protectPlayerMutation;
  final bool Function() playerMutationQuiet;
  final _service = RecordingService.instance;
  late final DanmakuCaptureController capture;
  StreamSubscription<bool>? _playing;
  Timer? _clock;
  Future<void>? _startPending;
  Future<void>? _stopPending;
  String? _sessionId;
  bool _disposed = false, _choosing = false;
  bool _resumeAfterPlayerMutation = false;
  RecordingMode? _intentMode;
  Rect? Function()? videoRect;
  bool get active =>
      _sessionId != null && _service.activeSession?.id == _sessionId;
  bool get busy => _choosing || _startPending != null || _stopPending != null;
  bool get mutationInProgress => _startPending != null || _stopPending != null;
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
    }
    if (active && !playerMutationQuiet() && !player().state.playing) {
      unawaited(stop(reason: '播放已暂停'));
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> toggle(BuildContext context) async {
    if (active || _startPending != null) {
      await stop();
      return;
    }
    if (_disposed || busy || !canRecord()) return;
    _choosing = true;
    notifyListeners();
    try {
      final mode = await chooseRecordingMode(context);
      if (mode == null || _disposed || !canRecord()) return;
      _intentMode = mode;
      final directory = await resolveOrChooseRecordingDirectory();
      if (directory == null || _disposed || !canRecord()) return;
      await _service.initialize(directory.path);
      final start = _start(mode);
      _startPending = start;
      await start;
    } on Object catch (error) {
      if (!active) _intentMode = null;
      if (!_disposed) SmartDialog.showToast('无法开始录制：$error');
    } finally {
      _startPending = null;
      _choosing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _start(RecordingMode mode) async {
    await capture.reset();
    final source = MpvRecordingSource(
      player(),
      onError: (_, __) {
        if (_disposed || !active) return;
        unawaited(stop(reason: '录制写入中断'));
      },
    );
    await _runProtected(() => _service.start(RecordingStartRequest(
          roomId: roomId(),
          roomTitle: roomTitle(),
          platform: platform(),
          mode: mode,
          source: source,
          beforeStop: () async {
            capture.enabled = false;
            await capture.flush();
          },
        )));
    _sessionId = _service.activeSession?.id;
    if (_disposed) {
      await _service.stop(reason: '离开直播间');
      return;
    }
    capture.enabled = mode != RecordingMode.videoOnly;
    _playing = player().stream.playing.listen((playing) {
      if (!playing && active && !playerMutationQuiet()) {
        unawaited(stop(reason: '播放已暂停'));
      }
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
    notifyListeners();
    SmartDialog.showToast('录制已开始');
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
          position: readMpvRecordingPosition(player()),
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
    _resumeAfterPlayerMutation = false;
    _intentMode = null;
    final pending = _stopPending;
    if (pending != null) return pending;
    final operation = _stop(reason);
    _stopPending = operation;
    return operation.whenComplete(() => _stopPending = null);
  }

  Future<void> _stop(String reason) async {
    final pending = _startPending;
    if (pending != null) {
      try {
        await pending;
      } on Object {
        if (!_resumeAfterPlayerMutation) _intentMode = null;
        return;
      }
    }
    if (!active) {
      if (!_resumeAfterPlayerMutation) _intentMode = null;
      return;
    }
    capture.enabled = false;
    await capture.flush();
    await _playing?.cancel();
    _playing = null;
    _clock?.cancel();
    await _runProtected(() => _service.stop(reason: reason));
    _sessionId = null;
    if (!_resumeAfterPlayerMutation) _intentMode = null;
    if (!_disposed) {
      notifyListeners();
      SmartDialog.showToast('本段录制已保存，可在“录制文件”中查看');
    }
  }

  Future<void> close() async {
    _disposed = true;
    _resumeAfterPlayerMutation = false;
    _intentMode = null;
    await stop(reason: '离开直播间');
    await _playing?.cancel();
    _clock?.cancel();
    _service.removeListener(_changed);
    capture.dispose();
    super.dispose();
  }

  Future<void> suspendForPlayerMutation({
    bool resumeAfterMutation = false,
  }) async {
    if (resumeAfterMutation) {
      _resumeAfterPlayerMutation = true;
    } else if (!_resumeAfterPlayerMutation) {
      _intentMode = null;
    }
    await _stop('播放源或播放状态变化');
  }

  Future<void> resumeAfterPlayerMutation() async {
    if (!_resumeAfterPlayerMutation) return;
    final mode = _intentMode;
    _resumeAfterPlayerMutation = false;
    if (_disposed || mode == null) {
      _intentMode = null;
      return;
    }
    for (var attempt = 0;
        attempt < 20 && !_disposed && !player().state.playing;
        attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (_disposed || !canRecord()) {
      _intentMode = null;
      return;
    }
    try {
      final start = _start(mode);
      _startPending = start;
      await start;
    } catch (_) {
      _intentMode = null;
    } finally {
      _startPending = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _runProtected(Future<void> Function() operation) {
    return protectPlayerMutation?.call(operation) ?? operation();
  }

  static bool _alwaysFalse() => false;
}
