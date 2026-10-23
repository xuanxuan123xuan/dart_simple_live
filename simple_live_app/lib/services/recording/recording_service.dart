import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'recording_backend.dart';
import 'recording_models.dart';
export 'recording_models.dart';

class RecordingService extends ChangeNotifier with WidgetsBindingObserver {
  static const _probeTimeout = Duration(seconds: 8);
  static const _timelineTimeout = Duration(seconds: 12);
  RecordingService({RecordingBackend? backend})
      : _backend = backend ?? FFmpegRecordingBackend();
  static final RecordingService instance = RecordingService();
  final RecordingBackend _backend;
  final List<RecordingSession> _sessions = [];
  final List<String> _queue = [];
  final Set<String> _cancelled = {};
  String? _root;
  RecordingSession? _active;
  RecordingSource? _source;
  Future<void> Function()? _beforeStop;
  IOSink? _frames;
  bool _transitioning = false, _workerRunning = false, _foreground = true;
  bool _observingLifecycle = false;
  int _lastFrameMs = -1;
  int _frameCount = 0;
  int _spriteBytes = 0;
  Object? _materialError;
  final Map<String, Future<void>> _saves = {};
  Future<void> _materialWrites = Future.value();
  Future<void> _captureOperations = Future.value();
  List<RecordingSession> get sessions => List.unmodifiable(_sessions);
  RecordingSession? get activeSession => _active;
  bool get isRecording => _active != null;

  Future<void> initialize(String rootPath) async {
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    final root = p.normalize(p.absolute(rootPath));
    if (_root == root) return;
    if (_active != null ||
        _workerRunning ||
        _transitioning ||
        _queue.isNotEmpty) {
      throw StateError('Recording is busy');
    }
    await Directory(root).create(recursive: true);
    _root = root;
    _sessions.clear();
    await for (final entry in Directory(root).list()) {
      if (entry is! Directory) continue;
      try {
        final manifest = File(p.join(entry.path, 'session.json'));
        final backup = File('${manifest.path}.previous');
        final file = await manifest.exists() ? manifest : backup;
        final session = RecordingSession.fromJson(
            jsonDecode(await file.readAsString()) as Map<String, dynamic>,
            entry.path);
        if ({
          RecordingStatus.recording,
          RecordingStatus.exporting,
          RecordingStatus.queued
        }.contains(session.status)) {
          session.status = RecordingStatus.interrupted;
          session.error = '上次任务未正常结束，原始文件已保留，可重试导出';
          await _save(session);
        }
        _sessions.add(session);
      } on Object {
        // A damaged manifest must never prevent access to other recordings.
      }
    }
    _sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Future<void> _captureOperation(Future<void> Function() operation) {
    final result =
        _captureOperations.catchError((Object _) {}).then((_) => operation());
    _captureOperations = result;
    return result;
  }

  Future<void> start(RecordingStartRequest request) =>
      _captureOperation(() => _start(request));

  Future<void> _start(RecordingStartRequest request) async {
    if (_root == null) throw StateError('Recording storage is not initialized');
    if (_active != null || _transitioning) {
      throw StateError('Already recording');
    }
    _transitioning = true;
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}';
    final session = RecordingSession(
        id: id,
        directory: p.join(_root!, id),
        roomId: request.roomId,
        roomTitle: request.roomTitle,
        platform: request.platform,
        mode: request.mode,
        createdAt: now);
    try {
      await Directory(p.join(session.directory, 'sprites'))
          .create(recursive: true);
      await _save(session);
      await request.source.start(session.rawPath);
      _active = session;
      _source = request.source;
      _beforeStop = request.beforeStop;
      _lastFrameMs = -1;
      _frameCount = 0;
      _spriteBytes = 0;
      _materialError = null;
      _materialWrites = Future.value();
      _frames = File(p.join(session.directory, 'frames.jsonl')).openWrite();
      unawaited(_frames!.done.then<void>((_) {}, onError: (Object error) {
        _materialError = error;
      }));
      _sessions.insert(0, session);
    } on Object {
      try {
        await request.source.stop();
      } on Object {/* Keep partial media. */}
      session.status = RecordingStatus.failed;
      session.error = '无法启动录制';
      await _save(session);
      if (!_sessions.contains(session)) _sessions.insert(0, session);
      rethrow;
    } finally {
      _transitioning = false;
      notifyListeners();
    }
  }

  Future<void> registerSprite(String id, Uint8List png,
      {String? sessionId}) async {
    final session = _active;
    if (session == null || session.mode == RecordingMode.videoOnly) return;
    if (sessionId != null && session.id != sessionId) return;
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
      throw ArgumentError('Invalid sprite id');
    }
    if (png.length > 4 * 1024 * 1024) {
      throw StateError('Sprite exceeds size limit');
    }
    final file = File(p.join(session.directory, 'sprites', '$id.png'));
    _materialWrites = _materialWrites.then((_) async {
      if (!await file.exists()) {
        if (_spriteBytes + png.length > 256 * 1024 * 1024) {
          throw StateError('Danmaku sprite storage limit reached');
        }
        await file.writeAsBytes(png, flush: true);
        _spriteBytes += png.length;
      }
    });
    await _materialWrites;
  }

  void recordFrame(RecordingOverlayFrame frame,
      {String? sessionId, bool force = false}) {
    final session = _active;
    if (session == null || session.mode == RecordingMode.videoOnly) return;
    if (sessionId != null && session.id != sessionId) return;
    final ms = frame.position.inMilliseconds;
    if (ms < 0 ||
        ms < _lastFrameMs ||
        frame.canvasWidth <= 0 ||
        frame.canvasHeight <= 0 ||
        frame.items.length > 500) {
      return;
    }
    // Bound material to 60 fps and approximately 12 hours. No unbounded in-memory
    // history: each accepted frame is streamed to the session's JSONL file.
    if (!force && _lastFrameMs >= 0 && ms - _lastFrameMs < 16) return;
    if (_frameCount >= 2592000) {
      _materialError = StateError('Danmaku material duration limit reached');
      return;
    }
    _lastFrameMs = ms;
    _frameCount++;
    _frames?.writeln(jsonEncode(frame.toJson()));
  }

  void markCaptureFailure() {
    final session = _active;
    if (session == null || session.mode == RecordingMode.videoOnly) return;
    session.captureFailed = true;
    _materialError = StateError('Danmaku capture failed');
  }

  Future<void> stop({String reason = 'manual'}) =>
      _captureOperation(() => _stop(reason));

  Future<RecordingMediaInfo> _probeValid(String path) async {
    Object? lastError;
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        final info =
            await _backend.probe(path).timeout(_probeTimeout);
        if (info.valid) return info;
        lastError = StateError('Invalid recording media');
      } on Object catch (error) {
        lastError = error;
      }
      if (attempt < 7) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    throw StateError('Invalid recording: $lastError');
  }

  Future<void> _stop(String reason) async {
    final session = _active;
    if (session == null || _transitioning) return;
    _transitioning = true;
    final stageClock = Stopwatch()..start();
    void stage(String name) => developer.log(
          'stage=$name elapsedMs=${stageClock.elapsedMilliseconds}',
          name: 'simple_live.recording',
        );
    stage('stopping');
    RecordingMediaInfo? info;
    var probeAttempted = false;
    try {
      Object? beforeStopError;
      try {
        await _beforeStop?.call();
        stage('captureFlushed');
      } on Object catch (error) {
        beforeStopError = error;
      }
      Duration? position;
      try {
        position = await _source!.mediaPosition();
      } on Object {
        // The player may already be in the source-switching path. The flushed
        // file is still usable when its own media metadata is valid.
      }
      await _source!.stop();
      stage('sourceStopped');
      probeAttempted = true;
      info = await _probeValid(session.rawPath);
      stage('probed');
      if (beforeStopError != null) throw beforeStopError;
      RecordingTimeline? timeline;
      try {
        timeline = await _source!.timeline().timeout(_timelineTimeout);
      } on Object {
        timeline = null;
      }
      stage('timelineChecked');
      session.mediaStartMs = timeline?.mediaStart.inMilliseconds;
      session.fileStartMs = timeline?.fileStart.inMilliseconds ?? 0;
      session.timelineConfirmed = timeline?.confirmed ?? false;
      final duration = timeline == null || position == null
          ? info.duration - Duration(milliseconds: session.fileStartMs)
          : position - timeline.mediaStart;
      session.durationMs = duration.inMilliseconds.clamp(0, 1 << 53);
      session.captureDurationMs =
          session.timelineConfirmed && session.durationMs > 0
              ? session.durationMs
              : null;
      await _materialWrites;
      await _frames?.flush();
      await _frames?.close();
      if (_materialError != null) throw StateError('Material write failed');
      if (info.valid && await File(session.rawPath).exists()) {
        session.outputPath = session.rawPath;
      }
      session.stopReason = reason;
      session.status = RecordingStatus.ready;
    } on Object {
      session.status = RecordingStatus.failed;
      session.captureFailed = session.captureFailed || _materialError != null;
      session.error = session.captureFailed
          ? '弹幕素材捕获失败，原始视频已保留，可单独播放或无损导出'
          : '录制停止时发生错误，原始文件与弹幕素材已保留';
      final raw = File(session.rawPath);
      if (info?.valid == true) {
        session.outputPath = raw.path;
      } else if (!probeAttempted) {
        try {
          info = await _probeValid(raw.path);
          session.outputPath = info.valid ? raw.path : null;
        } on Object {
          session.outputPath = null;
        }
      }
      // Always attempt to detach stream-record even if position sampling failed.
      try {
        await _source?.stop();
      } on Object {/* Preserve the recording. */}
    } finally {
      try {
        await _frames?.close();
      } on Object {/* Preserve partial sidecar. */}
      _active = null;
      _source = null;
      _beforeStop = null;
      _frames = null;
      _transitioning = false;
      try {
        await _save(session);
      } on Object {
        session.status = RecordingStatus.failed;
        session.error = '无法保存录制状态，请检查剩余存储空间；原始文件已保留';
      }
      notifyListeners();
    }
    if (session.status == RecordingStatus.ready) {
      await exportSession(session.id);
    }
  }

  RecordingSession _find(String id) => _sessions.firstWhere((s) => s.id == id);

  Future<void> exportSession(String id, {bool burnDanmaku = false}) async {
    final session = _find(id);
    if (session == _active ||
        session.status == RecordingStatus.exporting ||
        _queue.contains(id)) {
      return;
    }
    if (!await File(session.rawPath).exists()) {
      session.status = RecordingStatus.failed;
      session.error = '原始录制文件不存在';
      await _save(session);
      notifyListeners();
      return;
    }
    _cancelled.remove(id);
    session.exportBurnDanmaku = burnDanmaku ||
        session.exportBurnDanmaku ||
        session.mode == RecordingMode.burnDanmaku;
    session.exportProgress = 0;
    session.status = RecordingStatus.queued;
    session.error = null;
    _queue.add(id);
    try {
      await _save(session);
    } on Object {
      _queue.remove(id);
      session.status = RecordingStatus.failed;
      session.error = '无法保存导出任务，请检查剩余存储空间';
      notifyListeners();
      return;
    }
    notifyListeners();
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_workerRunning || !_foreground) return;
    _workerRunning = true;
    try {
      while (_queue.isNotEmpty && _foreground) {
        final session = _find(_queue.removeAt(0));
        session.status = RecordingStatus.exporting;
        await _save(session);
        notifyListeners();
        final temporary = p.join(session.directory, 'export.partial.mp4');
        try {
          final info =
              await _backend.probe(session.rawPath).timeout(_probeTimeout);
          if (!info.valid) throw StateError('Invalid media');
          session.durationMs = info.duration.inMilliseconds;
          final capturedMs = session.captureDurationMs;
          final availableMs =
              info.duration.inMilliseconds - session.fileStartMs;
          final targetDuration = Duration(
              milliseconds: capturedMs != null &&
                      capturedMs > 0 &&
                      capturedMs < availableMs
                  ? capturedMs
                  : availableMs);
          var retainedRaw = false;
          if (session.exportBurnDanmaku) {
            if (session.captureFailed) {
              throw StateError('Danmaku capture failed');
            }
            await _backend.burn(session, temporary,
                () => _cancelled.contains(session.id) || !_foreground,
                onProgress: (value) {
              session.exportProgress = value.clamp(0, 1);
              notifyListeners();
            });
          } else if (info.mp4Compatible) {
            try {
              await _backend.remux(session.rawPath, temporary,
                  duration: targetDuration,
                  start: Duration(milliseconds: session.fileStartMs));
            } on Object {
              if (_cancelled.contains(session.id) || !_foreground) rethrow;
              retainedRaw = true;
            }
          } else {
            retainedRaw = true;
          }
          if (_cancelled.contains(session.id) || !_foreground) {
            throw StateError('Export cancelled');
          }
          if (retainedRaw) {
            session.outputPath = session.rawPath;
            session.status = RecordingStatus.complete;
            session.exportProgress = 1;
            session.error = 'MP4无法无损封装，已保留原始MKV（含录制缓存尾部）';
            await _save(session);
            notifyListeners();
            developer.log('stage=exported mode=raw', name: 'simple_live.recording');
            continue;
          }
          final result =
              await _backend.probe(temporary).timeout(_probeTimeout);
          if (!result.valid ||
              !result.mp4Compatible ||
              (session.exportBurnDanmaku && result.videoCodec != 'h264') ||
              (info.audioCodec != null && result.audioCodec != 'aac') ||
              (result.duration - targetDuration).inMilliseconds.abs() > 250 ||
              result.width != info.width ||
              result.height != info.height) {
            throw StateError('Export validation failed');
          }
          final output = File(p.join(session.directory, 'recording.mp4'));
          if (await output.exists()) await output.delete();
          await File(temporary).rename(output.path);
          session.outputPath = output.path;
          session.status = RecordingStatus.complete;
          session.durationMs = result.duration.inMilliseconds;
          session.exportProgress = 1;
          session.error = session.mode != RecordingMode.videoOnly &&
                  !session.timelineConfirmed
              ? '已保存视频与弹幕素材；未能确认媒体时间映射，暂无法合成弹幕'
              : null;
          developer.log('stage=exported mode=mp4', name: 'simple_live.recording');
        } on Object {
          if (!_foreground && !_cancelled.contains(session.id)) {
            session.status = RecordingStatus.queued;
            _queue.insert(0, session.id);
          } else {
            session.status = RecordingStatus.failed;
            session.error = _cancelled.contains(session.id)
                ? '已取消导出，原始文件与素材已保留'
                : session.captureFailed && session.exportBurnDanmaku
                    ? '弹幕素材捕获失败，无法合成；原始视频已保留'
                    : session.exportBurnDanmaku && !session.timelineConfirmed
                        ? '未能确认弹幕与视频的时间映射，原始文件与素材已保留'
                        : '导出失败，原始文件与素材已保留，可重试';
          }
        }
        await _save(session);
        notifyListeners();
      }
    } on Object {
      // Storage failures must not escape an unawaited queue worker. Keep every
      // source/material file and expose a retryable failure in memory.
      for (final session in _sessions) {
        if (session.status == RecordingStatus.exporting ||
            session.status == RecordingStatus.queued) {
          session.status = RecordingStatus.failed;
          session.error = '无法保存导出任务状态，请检查剩余存储空间';
        }
      }
      _queue.clear();
      notifyListeners();
    } finally {
      _workerRunning = false;
      if (_foreground && _queue.isNotEmpty) unawaited(_drain());
    }
  }

  Future<void> cancelExport(String id) async {
    final session = _find(id);
    _cancelled.add(id);
    _queue.remove(id);
    if (session.status == RecordingStatus.exporting) {
      await _backend.cancel();
    } else if (session.status == RecordingStatus.queued) {
      session.status = RecordingStatus.ready;
      await _save(session);
      notifyListeners();
    }
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (foreground) {
      unawaited(_drain());
    } else if (_workerRunning) {
      unawaited(_backend.cancel().catchError((Object _) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final mobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (!mobile) return;
    if (state == AppLifecycleState.resumed) {
      setForeground(true);
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      // Disable the export queue before stop schedules its automatic export.
      setForeground(false);
      unawaited(stop(reason: 'background').catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Deletes the entire session including raw video and final output.
  Future<void> deleteSession(String id) async {
    final session = _find(id);
    if (session == _active || session.status == RecordingStatus.exporting) {
      throw StateError('Task is busy');
    }
    _queue.remove(id);
    final directory = p.normalize(p.absolute(session.directory));
    if (_root == null || !p.isWithin(_root!, directory)) {
      throw StateError('Invalid recording directory');
    }
    await Directory(directory).delete(recursive: true);
    _sessions.remove(session);
    notifyListeners();
  }

  Future<void> _save(RecordingSession session) {
    final previous = _saves[session.id] ?? Future<void>.value();
    final next =
        previous.catchError((Object _) {}).then((_) => _write(session));
    _saves[session.id] = next;
    return next;
  }

  Future<void> _write(RecordingSession session) async {
    final target = File(p.join(session.directory, 'session.json'));
    final temporary = File('${target.path}.new');
    final previous = File('${target.path}.previous');
    await temporary.writeAsString(jsonEncode(session.toJson()), flush: true);
    if (await previous.exists()) await previous.delete();
    if (await target.exists()) await target.rename(previous.path);
    await temporary.rename(target.path);
  }
}
