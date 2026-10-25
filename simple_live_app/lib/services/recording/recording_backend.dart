import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

import 'recording_models.dart';
import 'recording_overlay_interpolation.dart';

class RecordingNativeResult {
  const RecordingNativeResult({required this.success, this.output = ''});

  final bool success;
  final String output;
}

abstract interface class RecordingNativeCommand {
  Future<void> cancel();
}

abstract interface class RecordingNativeCommandRunner {
  Future<RecordingNativeCommand> runFfmpeg(
      List<String> arguments, void Function(RecordingNativeResult) onComplete);
  Future<RecordingNativeCommand> runFfprobe(
      List<String> arguments, void Function(RecordingNativeResult) onComplete);
}

class _PluginNativeCommand implements RecordingNativeCommand {
  const _PluginNativeCommand(this._cancel);

  final Future<void> Function() _cancel;

  @override
  Future<void> cancel() => _cancel();
}

class _PluginNativeCommandRunner implements RecordingNativeCommandRunner {
  const _PluginNativeCommandRunner();

  @override
  Future<RecordingNativeCommand> runFfmpeg(List<String> arguments,
      void Function(RecordingNativeResult) onComplete) async {
    final session =
        await FFmpegKit.executeWithArgumentsAsync(arguments, (session) async {
      try {
        final code = await session.getReturnCode();
        onComplete(RecordingNativeResult(
          success: ReturnCode.isSuccess(code),
          output: await session.getOutput() ?? '',
        ));
      } on Object {
        onComplete(const RecordingNativeResult(success: false));
      }
    });
    return _PluginNativeCommand(() => FFmpegKit.cancel(session.getSessionId()));
  }

  @override
  Future<RecordingNativeCommand> runFfprobe(List<String> arguments,
      void Function(RecordingNativeResult) onComplete) async {
    final session =
        await FFprobeKit.executeWithArgumentsAsync(arguments, (session) async {
      try {
        final code = await session.getReturnCode();
        onComplete(RecordingNativeResult(
          success: ReturnCode.isSuccess(code),
          output: await session.getOutput() ?? '',
        ));
      } on Object {
        onComplete(const RecordingNativeResult(success: false));
      }
    });
    return _PluginNativeCommand(session.cancel);
  }
}

class _ActiveNativeOperation {
  final Completer<RecordingNativeResult> result =
      Completer<RecordingNativeResult>();
  final Completer<void> settled = Completer<void>();
  RecordingNativeCommand? command;
  Future<void>? _cancelFuture;
  bool cancelRequested = false;

  void complete(RecordingNativeResult value) {
    if (!result.isCompleted) result.complete(value);
    if (!settled.isCompleted) settled.complete();
  }

  void failToStart(Object error) {
    if (!result.isCompleted) {
      result.complete(RecordingNativeResult(success: false, output: '$error'));
    }
    if (!settled.isCompleted) settled.complete();
  }

  Future<void> cancelAndWait() async {
    cancelRequested = true;
    final command = this.command;
    Object? cancelError;
    if (command != null && !settled.isCompleted) {
      try {
        await (_cancelFuture ??= command.cancel());
      } on Object catch (error) {
        cancelError = error;
      }
    }
    await settled.future;
    if (cancelError != null) {
      Error.throwWithStackTrace(cancelError, StackTrace.current);
    }
  }
}

class _SpriteImageCache {
  static const _maxImages = 64;
  static const _maxBytes = 128 * 1024 * 1024;
  static const _maxImagePixels = 16 * 1024 * 1024;
  static const _maxPngBytes = 4 * 1024 * 1024;

  final Map<String, ui.Image> _images = {};
  final Map<String, int> _imageBytes = {};
  int _bytes = 0;

  Future<ui.Image> load(String id, File file) async {
    final cached = _images[id];
    if (cached != null) return cached;

    final bytes = await file.readAsBytes();
    if (bytes.length > _maxPngBytes) {
      throw StateError('Danmaku sprite exceeds the encoded image budget');
    }
    final dimensions = _validatePngSize(bytes);
    final estimatedBytes = dimensions.$1 * dimensions.$2 * 4;
    if (estimatedBytes > _maxBytes) {
      throw StateError('Danmaku sprite exceeds the decoded image budget');
    }
    _evictToFit(estimatedBytes);
    final codec = await ui.instantiateImageCodec(bytes);
    ui.Image image;
    try {
      image = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
    final decodedBytes = image.width * image.height * 4;
    if (image.width <= 0 ||
        image.height <= 0 ||
        image.width * image.height > _maxImagePixels ||
        decodedBytes > _maxBytes) {
      image.dispose();
      throw StateError('Danmaku sprite exceeds the decoded image budget');
    }
    if (_bytes + decodedBytes > _maxBytes || _images.length >= _maxImages) {
      _evictToFit(decodedBytes);
    }
    _images[id] = image;
    _imageBytes[id] = decodedBytes;
    _bytes += decodedBytes;
    return image;
  }

  void _evictToFit(int incomingBytes) {
    while (_images.isNotEmpty &&
        (_images.length >= _maxImages || _bytes + incomingBytes > _maxBytes)) {
      final evictedId = _images.keys.first;
      _images.remove(evictedId)!.dispose();
      _bytes -= _imageBytes.remove(evictedId)!;
    }
  }

  (int, int) _validatePngSize(Uint8List bytes) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 24) {
      throw StateError('Invalid danmaku sprite PNG');
    }
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) {
        throw StateError('Invalid danmaku sprite PNG');
      }
    }
    if (bytes[12] != 73 ||
        bytes[13] != 72 ||
        bytes[14] != 68 ||
        bytes[15] != 82 ||
        ByteData.sublistView(bytes, 8, 12).getUint32(0, Endian.big) != 13) {
      throw StateError('Invalid danmaku sprite PNG header');
    }
    final header = ByteData.sublistView(bytes, 16, 24);
    final width = header.getUint32(0, Endian.big);
    final height = header.getUint32(4, Endian.big);
    if (width == 0 ||
        height == 0 ||
        width > _maxImagePixels ||
        height > _maxImagePixels ||
        width * height > _maxImagePixels) {
      throw StateError('Danmaku sprite exceeds the decoded image budget');
    }
    return (width, height);
  }

  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _imageBytes.clear();
    _bytes = 0;
  }
}

/// A serial, local-files-only FFmpeg pipeline. Arguments are passed as a list,
/// never interpolated into a shell command or sent to a network endpoint.
class FFmpegRecordingBackend implements RecordingBackend {
  FFmpegRecordingBackend(
      {RecordingNativeCommandRunner? nativeRunner,
      Duration probeTimeout = const Duration(seconds: 8),
      Duration executeTimeout = const Duration(minutes: 5)})
      : _nativeRunner = nativeRunner ?? const _PluginNativeCommandRunner(),
        _probeTimeout = probeTimeout,
        _executeTimeout = executeTimeout;

  final RecordingNativeCommandRunner _nativeRunner;
  final Duration _probeTimeout;
  final Duration _executeTimeout;
  _ActiveNativeOperation? _active;
  Future<void> _nativeQueue = Future<void>.value();
  int _cancelGeneration = 0;

  void _stage(String name) {
    developer.log('stage=$name', name: 'simple_live.recording');
  }

  bool _isCancelled(int generation) => generation != _cancelGeneration;

  void _checkNotCancelled(int generation, [bool Function()? cancelled]) {
    if (_isCancelled(generation) || (cancelled?.call() ?? false)) {
      throw StateError('Export cancelled');
    }
  }

  Future<RecordingNativeResult> _runNative(
      Future<RecordingNativeCommand> Function(
              void Function(RecordingNativeResult) onComplete)
          start,
      Duration timeout,
      int generation,
      String operation) {
    final previous = _nativeQueue;
    final turn = Completer<void>();
    _nativeQueue = turn.future;
    return _runNativeQueued(
        previous, turn, start, timeout, generation, operation);
  }

  Future<RecordingNativeResult> _runNativeQueued(
      Future<void> previous,
      Completer<void> turn,
      Future<RecordingNativeCommand> Function(
              void Function(RecordingNativeResult) onComplete)
          start,
      Duration timeout,
      int generation,
      String operation) async {
    try {
      await previous;
      _checkNotCancelled(generation);
      return await _runNativeNow(start, timeout, generation, operation);
    } finally {
      if (!turn.isCompleted) turn.complete();
    }
  }

  Future<RecordingNativeResult> _runNativeNow(
      Future<RecordingNativeCommand> Function(
              void Function(RecordingNativeResult) onComplete)
          start,
      Duration timeout,
      int generation,
      String operation) async {
    _checkNotCancelled(generation);
    if (_active != null) throw StateError('Native recording operation busy');
    final active = _ActiveNativeOperation();
    _active = active;
    var timedOut = false;
    try {
      try {
        active.command = await start(active.complete);
      } on Object catch (error) {
        active.failToStart(error);
        rethrow;
      }
      if (active.cancelRequested || _isCancelled(generation)) {
        await active.cancelAndWait();
      }
      RecordingNativeResult result;
      try {
        result = await active.result.future.timeout(timeout);
      } on TimeoutException {
        timedOut = true;
        await active.cancelAndWait();
        result = await active.result.future;
      }
      if (timedOut) {
        throw TimeoutException('$operation timed out; native work was stopped');
      }
      if (_isCancelled(generation)) throw StateError('$operation cancelled');
      if (!result.success) {
        throw StateError('$operation failed');
      }
      return result;
    } finally {
      if (!active.settled.isCompleted) {
        // A synchronous start failure is finalized above. Native work is never
        // detached from this backend before its completion callback arrives.
        await active.settled.future;
      }
      if (identical(_active, active)) _active = null;
    }
  }

  /// Renders a local preview with the same compositor used by exported frames.
  Future<Uint8List> renderOverlayPreview(RecordingOverlayFrame frame,
      {required int width,
      required int height,
      required String directory}) async {
    final sprites = _SpriteImageCache();
    try {
      return await _paint(frame.toJson(), width, height, directory, sprites);
    } finally {
      sprites.dispose();
    }
  }

  Future<void> _execute(List<String> arguments, int generation) async {
    final localArguments = <String>[];
    for (final argument in arguments) {
      if (argument == '-i') {
        localArguments.addAll(['-protocol_whitelist', 'file,pipe']);
      }
      localArguments.add(argument);
    }
    _stage('ffmpegStarted');
    await _runNative(
      (onComplete) => _nativeRunner.runFfmpeg(localArguments, onComplete),
      _executeTimeout,
      generation,
      'FFmpeg operation',
    );
    _stage('ffmpegCompleted');
  }

  @override
  Future<void> cancel() async {
    _cancelGeneration++;
    final queueAtCancel = _nativeQueue;
    Object? cancelError;
    StackTrace? cancelStack;
    try {
      await _active?.cancelAndWait();
    } on Object catch (error, stackTrace) {
      cancelError = error;
      cancelStack = stackTrace;
    }
    await queueAtCancel;
    if (cancelError != null) {
      Error.throwWithStackTrace(cancelError, cancelStack!);
    }
  }

  @override
  Future<RecordingMediaInfo> probe(String path) =>
      _probe(path, _cancelGeneration);

  Future<RecordingMediaInfo> _probe(String path, int generation) async {
    _stage('ffprobeStarted');
    final result = await _runNative(
        (onComplete) => _nativeRunner.runFfprobe([
              '-protocol_whitelist',
              'file,pipe',
              '-v',
              'error',
              '-show_format',
              '-show_streams',
              '-show_frames',
              '-skip_frame',
              'nokey',
              '-read_intervals',
              '%+30',
              '-show_entries',
              'format=duration:stream=codec_type,codec_name,width,height,avg_frame_rate:frame=media_type,best_effort_timestamp_time',
              '-of',
              'json',
              path,
            ], onComplete),
        _probeTimeout,
        generation,
        'FFprobe operation');
    final json = jsonDecode(result.output) as Map<String, dynamic>;
    _stage('ffprobeCompleted');
    final streams =
        (json['streams'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final video = streams.firstWhere((s) => s['codec_type'] == 'video');
    final audio = streams.where((s) => s['codec_type'] == 'audio').firstOrNull;
    final format = json['format'] as Map<String, dynamic>? ?? {};
    final seconds =
        double.tryParse('${format['duration'] ?? video['duration']}') ?? 0;
    final rate = '${video['avg_frame_rate'] ?? '30/1'}'.split('/');
    final numerator = double.tryParse(rate.first) ?? 30;
    final denominator = rate.length > 1 ? double.tryParse(rate[1]) ?? 1 : 1;
    final frameRate =
        denominator > 0 && numerator > 0 ? numerator / denominator : 30.0;
    Duration? firstVideoFrameStart;
    for (final rawFrame in (json['frames'] as List<dynamic>? ?? const [])) {
      final frame = rawFrame as Map<String, dynamic>;
      if (frame['media_type'] != 'video') continue;
      final frameSeconds =
          double.tryParse('${frame['best_effort_timestamp_time']}');
      if (frameSeconds != null && frameSeconds.isFinite) {
        firstVideoFrameStart = Duration(
            microseconds:
                (frameSeconds * Duration.microsecondsPerSecond).round());
        break;
      }
    }
    if (firstVideoFrameStart == null) {
      throw StateError('Recording has no decodable video keyframe');
    }
    return RecordingMediaInfo(
        duration: Duration(
            microseconds: seconds.isFinite
                ? (seconds * Duration.microsecondsPerSecond).round()
                : 0),
        width: (video['width'] as num?)?.toInt() ?? 0,
        height: (video['height'] as num?)?.toInt() ?? 0,
        videoCodec: video['codec_name'] as String? ?? '',
        audioCodec: audio?['codec_name'] as String?,
        frameRate: frameRate,
        firstVideoFrameStart: firstVideoFrameStart);
  }

  List<String> get _encode => [
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '20',
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-b:a',
        '192k'
      ];

  @override
  Future<void> remux(String input, String output,
          {Duration? duration, Duration start = Duration.zero}) =>
      _execute([
        '-y',
        '-seek_timestamp',
        '1',
        '-ss',
        '${start.inMicroseconds / 1e6}',
        '-i',
        input,
        '-map',
        '0:v:0',
        '-map',
        '0:a:0?',
        '-c',
        'copy',
        if (duration != null) ...['-t', '${duration.inMicroseconds / 1e6}'],
        '-movflags',
        '+faststart',
        output,
      ], _cancelGeneration);

  @override
  Future<void> transcode(String input, String output) => _execute([
        '-y',
        '-i',
        input,
        '-map',
        '0:v:0',
        '-map',
        '0:a:0?',
        ..._encode,
        '-movflags',
        '+faststart',
        output,
      ], _cancelGeneration);

  @override
  Future<void> burn(
      RecordingSession session, String output, bool Function() cancelled,
      {void Function(double progress)? onProgress}) async {
    if (!session.timelineConfirmed || session.mediaStartMs == null) {
      throw StateError(
          'Recording first-packet timestamp has not been confirmed');
    }
    final generation = _cancelGeneration;
    _checkNotCancelled(generation, cancelled);
    final info = await _probe(session.rawPath, generation);
    if (!info.valid || info.width.isOdd || info.height.isOdd) {
      throw StateError('Unsupported video geometry');
    }
    final firstFrameMs = info.firstVideoFrameStart?.inMilliseconds ?? 0;
    session.fileStartMs = session.fileStartMs < 0
        ? firstFrameMs
        : session.fileStartMs > firstFrameMs
            ? session.fileStartMs
            : firstFrameMs;
    final materials = File(p.join(session.directory, 'frames.jsonl'));
    if (!await materials.exists()) throw StateError('Missing danmaku material');
    final directory = Directory(p.join(session.directory, 'export-work'));
    await directory.create(recursive: true);
    final frames = StreamIterator(materials
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>));
    Map<String, dynamic>? current;
    Map<String, dynamic>? next;
    final sprites = _SpriteImageCache();
    final chunks = <String>[];
    bool hasFrame = false;
    try {
      _checkNotCancelled(generation, cancelled);
      if (await frames.moveNext()) next = frames.current;
      const chunkMs = 2000;
      const overlayFps = 60;
      final capturedMs = session.captureDurationMs;
      final availableMs = info.duration.inMilliseconds - session.fileStartMs;
      if (availableMs <= 0) {
        throw StateError('No decodable video remains after trimming');
      }
      final durationMs =
          capturedMs != null && capturedMs > 0 && capturedMs < availableMs
              ? capturedMs
              : availableMs;
      if (durationMs <= 0) throw StateError('No decoded video to export');
      for (var start = 0; start < durationMs; start += chunkMs) {
        _checkNotCancelled(generation, cancelled);
        final remaining = durationMs - start;
        final length = remaining < chunkMs ? remaining : chunkMs;
        final count = (length * overlayFps / 1000).ceil();
        for (var index = 0; index < count; index++) {
          _checkNotCancelled(generation, cancelled);
          final mediaMs =
              session.mediaStartMs! + start + index * 1000 / overlayFps;
          while (next != null && (next['positionMs'] as num) <= mediaMs) {
            current = next;
            hasFrame = true;
            next = await frames.moveNext() ? frames.current : null;
          }
          final sampled =
              interpolateRecordingOverlayFrame(current, next, mediaMs);
          final png = await _paint(
              sampled, info.width, info.height, session.directory, sprites);
          await File(p.join(directory.path,
                  'overlay${index.toString().padLeft(4, '0')}.png'))
              .writeAsBytes(png);
        }
        final chunk = p.join(directory.path, 'chunk${chunks.length}.mp4');
        await _execute([
          '-y',
          '-ss',
          '${(session.fileStartMs + start) / 1000}',
          '-seek_timestamp',
          '1',
          '-i',
          session.rawPath,
          '-framerate',
          '$overlayFps',
          '-i',
          p.join(directory.path, 'overlay%04d.png'),
          '-filter_complex',
          '[0:v]setpts=PTS-STARTPTS,fps=$overlayFps[v];[v][1:v]overlay=0:0:shortest=1[out]',
          '-map',
          '[out]',
          '-an',
          '-r',
          '$overlayFps',
          '-t',
          '${length / 1000}',
          ..._encode,
          chunk
        ], generation);
        chunks.add(chunk);
        onProgress?.call((start + length) / durationMs * .95);
        // Keep at most one two-second PNG segment on disk.
        for (var index = 0; index < count; index++) {
          await File(p.join(directory.path,
                  'overlay${index.toString().padLeft(4, '0')}.png'))
              .delete();
        }
      }
      if (!hasFrame) throw StateError('No synchronized danmaku frames');
      _checkNotCancelled(generation, cancelled);
      final list = File(p.join(directory.path, 'concat.txt'));
      // Chunk names are generated locally, without user strings or apostrophes.
      await list.writeAsString(
          chunks.map((path) => "file '${p.basename(path)}'").join('\n'));
      await _execute([
        '-y',
        '-f',
        'concat',
        '-safe',
        '1',
        '-i',
        list.path,
        '-ss',
        '${session.fileStartMs / 1000}',
        '-seek_timestamp',
        '1',
        '-i',
        session.rawPath,
        '-map',
        '0:v:0',
        '-map',
        '1:a:0?',
        '-c:v',
        'copy',
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        '-t',
        '${durationMs / 1000}',
        '-movflags',
        '+faststart',
        output
      ], generation);
    } finally {
      try {
        await frames.cancel();
      } finally {
        sprites.dispose();
        // Only transient generated PNGs/chunks are removed; source assets persist.
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    }
  }

  Future<Uint8List> _paint(Map<String, dynamic>? frame, int width, int height,
      String directory, _SpriteImageCache sprites) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    ui.Picture? picture;
    ui.Image? image;
    try {
      canvas.clipRect(
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
      if (frame != null) {
        final canvasWidth = (frame['canvasWidth'] as num).toDouble();
        final canvasHeight = (frame['canvasHeight'] as num).toDouble();
        if (!_positiveFinite(canvasWidth) || !_positiveFinite(canvasHeight)) {
          throw StateError('Invalid viewport');
        }
        final videoWidth =
            (frame['videoWidth'] as num?)?.toDouble() ?? canvasWidth;
        final videoHeight =
            (frame['videoHeight'] as num?)?.toDouble() ?? canvasHeight;
        if (!_positiveFinite(videoWidth) || !_positiveFinite(videoHeight)) {
          throw StateError('Invalid video mapping');
        }
        final videoLeft = (frame['videoLeft'] as num?)?.toDouble() ?? 0;
        final videoTop = (frame['videoTop'] as num?)?.toDouble() ?? 0;
        final groupOpacity = (frame['opacity'] as num?)?.toDouble() ?? 1;
        if (!videoLeft.isFinite ||
            !videoTop.isFinite ||
            !groupOpacity.isFinite) {
          throw StateError('Invalid viewport transform');
        }
        canvas.scale(width / videoWidth, height / videoHeight);
        canvas.translate(-videoLeft, -videoTop);
        canvas.clipRect(ui.Rect.fromLTWH(0, 0, canvasWidth, canvasHeight));
        canvas.saveLayer(
            ui.Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
            ui.Paint()
              ..color = ui.Color.fromRGBO(
                  255, 255, 255, groupOpacity.clamp(0.0, 1.0)));
        try {
          for (final raw in frame['items'] as List<dynamic>) {
            final item = raw as Map<String, dynamic>;
            final id = item['spriteId'] as String;
            if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
              throw StateError('Invalid sprite');
            }
            final sprite = await sprites.load(
                id, File(p.join(directory, 'sprites', '$id.png')));
            final x = (item['x'] as num).toDouble();
            final y = (item['y'] as num).toDouble();
            final itemWidth = (item['width'] as num).toDouble();
            final itemHeight = (item['height'] as num).toDouble();
            final originX = (item['transformOriginX'] as num?)?.toDouble() ?? 0;
            final originY = (item['transformOriginY'] as num?)?.toDouble() ?? 0;
            final opacity = (item['opacity'] as num?)?.toDouble() ?? 1;
            if (![x, y, itemWidth, itemHeight, originX, originY, opacity]
                    .every((value) => value.isFinite) ||
                itemWidth <= 0 ||
                itemHeight <= 0) {
              throw StateError('Invalid sprite geometry');
            }
            canvas.save();
            try {
              var drawX = x, drawY = y;
              final transform = item['transform'] as List<dynamic>?;
              if (transform != null) {
                if (transform.length != 16) {
                  throw StateError('Invalid sprite transform');
                }
                final values = transform.map((value) {
                  final number = (value as num).toDouble();
                  if (!number.isFinite) throw StateError('Invalid transform');
                  return number;
                }).toList();
                canvas.translate(x + originX, y + originY);
                canvas.transform(Float64List.fromList(values));
                drawX = -originX;
                drawY = -originY;
              }
              canvas.drawImageRect(
                  sprite,
                  ui.Rect.fromLTWH(
                      0, 0, sprite.width.toDouble(), sprite.height.toDouble()),
                  ui.Rect.fromLTWH(drawX, drawY, itemWidth, itemHeight),
                  ui.Paint()
                    ..color = ui.Color.fromRGBO(
                        255, 255, 255, opacity.clamp(0.0, 1.0)));
            } finally {
              canvas.restore();
            }
          }
        } finally {
          canvas.restore();
        }
      }
      picture = recorder.endRecording();
      image = await picture.toImage(width, height);
      return (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
    } finally {
      image?.dispose();
      if (picture == null) {
        try {
          picture = recorder.endRecording();
        } on Object {
          // The recorder may already have failed while finalizing its picture.
        }
      }
      picture?.dispose();
    }
  }

  bool _positiveFinite(double value) => value.isFinite && value > 0;
}
