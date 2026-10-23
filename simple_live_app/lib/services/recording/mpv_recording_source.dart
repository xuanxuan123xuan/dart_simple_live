import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import 'recording_models.dart';

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
  final warning = severe || normalizedLevel == 'warn' || normalizedLevel == 'warning';
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
/// another live URL. A second player is used only for the finalized local file.
class MpvRecordingSource implements RecordingSource {
  MpvRecordingSource(this.player,
      {this.onError, this.captureTimeline = true});
  final Player player;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final bool captureTimeline;
  static const _label = 'simplelive_recording';
  static const _nativeOperationTimeout = Duration(seconds: 3);
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

  NativePlayer get _native => player.platform as NativePlayer;

  void _stage(String name) {
    developer.log(
      'stage=$name elapsedMs=${_stageClock.elapsedMilliseconds}',
      name: 'simple_live.recording',
    );
  }

  Future<void> _nativeCommand(List<String> command, String stage) async {
    try {
      await _native.command(command).timeout(_nativeOperationTimeout);
    } on TimeoutException {
      throw StateError('录制原生操作超时：$stage');
    }
  }

  void _startFingerprintSampling(int generation) {
    if (!captureTimeline) return;
    // Fingerprints are useful for the optional danmaku timeline, but querying
    // vf-metadata synchronously is expensive. Start only after recording has
    // become ready and sample at a bounded rate so Windows remains responsive.
    _fingerprintTimer =
        Timer.periodic(const Duration(milliseconds: 250), (_) {
      _sampling = _sampling.then((_) async {
        if (generation != _generation || !_filterAttached) return;
        final frames = parseRecordingFingerprints(
          await _native.getProperty('vf-metadata/$_label'),
        );
        _sourceFrames.addAll(
            frames.where((frame) =>
                _sourcePositions.add(frame.position.inMicroseconds)));
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
    if (_attached || _state != MpvRecordingState.idle) {
      throw StateError('录制已经开始');
    }
    if (await File(path).exists()) throw StateError('录制目标文件已存在');
    _state = MpvRecordingState.starting;
    _stageClock
      ..reset()
      ..start();
    _stage('requested');
    _lastError = null;
    _errorReported = false;
    final generation = ++_generation;
    _path = path;
    _sourceFrames.clear();
    _sourcePositions.clear();
    _sourceFirstPosition = null;
    // A small, bounded fingerprint history is sufficient to establish the
    // packet rebase offset without guessing at the demuxer cache tail.
    try {
      if (captureTimeline) {
        await _nativeCommand(['vf', 'add', _filter], '添加指纹滤镜');
        _filterAttached = true;
        _stage('filterAttached');
      }
      _logs = player.stream.log.listen((log) {
        if ((_state != MpvRecordingState.starting &&
                _state != MpvRecordingState.recording) ||
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
      try {
        await stop();
      } on Object {/* Preserve the original start error. */}
      rethrow;
    }
  }

  Future<void> _removeFilter() async {
    if (!_filterAttached) return;
    _filterAttached = false;
    await _nativeCommand(['vf', 'remove', '@$_label'], '移除指纹滤镜');
  }

  @override
  Future<void> stop() async {
    if (_state == MpvRecordingState.idle) return;
    _state = MpvRecordingState.stopping;
    _stage('stopping');
    _generation++;
    _fingerprintTimer?.cancel();
    await _logs?.cancel();
    _logs = null;
    try {
      await _sampling.timeout(const Duration(milliseconds: 500));
    } on TimeoutException {
      // A blocked metadata read must never keep the stop path pending.
    } on Object {
      // Sampling failures only affect optional timeline confirmation.
    }
    try {
      if (_attached) {
        await _nativeCommand(['set', 'stream-record', ''], '停止写入录制');
      }
      await _waitForFileFlush();
      _stage('flushed');
    } finally {
      _attached = false;
      try {
        await _removeFilter();
      } on Object {
        // A failed filter cleanup must not leave the source stuck in stopping.
      }
      _state = MpvRecordingState.idle;
    }
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
  Future<RecordingTimeline?> timeline() async {
    final path = _path;
    if (path == null || _sourceFrames.length < 3) {
      return null;
    }
    final local = Player(
        configuration: const PlayerConfiguration(
      title: 'Recording timestamp verification',
      logLevel: MPVLogLevel.error,
    ));
    final frames = <RecordingFingerprint>[];
    final positions = <int>{};
    try {
      final native = local.platform as NativePlayer;
      await native.setProperty('vo', 'null');
      await native.setProperty('ao', 'null');
      // media_kit defaults to vid=no until a VideoController attaches. The
      // local verifier is headless, but must still decode video fingerprints.
      await native.setProperty('vid', 'auto');
      await native.setProperty('hwdec', 'no');
      await native.setProperty('cache-on-disk', 'no');
      await native.setProperty('vf', _filter);
      await local.open(Media(path), play: false);
      Duration? firstFrame;
      for (var attempt = 0; attempt < 800; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        frames.addAll(parseRecordingFingerprints(
          await native.getProperty('vf-metadata/$_label'),
        ).where((frame) => positions.add(frame.position.inMicroseconds)));
        if (firstFrame == null && frames.isNotEmpty) {
          firstFrame = frames.first.position;
          await native.setProperty('speed', '4');
          await local.play();
        }
        final result = matchRecordingTimeline(_sourceFrames, frames);
        if (result != null && firstFrame != null) {
          return RecordingTimeline(
              mediaStart: result.mediaStart + firstFrame,
              confirmed: true,
              fileStart: firstFrame);
        }
        if (frames.length >= 2048 || local.state.completed) break;
      }
      return null;
    } finally {
      await local.dispose();
    }
  }
}
