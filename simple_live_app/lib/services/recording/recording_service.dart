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
  static const _timelineTimeout = Duration(seconds: 12);
  RecordingService(
      {RecordingBackend? backend, RecordingBackend? captureBackend})
      : _backend = backend ?? FFmpegRecordingBackend(),
        _captureBackend =
            captureBackend ?? (backend ?? FFmpegRecordingBackend());
  static final RecordingService instance = RecordingService();
  final RecordingBackend _backend;
  final RecordingBackend _captureBackend;
  final List<RecordingSession> _sessions = [];
  final List<String> _queue = [];
  final Set<String> _cancelled = {};
  final Set<String> _leasedSessions = {};
  final Set<String> _mutatingSessions = {};
  final Map<String, Future<void>> _initializations = {};
  Future<void> _initializationTail = Future<void>.value();
  String? _root;
  RecordingSession? _active;
  RecordingSource? _source;
  RecordingSource? _pendingReleaseSource;
  Future<void> Function()? _beforeStop;
  IOSink? _frames;
  bool _transitioning = false, _workerRunning = false, _foreground = true;
  bool _shuttingDown = false;
  bool _scanningRoot = false;
  bool _observingLifecycle = false;
  int _foregroundGeneration = 0;
  Completer<void>? _workerFinished;
  Future<void>? _shutdownFuture;
  int _lastFrameMs = -1;
  int _frameCount = 0;
  int _spriteBytes = 0;
  int _pendingSpriteBytes = 0;
  final Set<String> _spriteIds = {};
  Object? _materialError;
  final Map<String, Future<void>> _saves = {};
  Future<void> _materialWrites = Future.value();
  Future<void> _captureOperations = Future.value();
  List<RecordingSession> get sessions => List.unmodifiable(_sessions);
  RecordingSession? get activeSession => _active;
  bool get isRecording => _active != null;
  bool get isScanningDirectory => _scanningRoot;

  /// Whether this service still owns source-side work for the player.
  /// Call [stop] and wait for success before disposing or replacing that player.
  bool ownsSource(RecordingSource source) =>
      identical(_source, source) || identical(_pendingReleaseSource, source);

  Future<void> initialize(String rootPath) {
    if (_shuttingDown) {
      return Future<void>.error(StateError('Recording service is shut down'));
    }
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    final root = p.normalize(p.absolute(rootPath));
    final inFlight = _initializations[root];
    if (inFlight != null) return inFlight;

    final task = _captureOperation(() => _initializeRoot(root));
    _initializations[root] = task;
    _initializationTail = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    unawaited(task.then<void>(
      (_) {
        _initializations.remove(root);
      },
      onError: (Object _, StackTrace __) {
        _initializations.remove(root);
      },
    ));
    return task;
  }

  Future<void> _initializeRoot(String root) async {
    if (_shuttingDown) throw StateError('Recording service is shut down');
    final busy = _active != null ||
        _workerRunning ||
        _transitioning ||
        _leasedSessions.isNotEmpty ||
        _mutatingSessions.isNotEmpty ||
        _pendingReleaseSource != null ||
        _queue.isNotEmpty;
    if (_root != root && busy) throw StateError('Recording is busy');
    if (_root == root && busy) return;

    _scanningRoot = true;
    notifyListeners();
    try {
      await Directory(root).create(recursive: true);
      final loaded = <RecordingSession>[];
      await for (final entry in Directory(root).list()) {
        if (entry is! Directory) continue;
        final manifest = File(p.join(entry.path, 'session.json'));
        final backup = File('${manifest.path}.previous');
        RecordingSession? session;
        Object? primaryError;
        if (await manifest.exists()) {
          try {
            session = RecordingSession.fromJson(
                jsonDecode(await manifest.readAsString())
                    as Map<String, dynamic>,
                entry.path);
          } on Object catch (error) {
            primaryError = error;
          }
        }
        if (session == null && await backup.exists()) {
          try {
            session = RecordingSession.fromJson(
                jsonDecode(await backup.readAsString()) as Map<String, dynamic>,
                entry.path);
            session.error = '主清单无法读取，已从备份恢复';
          } on Object {
            // Preserve other recordings even when both manifests are damaged.
          }
        }
        if (session == null) {
          if (primaryError != null) {
            developer.log(
                'Skipping unreadable recording manifest: $primaryError',
                name: 'simple_live.recording');
          }
          continue;
        }
        await _recoverOutputReplacement(session);
        if ({
          RecordingStatus.recording,
          RecordingStatus.exporting,
          RecordingStatus.queued
        }.contains(session.status)) {
          session.status = RecordingStatus.interrupted;
          session.error = '上次任务未正常结束，原始文件已保留，可重试导出';
          try {
            await _save(session);
          } on Object catch (error) {
            session.error = '上次任务未正常结束；清单暂时无法更新，原始文件已保留：$error';
          }
        }
        loaded.add(session);
      }
      loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _root = root;
      _sessions
        ..clear()
        ..addAll(loaded);
      notifyListeners();
    } finally {
      _scanningRoot = false;
      notifyListeners();
    }
  }

  Future<void> _recoverOutputReplacement(RecordingSession session) async {
    final output = File(p.join(session.directory, 'recording.mp4'));
    final previous = File('${output.path}.previous');
    if (await output.exists()) {
      if (await previous.exists()) {
        try {
          await previous.delete();
        } on Object {
          // A redundant backup is safer to retain if the file is locked.
        }
      }
      return;
    }
    if (!await previous.exists()) return;
    try {
      await previous.rename(output.path);
      session.outputPath = output.path;
    } on Object {
      // The service can still recover the raw recording if replacement fails.
    }
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
    if (_shuttingDown) throw StateError('Recording service is shut down');
    if (_root == null) throw StateError('Recording storage is not initialized');
    if (_pendingReleaseSource != null) {
      throw StateError('Recording source cleanup is still pending');
    }
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
      _source = request.source;
      await request.source.start(session.rawPath);
      _active = session;
      _beforeStop = request.beforeStop;
      _lastFrameMs = -1;
      _frameCount = 0;
      _spriteBytes = 0;
      _pendingSpriteBytes = 0;
      _spriteIds.clear();
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
      Object? releaseError;
      try {
        await _releaseSourceOwner(request.source);
      } on Object catch (error) {
        releaseError = error;
      }
      session.status = RecordingStatus.failed;
      session.error = releaseError == null
          ? '无法启动录制'
          : '录制启动失败且资源未能完全释放：$releaseError；原始文件与素材已保留';
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
    if (!_spriteIds.add(id)) {
      await _materialWrites;
      return;
    }
    if (_spriteBytes + _pendingSpriteBytes + png.length > 256 * 1024 * 1024) {
      _spriteIds.remove(id);
      throw StateError('Danmaku sprite storage limit reached');
    }
    _pendingSpriteBytes += png.length;
    final file = File(p.join(session.directory, 'sprites', '$id.png'));
    final write = _materialWrites.catchError((Object _) {}).then((_) async {
      if (!await file.exists()) {
        await file.writeAsBytes(png, flush: true);
        _spriteBytes += png.length;
      }
    });
    _materialWrites = write;
    try {
      await write;
    } on Object catch (error) {
      _materialError = error;
      session.captureFailed = true;
      _spriteIds.remove(id);
      rethrow;
    } finally {
      _pendingSpriteBytes -= png.length;
    }
  }

  void recordFrame(RecordingOverlayFrame frame,
      {String? sessionId, bool force = false}) {
    final session = _active;
    if (session == null || session.mode == RecordingMode.videoOnly) return;
    if (sessionId != null && session.id != sessionId) return;
    final ms = frame.position.inMilliseconds;
    if (ms < 0 || ms < _lastFrameMs) return;
    if (!_positiveFinite(frame.canvasWidth) ||
        !_positiveFinite(frame.canvasHeight) ||
        !_positiveFinite(frame.videoWidth ?? frame.canvasWidth) ||
        !_positiveFinite(frame.videoHeight ?? frame.canvasHeight) ||
        !frame.videoLeft.isFinite ||
        !frame.videoTop.isFinite ||
        !frame.opacity.isFinite ||
        frame.items.length > 500) {
      markCaptureFailure();
      return;
    }
    for (final item in frame.items) {
      if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(item.spriteId) ||
          ![
            item.x,
            item.y,
            item.width,
            item.height,
            item.opacity,
            item.transformOriginX,
            item.transformOriginY
          ].every((value) => value.isFinite) ||
          item.width <= 0 ||
          item.height <= 0 ||
          (item.transform != null &&
              (item.transform!.length != 16 ||
                  !item.transform!.every((value) => value.isFinite)))) {
        markCaptureFailure();
        return;
      }
    }
    // Bound material to 60 fps and approximately 12 hours. No unbounded in-memory
    // history: each accepted frame is streamed to the session's JSONL file.
    if (!force && _lastFrameMs >= 0 && ms - _lastFrameMs < 16) return;
    if (_frameCount >= 2592000) {
      markCaptureFailure();
      return;
    }
    _lastFrameMs = ms;
    _frameCount++;
    try {
      _frames?.writeln(jsonEncode(frame.toJson()));
    } on Object catch (error) {
      _materialError = error;
      session.captureFailed = true;
    }
  }

  bool _positiveFinite(double value) => value.isFinite && value > 0;

  void markCaptureFailure() {
    final session = _active;
    if (session == null || session.mode == RecordingMode.videoOnly) return;
    session.captureFailed = true;
    _materialError = StateError('Danmaku capture failed');
  }

  Future<void> stop({String reason = 'manual'}) => _captureOperation(() async {
        final pendingSource = _pendingReleaseSource;
        if (pendingSource != null) {
          await _releaseSourceOwner(pendingSource);
          notifyListeners();
          return;
        }
        await _stop(reason);
      });

  Future<void> _releaseSourceOwner(RecordingSource source) async {
    if (source is RecordingSourceLifetime) {
      try {
        await (source as RecordingSourceLifetime).release();
      } on Object {
        // Retain the source so callers can retry and player mutation stays
        // behind this ownership barrier.
        _pendingReleaseSource = source;
        _source = source;
        rethrow;
      }
    }
    if (identical(_pendingReleaseSource, source)) {
      _pendingReleaseSource = null;
    }
    if (identical(_source, source)) _source = null;
  }

  Future<RecordingMediaInfo> _probeValid(String path) async {
    Object? lastError;
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        final info = await _captureBackend.probe(path);
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

  Future<void> _stop(String reason, {bool autoExport = true}) async {
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
      final timelineFileStart = timeline?.fileStart.inMilliseconds ?? 0;
      final decodedFileStart = info.firstVideoFrameStart?.inMilliseconds ?? 0;
      session.fileStartMs = timelineFileStart > decodedFileStart
          ? timelineFileStart
          : decodedFileStart;
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
      Object? releaseError;
      StackTrace? releaseStack;
      final source = _source;
      if (source != null) {
        try {
          await _releaseSourceOwner(source);
        } on Object catch (error, stackTrace) {
          releaseError = error;
          releaseStack = stackTrace;
          session.status = RecordingStatus.failed;
          session.error = '录制资源未能完全释放：$error；原始文件与弹幕素材已保留';
        }
      }
      _active = null;
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
      if (releaseError != null) {
        Error.throwWithStackTrace(
            StateError(
                'Recording source cleanup is still pending: $releaseError'),
            releaseStack!);
      }
    }
    if (session.status == RecordingStatus.ready &&
        autoExport &&
        !_shuttingDown) {
      await exportSession(session.id);
    }
  }

  RecordingSession _find(String id) => _sessions.firstWhere((s) => s.id == id);

  Future<T> withSessionFiles<T>(
      String id, Future<T> Function(RecordingSession session) action) async {
    if (_shuttingDown) throw StateError('Recording service is shut down');
    if (_scanningRoot) throw StateError('Recording directory scan is busy');
    final session = _find(id);
    if (session == _active ||
        session.status == RecordingStatus.queued ||
        session.status == RecordingStatus.exporting ||
        _mutatingSessions.contains(id) ||
        _leasedSessions.contains(id)) {
      throw StateError('Recording files are busy');
    }
    _leasedSessions.add(id);
    try {
      return await action(session);
    } finally {
      _leasedSessions.remove(id);
    }
  }

  Future<void> exportSession(String id, {bool burnDanmaku = false}) async {
    if (_shuttingDown) throw StateError('Recording service is shut down');
    if (_scanningRoot) throw StateError('Recording directory scan is busy');
    final session = _find(id);
    if (_leasedSessions.contains(id)) {
      throw StateError('Recording files are in use');
    }
    if (session == _active ||
        session.status == RecordingStatus.exporting ||
        _queue.contains(id)) {
      return;
    }
    final rawExists = await File(session.rawPath).exists();
    if (_scanningRoot || !_sessions.contains(session)) {
      throw StateError('Recording directory changed during export request');
    }
    if (!rawExists) {
      session.status = RecordingStatus.failed;
      session.error = '原始录制文件不存在';
      await _save(session);
      notifyListeners();
      return;
    }
    if (_scanningRoot) throw StateError('Recording directory scan is busy');
    if (_leasedSessions.contains(id) || _mutatingSessions.contains(id)) {
      throw StateError('Recording files are in use');
    }
    if (_shuttingDown) throw StateError('Recording service is shut down');
    if (_scanningRoot) throw StateError('Recording directory scan is busy');
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
    if (_workerRunning || !_foreground || _shuttingDown) return;
    _workerRunning = true;
    final workerFinished = Completer<void>();
    _workerFinished = workerFinished;
    try {
      while (_queue.isNotEmpty && _foreground && !_shuttingDown) {
        final id = _queue.removeAt(0);
        final session = _find(id);
        final foregroundGeneration = _foregroundGeneration;
        session.status = RecordingStatus.exporting;
        await _save(session);
        notifyListeners();
        final temporary = p.join(session.directory, 'export.partial.mp4');
        try {
          _ensureExportCanContinue(session, foregroundGeneration);
          final info = await _backend.probe(session.rawPath);
          _ensureExportCanContinue(session, foregroundGeneration);
          if (!info.valid) throw StateError('Invalid media');
          session.durationMs = info.duration.inMilliseconds;
          final decodedStartMs = info.firstVideoFrameStart?.inMilliseconds ?? 0;
          if (decodedStartMs > session.fileStartMs) {
            session.fileStartMs = decodedStartMs;
            await _save(session);
          }
          final capturedMs = session.captureDurationMs;
          final availableMs =
              info.duration.inMilliseconds - session.fileStartMs;
          if (availableMs <= 0) {
            throw StateError('No decodable video remains after trimming');
          }
          final targetDuration = Duration(
              milliseconds: capturedMs != null &&
                      capturedMs > 0 &&
                      capturedMs <= availableMs
                  ? capturedMs
                  : availableMs);
          var retainedRaw = false;
          if (session.exportBurnDanmaku) {
            if (session.captureFailed) {
              throw StateError('Danmaku capture failed');
            }
            await _backend.burn(
                session,
                temporary,
                () =>
                    _cancelled.contains(session.id) ||
                    _shuttingDown ||
                    !_foreground ||
                    foregroundGeneration != _foregroundGeneration,
                onProgress: (value) {
              session.exportProgress = value.clamp(0, 1);
              notifyListeners();
            });
          } else if (info.mp4Compatible) {
            try {
              _ensureExportCanContinue(session, foregroundGeneration);
              await _backend.remux(session.rawPath, temporary,
                  duration: targetDuration,
                  start: Duration(milliseconds: session.fileStartMs));
            } on Object {
              if (_isExportInterrupted(session, foregroundGeneration)) rethrow;
              retainedRaw = true;
            }
          } else {
            retainedRaw = true;
          }
          _ensureExportCanContinue(session, foregroundGeneration);
          if (retainedRaw) {
            session.outputPath = session.rawPath;
            session.status = RecordingStatus.complete;
            session.exportProgress = 1;
            session.error = 'MP4无法无损封装，已保留原始MKV（含录制缓存尾部）';
            developer.log('stage=exported mode=raw',
                name: 'simple_live.recording');
          } else {
            final result = await _backend.probe(temporary);
            _ensureExportCanContinue(session, foregroundGeneration);
            if (!result.valid ||
                !result.mp4Compatible ||
                (session.exportBurnDanmaku && result.videoCodec != 'h264') ||
                (info.audioCodec != null && result.audioCodec != 'aac') ||
                !_trimDurationMatches(result.duration, targetDuration, info) ||
                result.width != info.width ||
                result.height != info.height) {
              throw StateError('Export validation failed');
            }
            final output = File(p.join(session.directory, 'recording.mp4'));
            await _replaceOutput(File(temporary), output,
                () => _ensureExportCanContinue(session, foregroundGeneration));
            session.outputPath = output.path;
            session.status = RecordingStatus.complete;
            session.durationMs = result.duration.inMilliseconds;
            session.exportProgress = 1;
            session.error = session.mode != RecordingMode.videoOnly &&
                    !session.timelineConfirmed
                ? '已保存视频与弹幕素材；未能确认媒体时间映射，暂无法合成弹幕'
                : null;
            developer.log('stage=exported mode=mp4',
                name: 'simple_live.recording');
          }
        } on Object catch (error) {
          if (_shuttingDown) {
            session.status = RecordingStatus.ready;
            session.error = '应用关闭前已停止导出，原始文件与素材已保留';
          } else if (foregroundGeneration != _foregroundGeneration &&
              !_cancelled.contains(session.id)) {
            session.status = RecordingStatus.queued;
            if (!_queue.contains(session.id)) _queue.insert(0, session.id);
          } else {
            session.status = RecordingStatus.failed;
            session.error = _cancelled.contains(session.id)
                ? '已取消导出，原始文件与素材已保留'
                : session.captureFailed && session.exportBurnDanmaku
                    ? '弹幕素材捕获失败，无法合成；原始视频已保留'
                    : session.exportBurnDanmaku && !session.timelineConfirmed
                        ? '未能确认弹幕与视频的时间映射，原始文件与素材已保留'
                        : '导出失败，原始文件与素材已保留，可重试：$error';
          }
        } finally {
          await _deleteTemporary(File(temporary));
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
          session.status =
              _shuttingDown ? RecordingStatus.ready : RecordingStatus.failed;
          session.error =
              _shuttingDown ? '应用关闭前已停止导出，原始文件与素材已保留' : '无法保存导出任务状态，请检查剩余存储空间';
        }
      }
      _queue.clear();
      notifyListeners();
    } finally {
      _workerRunning = false;
      _workerFinished = null;
      if (!workerFinished.isCompleted) workerFinished.complete();
      if (_foreground && !_shuttingDown && _queue.isNotEmpty) {
        unawaited(_drain());
      }
    }
  }

  bool _isExportInterrupted(RecordingSession session, int generation) =>
      _shuttingDown ||
      _cancelled.contains(session.id) ||
      !_foreground ||
      generation != _foregroundGeneration;

  void _ensureExportCanContinue(RecordingSession session, int generation) {
    if (_isExportInterrupted(session, generation)) {
      throw StateError('Export interrupted');
    }
  }

  bool _trimDurationMatches(
      Duration actual, Duration expected, RecordingMediaInfo source) {
    final frameMs = source.frameRate.isFinite && source.frameRate > 0
        ? (1000 / source.frameRate).ceil()
        : 34;
    final toleranceMs = frameMs * 2 > 250 ? frameMs * 2 : 250;
    return (actual - expected).inMilliseconds.abs() <= toleranceMs;
  }

  Future<void> _replaceOutput(
      File temporary, File output, void Function() ensureCanContinue) async {
    final previous = File('${output.path}.previous');
    if (await previous.exists()) {
      if (await output.exists()) {
        await previous.delete();
      } else {
        await previous.rename(output.path);
      }
    }
    var movedExistingOutput = false;
    if (await output.exists()) {
      await output.rename(previous.path);
      movedExistingOutput = true;
    }
    try {
      ensureCanContinue();
      await temporary.rename(output.path);
      ensureCanContinue();
    } on Object {
      if (await output.exists()) {
        try {
          await output.delete();
        } on Object {
          // A locked new output is still safer than deleting the old backup.
        }
      }
      if (movedExistingOutput &&
          await previous.exists() &&
          !await output.exists()) {
        try {
          await previous.rename(output.path);
        } on Object {
          // Keep the previous path available if a locked file prevents restore.
        }
      }
      rethrow;
    }
    if (await previous.exists()) {
      try {
        await previous.delete();
      } on Object {
        // A successful new output is safe; leave a redundant backup if locked.
      }
    }
  }

  Future<void> _deleteTemporary(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // A failed cleanup must not hide the preserved source recording.
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
    if (_shuttingDown || _foreground == foreground) return;
    if (!foreground) _foregroundGeneration++;
    _foreground = foreground;
    if (foreground) {
      unawaited(_drain());
    } else if (_workerRunning) {
      unawaited(_backend.cancel().catchError((Object _) {}));
    }
  }

  Future<void> shutdown() {
    final existing = _shutdownFuture;
    if (existing != null) return existing;

    final completion = Completer<void>();
    _shutdownFuture = completion.future;
    _shuttingDown = true;
    _foreground = false;
    _foregroundGeneration++;
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    unawaited(_finishShutdown().then<void>(
      (_) => completion.complete(),
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_shutdownFuture, completion.future)) {
          _shutdownFuture = null;
        }
        completion.completeError(error, stackTrace);
      },
    ));
    return completion.future;
  }

  Future<void> _finishShutdown() async {
    await _initializationTail;
    final worker = _workerFinished?.future;
    if (_workerRunning) {
      try {
        await _backend.cancel();
      } on Object {
        // The worker completion below is still required before releasing files.
      }
      if (worker != null) await worker;
    }

    await _captureOperations.catchError((Object _) {});
    await _captureOperation(() async {
      if (_active != null) {
        await _stop('shutdown', autoExport: false);
      } else if (_pendingReleaseSource != null) {
        await _releaseSourceOwner(_pendingReleaseSource!);
      }
    });
    await _captureBackend.cancel();

    _queue.clear();
    for (final session in _sessions) {
      if (session.status != RecordingStatus.queued &&
          session.status != RecordingStatus.exporting) {
        continue;
      }
      session.status = RecordingStatus.ready;
      session.error = '应用关闭前已停止导出，原始文件与素材已保留';
      try {
        await _save(session);
      } on Object {
        // On restart, the persisted queued/exporting state is recovered as
        // interrupted and can still be exported from the raw media.
      }
    }
    await Future.wait(
        _saves.values.map((save) => save.catchError((Object _) {})));
    notifyListeners();
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
    if (_scanningRoot) throw StateError('Recording directory scan is busy');
    final session = _find(id);
    if (session == _active ||
        session.status == RecordingStatus.exporting ||
        session.status == RecordingStatus.queued ||
        _leasedSessions.contains(id) ||
        _mutatingSessions.contains(id)) {
      throw StateError('Task is busy');
    }
    if (_shuttingDown) throw StateError('Recording service is shut down');
    _queue.remove(id);
    final directory = p.normalize(p.absolute(session.directory));
    if (_root == null || !p.isWithin(_root!, directory)) {
      throw StateError('Invalid recording directory');
    }
    _mutatingSessions.add(id);
    try {
      await Directory(directory).delete(recursive: true);
      _sessions.remove(session);
      notifyListeners();
    } finally {
      _mutatingSessions.remove(id);
    }
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
    final damaged = File('${target.path}.damaged');
    await temporary.writeAsString(jsonEncode(session.toJson()), flush: true);
    var movedTargetToPrevious = false;
    var movedDamagedTarget = false;
    if (await target.exists()) {
      if (await _isValidManifest(target, session.directory)) {
        if (await previous.exists()) await previous.delete();
        await target.rename(previous.path);
        movedTargetToPrevious = true;
      } else {
        if (await damaged.exists()) await damaged.delete();
        await target.rename(damaged.path);
        movedDamagedTarget = true;
      }
    }
    try {
      await temporary.rename(target.path);
    } on Object {
      if (await target.exists()) await target.delete();
      if (!await target.exists() &&
          movedTargetToPrevious &&
          await previous.exists()) {
        await previous.rename(target.path);
      } else if (!await target.exists() &&
          movedDamagedTarget &&
          await damaged.exists()) {
        await damaged.rename(target.path);
      }
      rethrow;
    }
    if (movedDamagedTarget && await damaged.exists()) {
      try {
        await damaged.delete();
      } on Object {
        // Keep the old damaged file if cleanup is blocked by the filesystem.
      }
    }
  }

  Future<bool> _isValidManifest(File file, String directory) async {
    try {
      RecordingSession.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
          directory);
      return true;
    } on Object {
      return false;
    }
  }
}
