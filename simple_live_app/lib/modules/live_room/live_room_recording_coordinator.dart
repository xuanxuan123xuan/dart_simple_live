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
      required this.danmakuVisible}) {
    capture = DanmakuCaptureController(
      mediaPosition: () => readMpvRecordingPosition(player()),
      onFrame: _onFrame,
      onError: (_, __) {
        _service.markCaptureFailure();
        unawaited(stop(reason: '弹幕素材写入失败'));
      },
    );
    _service.addListener(_changed);
  }

  final Player Function() player;
  final String Function() roomId, roomTitle, platform;
  final bool Function() canRecord, danmakuVisible;
  final _service = RecordingService.instance;
  late final DanmakuCaptureController capture;
  StreamSubscription<bool>? _playing;
  StreamSubscription<PlayerLog>? _logs;
  Timer? _clock;
  Future<void>? _startPending;
  Future<void>? _stopPending;
  String? _sessionId;
  bool _disposed = false, _choosing = false;
  Rect? Function()? videoRect;
  bool get active =>
      _sessionId != null && _service.activeSession?.id == _sessionId;
  bool get busy => _choosing || _startPending != null || _stopPending != null;
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
      unawaited(_logs?.cancel());
      _playing = null;
      _logs = null;
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
      final directory = await resolveOrChooseRecordingDirectory();
      if (directory == null || _disposed || !canRecord()) return;
      await _service.initialize(directory.path);
      final start = _start(mode);
      _startPending = start;
      await start;
    } on Object catch (error) {
      if (!_disposed) SmartDialog.showToast('无法开始录制：$error');
    } finally {
      _startPending = null;
      _choosing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _start(RecordingMode mode) async {
    await capture.reset();
    await _service.start(RecordingStartRequest(
      roomId: roomId(),
      roomTitle: roomTitle(),
      platform: platform(),
      mode: mode,
      source: MpvRecordingSource(player()),
      beforeStop: () async {
        capture.enabled = false;
        await capture.flush();
      },
    ));
    _sessionId = _service.activeSession?.id;
    if (_disposed) {
      await _service.stop(reason: '离开直播间');
      return;
    }
    capture.enabled = mode != RecordingMode.videoOnly;
    _playing = player().stream.playing.listen((playing) {
      if (!playing && active) unawaited(stop(reason: '播放已暂停'));
    });
    _logs = player().stream.log.listen((log) {
      if (active &&
          (log.prefix.contains('recorder') ||
              log.text.contains('Disabling recording')) &&
          (log.level == 'error' || log.text.contains('Disabling recording'))) {
        unawaited(stop(reason: '录制写入中断'));
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
        return;
      }
    }
    if (!active) return;
    capture.enabled = false;
    await capture.flush();
    await _playing?.cancel();
    _playing = null;
    await _logs?.cancel();
    _logs = null;
    _clock?.cancel();
    await _service.stop(reason: reason);
    _sessionId = null;
    if (!_disposed) {
      notifyListeners();
      SmartDialog.showToast('本段录制已保存，可在“录制文件”中查看');
    }
  }

  Future<void> close() async {
    _disposed = true;
    await stop(reason: '离开直播间');
    await _playing?.cancel();
    await _logs?.cancel();
    _clock?.cancel();
    _service.removeListener(_changed);
    capture.dispose();
    super.dispose();
  }
}
