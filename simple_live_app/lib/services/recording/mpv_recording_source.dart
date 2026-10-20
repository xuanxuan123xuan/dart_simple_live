import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:media_kit/media_kit.dart';

import 'recording_models.dart';

/// Sample at paint time instead of using the throttled Dart position stream.
/// The short C API call reads only a double, never a live URL or credentials.
Duration readMpvRecordingPosition(Player player) {
  final native = player.platform;
  if (native is! NativePlayer || native.disposed || native.ctx.address == 0) {
    return player.state.position;
  }
  final name = 'time-pos'.toNativeUtf8();
  final value = calloc<Double>();
  try {
    final result = native.mpv.mpv_get_property(
      native.ctx,
      name.cast(),
      5,
      value.cast(),
    );
    final seconds = value.value;
    return result >= 0 && seconds.isFinite
        ? Duration(microseconds: (seconds * 1000000).round())
        : player.state.position;
  } finally {
    calloc.free(name);
    calloc.free(value);
  }
}

/// One decoded frame fingerprint paired with its media PTS, never wall time.
class RecordingFingerprint {
  const RecordingFingerprint(this.position, this.fingerprint);
  final Duration position;
  final String fingerprint;
}

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

/// Writes packets from the existing native player. It never resolves or opens
/// another live URL. A second player is used only for the finalized local file.
class MpvRecordingSource implements RecordingSource {
  MpvRecordingSource(this.player);
  final Player player;
  static const _label = 'simplelive_recording';
  // mpv_get_property_string may query a node twice while formatting JSON.
  // Clearing on query would consume it before the formatted result is read.
  static const _filter = '@$_label:fingerprint=clear-on-query=no';
  final List<RecordingFingerprint> _sourceFrames = [];
  final Set<int> _sourcePositions = {};
  Timer? _fingerprintTimer;
  Future<void> _sampling = Future.value();
  String? _path;
  bool _attached = false;
  bool _filterAttached = false;
  int _generation = 0;
  Duration? _sourceFirstPosition;

  NativePlayer get _native => player.platform as NativePlayer;

  @override
  Future<void> start(String path) async {
    if (_attached) throw StateError('录制已经开始');
    if (await File(path).exists()) throw StateError('录制目标文件已存在');
    final generation = ++_generation;
    _path = path;
    // A small, bounded fingerprint history is sufficient to establish the
    // packet rebase offset without guessing at the demuxer cache tail.
    await _native.command(['vf', 'add', _filter]);
    _filterAttached = true;
    _fingerprintTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _sampling = _sampling.then((_) async {
        if (generation != _generation || !_filterAttached) return;
        final frames = parseRecordingFingerprints(
          await _native.getProperty('vf-metadata/$_label'),
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
    _attached = true;
    await _native.setProperty('stream-record', path);
    // Setting the option can succeed even when the bundled libavformat has no
    // muxers. Confirm file creation instead of displaying false success. MKV
    // buffers its first cluster, so size can stay zero until stop flushes it;
    // track/size/duration validation belongs to finalization.
    for (var attempt = 0; attempt < 60; attempt++) {
      if (generation != _generation) throw StateError('录制已取消');
      final file = File(path);
      if (await file.exists()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('播放器未能写入录制文件，请检查录制库支持和直播连接');
  }

  Future<void> _removeFilter() async {
    if (!_filterAttached) return;
    _filterAttached = false;
    await _native.command(['vf', 'remove', '@$_label']);
  }

  @override
  Future<void> stop() async {
    _generation++;
    _fingerprintTimer?.cancel();
    await _sampling;
    try {
      if (_attached) await _native.setProperty('stream-record', '');
    } finally {
      _attached = false;
      await _removeFilter();
    }
  }

  @override
  Future<Duration> mediaPosition() async {
    final seconds = double.tryParse(await _native.getProperty('time-pos'));
    if (seconds == null || !seconds.isFinite) {
      throw StateError('播放器没有可用的媒体时间');
    }
    return Duration(microseconds: (seconds * 1000000).round());
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
