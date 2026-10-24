import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import 'recording_models.dart';
import 'recording_mpv_bridge.dart';

/// Sample at paint time instead of using the throttled Dart position stream.
/// The position in [PlayerState] is maintained by media_kit's event loop. Do
/// not call the synchronous libmpv FFI from a Flutter paint callback: on
/// Windows that call can wait for demuxer or network work and freeze the UI.
Duration readMpvRecordingPosition(Player player) {
  return player.state.position;
}

/// One decoded frame fingerprint paired with its media PTS, never wall time.
class RecordingFingerprint {
  const RecordingFingerprint(this.position, this.fingerprint);
  final Duration position;
  final String fingerprint;
}

enum MpvRecordingState { idle, starting, recording, stopping, failed }

/// mpv rebases recorded packets. Recover that offset by matching several unique
/// decoded frames from the already-playing stream against the local recording.
/// Repeated/static images are deliberately insufficient evidence of an offset.
RecordingTimeline? matchRecordingTimeline(
  Iterable<RecordingFingerprint> source,
  Iterable<RecordingFingerprint> recorded,
) {
  Map<String, Set<int>> index(Iterable<RecordingFingerprint> frames) {
    final result = <String, Set<int>>{};
    for (final frame in frames) {
      result
          .putIfAbsent(frame.fingerprint, () => <int>{})
          .add(frame.position.inMicroseconds);
    }
    return result;
  }

  final sourceIndex = index(source);
  final recordedIndex = index(recorded);
  final offsets = <int>[];
  for (final entry in recordedIndex.entries) {
    final original = sourceIndex[entry.key];
    if (entry.value.length == 1 && original?.length == 1) {
      offsets.add(original!.single - entry.value.single);
    }
  }
  if (offsets.length < 3) return null;
  offsets.sort();
  final median = offsets[offsets.length ~/ 2];
  // Independent unique frames must agree to within one ordinary video frame.
  if (offsets.any((offset) => (offset - median).abs() > 35000)) return null;
  return RecordingTimeline(
    mediaStart: Duration(microseconds: median),
    confirmed: true,
  );
}

List<RecordingFingerprint> parseRecordingFingerprints(String metadata) {
  try {
    final map = jsonDecode(metadata) as Map<String, dynamic>;
    final frames = <RecordingFingerprint>[];
    for (var i = 0; i < 10; i++) {
      final pts = double.tryParse('${map['fp$i.pts']}');
      final hex = map['fp$i.hex'];
      if (pts != null &&
          pts.isFinite &&
          hex is String &&
          RegExp(r'^[0-9a-f]{512}$').hasMatch(hex)) {
        frames.add(RecordingFingerprint(
          Duration(microseconds: (pts * 1000000).round()),
          hex,
        ));
      }
    }
    return frames;
  } on Object {
    return const [];
  }
}

bool isMpvRecordingFailureLog({
  required String prefix,
  required String text,
  required String level,
}) {
  final value = text.toLowerCase();
  final normalizedLevel = level.toLowerCase();
  final severe = normalizedLevel == 'error' || normalizedLevel == 'fatal';
  final warning =
      severe || normalizedLevel == 'warn' || normalizedLevel == 'warning';
  final recorderPrefix = prefix.toLowerCase().contains('recorder');
  final failureWord = value.contains('error') ||
      value.contains('fail') ||
      value.contains('cannot') ||
      value.contains('unable') ||
      value.contains('invalid');
  return (recorderPrefix && warning) ||
      (value.contains('stream-record') && warning && failureWord) ||
      (value.contains('disabling recording') && severe);
}

/// Writes packets from the existing native player. It never resolves or opens
/// another live URL. A headless worker verifies only the finalized local file.
class MpvRecordingSource implements RecordingSource, RecordingSourceLifetime {
  MpvRecordingSource(this.player,
      {this.onError,
      this.captureTimeline = true,
      RecordingMpvBridge? bridge,
      Duration nativeOperationTimeout = const Duration(seconds: 3),
      this.protectNativeMutation})
      : _bridge = bridge,
        _nativeOperationTimeout = nativeOperationTimeout;
  final Player player;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final bool captureTimeline;
  final Future<void> Function(Future<void> Function())? protectNativeMutation;
  RecordingMpvBridge? _bridge;
  Future<RecordingMpvBridge>? _bridgeCreation;
  Future<void>? _stopFuture;
  Future<void>? _startFuture;
  final Set<Future<void>> _nativeMutations = {};
  Future<void>? _releaseFuture;
  Future<RecordingTimeline?>? _timelineFuture;
  bool _timelineCancelled = false;
  bool _released = false;
  bool _bridgeCreationFailed = false;

  Future<RecordingMpvBridge> get _transport async {
    try {
      return _bridge ??=
          await (_bridgeCreation ??= IsolateRecordingMpvBridge.create(player));
    } on RecordingMpvInitializationError {
      // Only the worker's explicit cleanup acknowledgement proves that no
      // partial client is left behind. A fatal isolate error retains ownership.
      _bridgeCreationFailed = true;
      rethrow;
    }
  }

  static const _label = 'simplelive_recording';
  final Duration _nativeOperationTimeout;
  // mpv_get_property_string may query a node twice while formatting JSON.
  // Clearing on query would consume it before the formatted result is read.
  static const _filter = '@$_label:fingerprint=clear-on-query=no';
  final List<RecordingFingerprint> _sourceFrames = [];
  final Set<int> _sourcePositions = {};
  Timer? _fingerprintTimer;
  StreamSubscription<PlayerLog>? _logs;
  Future<void> _sampling = Future.value();
  String? _path;
  bool _attached = false;
  bool _filterAttached = false;
  int _generation = 0;
  Duration? _sourceFirstPosition;
  final Stopwatch _stageClock = Stopwatch();
  MpvRecordingState _state = MpvRecordingState.idle;
  Object? _lastError;
  bool _errorReported = false;

  MpvRecordingState get state => _state;

  void _stage(String name) {
    developer.log(
      'stage=$name elapsedMs=${_stageClock.elapsedMilliseconds}',
      name: 'simple_live.recording',
    );
  }

  Future<void> _nativeCommand(List<String> command, String stage) async {
    Future<void> operation() async => (await _transport).command(command);
    // Keep the quiet window alive until the actual reply, even if the caller
    // times out. A timeout is uncertainty, never proof of native cancellation.
    final mutation = protectNativeMutation?.call(operation) ?? operation();
    _nativeMutations.add(mutation);
    unawaited(mutation.then<void>((_) {
      _nativeMutations.remove(mutation);
    }, onError: (Object _, StackTrace __) {
      _nativeMutations.remove(mutation);
    }));
    try {
      await mutation.timeout(_nativeOperationTimeout);
    } on TimeoutException {
      throw TimeoutException('录制原生操作超时：$stage', _nativeOperationTimeout);
    }
  }

  Future<void> _drainMutations() async {
    while (_nativeMutations.isNotEmpty) {
      await Future.wait(_nativeMutations
          .map((future) =>
              future.then<void>((_) {}, onError: (Object _, StackTrace __) {}))
          .toList());
    }
  }

  Future<String> _fingerprints(RecordingMpvBridge bridge) async {
    try {
      return await bridge
          .getProperty('vf-metadata/$_label')
          .timeout(_nativeOperationTimeout);
    } on RecordingMpvError catch (error) {
      // loadfile acceptance precedes the first decoded frame. This specific
      // native response means retry later, rather than a failed query/command.
      if (error.code == RecordingMpvError.propertyUnavailable) return '';
      rethrow;
    }
  }

  void _startFingerprintSampling(int generation) {
    if (!captureTimeline) return;
    // Fingerprints are useful for the optional danmaku timeline, but querying
    // vf-metadata synchronously is expensive. Start only after recording has
    // become ready and sample at a bounded rate so Windows remains responsive.
    _fingerprintTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _sampling = _sampling.then((_) async {
        if (generation != _generation || !_filterAttached) return;
        final frames = parseRecordingFingerprints(
          await _fingerprints(await _transport),
        );
        _sourceFrames.addAll(frames.where(
            (frame) => _sourcePositions.add(frame.position.inMicroseconds)));
        if (frames.isNotEmpty) _sourceFirstPosition ??= frames.first.position;
        if (_sourceFrames.length >= 2048 ||
            (frames.isNotEmpty &&
                _sourceFirstPosition != null &&
                frames.last.position - _sourceFirstPosition! >
                    const Duration(seconds: 35))) {
          _fingerprintTimer?.cancel();
          await _removeFilter();
        }
      }).catchError((Object _) {
        _fingerprintTimer?.cancel();
      });
    });
  }

  @override
  Future<void> start(String path) async {
    if (_startFuture != null ||
        _released ||
        _releaseFuture != null ||
        _attached ||
        _state != MpvRecordingState.idle) {
      throw StateError('录制正在开始或尚未关闭');
    }
    final operation = _start(path);
    _startFuture = operation;
    try {
      await operation;
    } on Object {
      _startFuture = null;
      try {
        await stop();
      } on Object {/* Retain uncertain ownership for release. */}
      _state = MpvRecordingState.failed;
      rethrow;
    } finally {
      _startFuture = null;
    }
  }

  Future<void> _start(String path) async {
    if (_released ||
        _releaseFuture != null ||
        _attached ||
        _state != MpvRecordingState.idle) {
      throw StateError('录制已经开始');
    }
    _state = MpvRecordingState.starting;
    final generation = ++_generation;
    if (await File(path).exists()) throw StateError('录制目标文件已存在');
    if (_released || _releaseFuture != null || generation != _generation) {
      throw StateError('录制已关闭');
    }
    _stageClock
      ..reset()
      ..start();
    _stage('requested');
    _lastError = null;
    _errorReported = false;
    _path = path;
    _sourceFrames.clear();
    _sourcePositions.clear();
    _sourceFirstPosition = null;
    // A small, bounded fingerprint history is sufficient to establish the
    // packet rebase offset without guessing at the demuxer cache tail.
    try {
      if (captureTimeline) {
        _filterAttached = true;
        try {
          await _nativeCommand(['vf', 'add', _filter], '添加指纹滤镜');
        } on RecordingMpvError {
          _filterAttached = false;
          rethrow;
        }
        if (generation != _generation) throw StateError('录制已取消');
        _stage('filterAttached');
      }
      _logs = player.stream.log.listen((log) {
        if ((_state != MpvRecordingState.starting &&
                _state != MpvRecordingState.recording &&
                _state != MpvRecordingState.stopping) ||
            !isMpvRecordingFailureLog(
              prefix: log.prefix,
              text: log.text,
              level: log.level,
            )) {
          return;
        }
        final error = StateError('录制器错误：${log.text}');
        _lastError = error;
        if (!_errorReported) {
          _errorReported = true;
          onError?.call(error, StackTrace.current);
        }
      });
      _attached = true;
      await _nativeCommand(['set', 'stream-record', path], '开始写入录制');
      if (generation != _generation) throw StateError('录制已取消');
      _stage('recordingAttached');
      // Setting the option can succeed even when the bundled libavformat has no
      // muxers. Confirm file creation instead of displaying false success. MKV
      // buffers its first cluster, so size can stay zero until stop flushes it;
      // track/size/duration validation belongs to finalization.
      for (var attempt = 0; attempt < 60; attempt++) {
        if (generation != _generation) throw StateError('录制已取消');
        final error = _lastError;
        if (error != null) throw error;
        final file = File(path);
        if (await file.exists()) {
          _state = MpvRecordingState.recording;
          _stage('fileCreated');
          _startFingerprintSampling(generation);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw StateError('播放器未能写入录制文件，请检查录制库支持和直播连接');
    } on Object catch (error, stackTrace) {
      _state = MpvRecordingState.failed;
      if (!_errorReported) onError?.call(error, stackTrace);
      rethrow;
    }
  }

  Future<void> _removeFilter() async {
    if (!_filterAttached) return;
    try {
      await _nativeCommand(['vf', 'remove', '@$_label'], '移除指纹滤镜');
    } on RecordingMpvError {
      // A previous timed-out remove may already have succeeded. Verify its
      // absence through the asynchronous client before releasing ownership.
      final filters = await (await _transport)
          .getProperty('vf')
          .timeout(_nativeOperationTimeout);
      if (filters.contains(_label)) rethrow;
    }
    _filterAttached = false;
  }

  @override
  Future<void> stop() => _stopFuture ??= _stop().whenComplete(() {
        _stopFuture = null;
      });

  Future<void> _stop() async {
    if (_state == MpvRecordingState.idle && !_attached && !_filterAttached) {
      return;
    }
    _state = MpvRecordingState.stopping;
    _stage('stopping');
    _generation++;
    _fingerprintTimer?.cancel();
    try {
      try {
        await _startFuture?.timeout(_nativeOperationTimeout);
      } on TimeoutException {
        rethrow;
      } on Object {
        // A rejected start still needs compensating native cleanup.
      }
      // Drain late attach/query replies before compensating. The bounded caller
      // may fail, but the client and ownership stay alive for release/retry.
      await _drainMutations().timeout(_nativeOperationTimeout);
      if (_bridgeCreationFailed) {
        _attached = false;
        _filterAttached = false;
      }
      final bridge =
          _bridgeCreationFailed ? null : _bridge ?? await _bridgeCreation;
      await bridge?.drain().timeout(_nativeOperationTimeout);
      await _sampling;
      if (_attached) {
        await _nativeCommand(['set', 'stream-record', ''], '停止写入录制');
        _attached = false;
      }
      await _removeFilter();
      await _logs?.cancel();
      _logs = null;
      await _waitForFileFlush();
      _stage('flushed');
      final error = _lastError;
      if (error != null) throw error;
      _state = MpvRecordingState.idle;
    } on Object {
      _state = MpvRecordingState.failed;
      rethrow;
    }
  }

  /// Unbounded ownership barrier. Native completion cannot safely be replaced
  /// with a timer: the caller must retain the player until this future settles.
  @override
  Future<void> release() => _releaseFuture ??=
          _release().onError((Object error, StackTrace stackTrace) {
        _releaseFuture = null;
        _state = MpvRecordingState.failed;
        Error.throwWithStackTrace(error, stackTrace);
      });

  Future<void> _release() async {
    _timelineCancelled = true;
    _fingerprintTimer?.cancel();
    try {
      await _timelineFuture;
    } on Object {
      // The verifier's finally still drains and destroys its worker-owned core.
    }
    try {
      await _startFuture;
    } on Object {
      // The start caller handles its error; this barrier handles its resources.
    }
    await _drainMutations();
    final bridge =
        _bridgeCreationFailed ? null : _bridge ?? await _bridgeCreation;
    await bridge?.drain();
    try {
      await stop();
    } on Object {
      // A recording failure may be reported after successful detach. It does
      // not prevent releasing a fully drained client; uncertain detach does.
      if (_attached || _filterAttached) {
        rethrow;
      }
    }
    await _logs?.cancel();
    _logs = null;
    await bridge?.close();
    _released = true;
  }

  Future<void> _waitForFileFlush() async {
    final path = _path;
    if (path == null) return;
    var previous = -1;
    var stable = 0;
    for (var attempt = 0; attempt < 20; attempt++) {
      final file = File(path);
      if (await file.exists()) {
        final length = await file.length();
        if (length == previous) {
          stable++;
          if (stable >= 3) return;
        } else {
          previous = length;
          stable = 0;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  Future<Duration> mediaPosition() async {
    return player.state.position;
  }

  @override
  Future<RecordingTimeline?> timeline() {
    if (_released || _releaseFuture != null) return Future.value(null);
    return _timelineFuture ??= _verifyTimeline();
  }

  Future<RecordingTimeline?> _verifyTimeline() async {
    final path = _path;
    if (path == null || _sourceFrames.length < 3 || _timelineCancelled) {
      return null;
    }
    RecordingMpvBridge? bridge;
    final frames = <RecordingFingerprint>[];
    final positions = <int>{};
    try {
      bridge = await IsolateRecordingMpvBridge.createVerifier();
      Future<void> command(List<String> value) =>
          bridge!.command(value).timeout(_nativeOperationTimeout);
      for (final entry in {
        'vo': 'null',
        'ao': 'null',
        'vid': 'auto',
        'hwdec': 'no',
        'cache-on-disk': 'no',
        'vf': _filter,
        'pause': 'yes',
      }.entries) {
        if (_timelineCancelled) return null;
        await command(['set', entry.key, entry.value]);
      }
      if (_timelineCancelled) return null;
      await command(['loadfile', path, 'replace']);
      Duration? firstFrame;
      for (var attempt = 0; attempt < 800 && !_timelineCancelled; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (_timelineCancelled) break;
        frames.addAll(parseRecordingFingerprints(
          await _fingerprints(bridge),
        ).where((frame) => positions.add(frame.position.inMicroseconds)));
        if (firstFrame == null && frames.isNotEmpty) {
          firstFrame = frames.first.position;
          await command(['set', 'speed', '4']);
          await command(['set', 'pause', 'no']);
        }
        final result = matchRecordingTimeline(_sourceFrames, frames);
        if (result != null && firstFrame != null) {
          return RecordingTimeline(
              mediaStart: result.mediaStart + firstFrame,
              confirmed: true,
              fileStart: firstFrame);
        }
        if (frames.length >= 2048) break;
      }
      return null;
    } finally {
      // A timed-out request still owns its native resources. Drain it and
      // destroy the verifier core before the source releases its ownership.
      await bridge?.close();
    }
  }
}
