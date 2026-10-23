import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

import 'recording_models.dart';

/// A serial, local-files-only FFmpeg pipeline. Arguments are passed as a list,
/// never interpolated into a shell command or sent to a network endpoint.
class FFmpegRecordingBackend implements RecordingBackend {
  static const _probeTimeout = Duration(seconds: 8);
  static const _executeTimeout = Duration(minutes: 5);
  int? _sessionId;
  bool _cancelRequested = false;

  void _stage(String name) {
    developer.log('stage=$name', name: 'simple_live.recording');
  }

  /// Renders a local preview with the same compositor used by exported frames.
  Future<Uint8List> renderOverlayPreview(RecordingOverlayFrame frame,
      {required int width,
      required int height,
      required String directory}) async {
    final sprites = <String, ui.Image>{};
    try {
      return await _paint(frame.toJson(), width, height, directory, sprites);
    } finally {
      for (final image in sprites.values) {
        image.dispose();
      }
    }
  }

  Future<void> _execute(List<String> arguments) async {
    _cancelRequested = false;
    final done = Completer<void>();
    final localArguments = <String>[];
    for (final argument in arguments) {
      if (argument == '-i') {
        localArguments.addAll(['-protocol_whitelist', 'file,pipe']);
      }
      localArguments.add(argument);
    }
    final session = await FFmpegKit.executeWithArgumentsAsync(localArguments,
        (session) async {
      final code = await session.getReturnCode();
      if (!done.isCompleted) {
        if (ReturnCode.isSuccess(code)) {
          done.complete();
        } else {
          done.completeError(StateError('Local FFmpeg operation failed'));
        }
      }
    });
    _sessionId = session.getSessionId();
    _stage('ffmpegStarted');
    if (_cancelRequested) await FFmpegKit.cancel(_sessionId);
    try {
      await done.future.timeout(_executeTimeout);
      _stage('ffmpegCompleted');
    } on TimeoutException {
      _cancelRequested = true;
      await FFmpegKit.cancel(_sessionId);
      _stage('ffmpegTimeout');
      throw StateError('FFmpeg 操作超时');
    } finally {
      _sessionId = null;
    }
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    final id = _sessionId;
    if (id != null) await FFmpegKit.cancel(id);
  }

  @override
  Future<RecordingMediaInfo> probe(String path) async {
    _stage('ffprobeStarted');
    final completed = Completer<FFprobeSession>();
    late final FFprobeSession session;
    session = await FFprobeKit.executeWithArgumentsAsync([
      '-protocol_whitelist',
      'file,pipe',
      '-v',
      'error',
      '-show_format',
      '-show_streams',
      '-of',
      'json',
      path,
    ], (value) {
      if (!completed.isCompleted) completed.complete(value);
    });
    FFprobeSession finished;
    try {
      finished = await completed.future.timeout(_probeTimeout);
    } on TimeoutException {
      await session.cancel();
      _stage('ffprobeTimeout');
      throw StateError('FFprobe 操作超时');
    }
    if (!ReturnCode.isSuccess(await finished.getReturnCode())) {
      throw StateError('Cannot inspect recording');
    }
    final json =
        jsonDecode(await finished.getOutput() ?? '{}') as Map<String, dynamic>;
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
    return RecordingMediaInfo(
        duration: Duration(microseconds: (seconds * 1e6).round()),
        width: (video['width'] as num?)?.toInt() ?? 0,
        height: (video['height'] as num?)?.toInt() ?? 0,
        videoCodec: video['codec_name'] as String? ?? '',
        audioCodec: audio?['codec_name'] as String?,
        frameRate: frameRate);
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
      ]);

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
      ]);

  @override
  Future<void> burn(
      RecordingSession session, String output, bool Function() cancelled,
      {void Function(double progress)? onProgress}) async {
    if (!session.timelineConfirmed || session.mediaStartMs == null) {
      throw StateError(
          'Recording first-packet timestamp has not been confirmed');
    }
    final info = await probe(session.rawPath);
    if (!info.valid || info.width.isOdd || info.height.isOdd) {
      throw StateError('Unsupported video geometry');
    }
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
    final sprites = <String, ui.Image>{};
    final chunks = <String>[];
    bool hasFrame = false;
    try {
      if (await frames.moveNext()) next = frames.current;
      const chunkMs = 2000;
      const overlayFps = 60;
      final capturedMs = session.captureDurationMs;
      final availableMs = info.duration.inMilliseconds - session.fileStartMs;
      final durationMs =
          capturedMs != null && capturedMs > 0 && capturedMs < availableMs
              ? capturedMs
              : availableMs;
      if (durationMs <= 0) throw StateError('No decoded video to export');
      for (var start = 0; start < durationMs; start += chunkMs) {
        if (cancelled()) throw StateError('Export cancelled');
        final remaining = durationMs - start;
        final length = remaining < chunkMs ? remaining : chunkMs;
        final count = (length * overlayFps / 1000).ceil();
        for (var index = 0; index < count; index++) {
          if (cancelled()) throw StateError('Export cancelled');
          final mediaMs =
              session.mediaStartMs! + start + index * 1000 / overlayFps;
          while (next != null && (next['positionMs'] as num) <= mediaMs) {
            current = next;
            hasFrame = true;
            next = await frames.moveNext() ? frames.current : null;
          }
          final png = await _paint(
              current, info.width, info.height, session.directory, sprites);
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
          '[0:v]setpts=PTS-STARTPTS[v];[v][1:v]overlay=0:0:shortest=1[out]',
          '-map',
          '[out]',
          '-an',
          '-r',
          '${info.frameRate.clamp(1, 60)}',
          '-t',
          '${length / 1000}',
          ..._encode,
          chunk
        ]);
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
      if (cancelled()) throw StateError('Export cancelled');
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
      ]);
    } finally {
      await frames.cancel();
      for (final image in sprites.values) {
        image.dispose();
      }
      // Only transient generated PNGs/chunks are removed; source assets persist.
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  Future<Uint8List> _paint(Map<String, dynamic>? frame, int width, int height,
      String directory, Map<String, ui.Image> sprites) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas
        .clipRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    if (frame != null) {
      final canvasWidth = (frame['canvasWidth'] as num).toDouble();
      final canvasHeight = (frame['canvasHeight'] as num).toDouble();
      if (canvasWidth <= 0 || canvasHeight <= 0) {
        throw StateError('Invalid viewport');
      }
      final videoWidth =
          (frame['videoWidth'] as num?)?.toDouble() ?? canvasWidth;
      final videoHeight =
          (frame['videoHeight'] as num?)?.toDouble() ?? canvasHeight;
      if (videoWidth <= 0 || videoHeight <= 0) {
        throw StateError('Invalid video mapping');
      }
      canvas.scale(width / videoWidth, height / videoHeight);
      canvas.translate(-((frame['videoLeft'] as num?)?.toDouble() ?? 0),
          -((frame['videoTop'] as num?)?.toDouble() ?? 0));
      canvas.clipRect(ui.Rect.fromLTWH(0, 0, canvasWidth, canvasHeight));
      final groupOpacity =
          ((frame['opacity'] as num?)?.toDouble() ?? 1).clamp(0.0, 1.0);
      canvas.saveLayer(ui.Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
          ui.Paint()..color = ui.Color.fromRGBO(255, 255, 255, groupOpacity));
      for (final raw in frame['items'] as List<dynamic>) {
        final item = raw as Map<String, dynamic>;
        final id = item['spriteId'] as String;
        if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
          throw StateError('Invalid sprite');
        }
        var image = sprites[id];
        if (image == null) {
          final bytes =
              await File(p.join(directory, 'sprites', '$id.png')).readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          try {
            image = (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }
          // Bound native image memory independently of recording length.
          if (sprites.length >= 64) {
            sprites.remove(sprites.keys.first)?.dispose();
          }
          sprites[id] = image;
        }
        canvas.save();
        final transform = item['transform'] as List<dynamic>?;
        final x = (item['x'] as num).toDouble();
        final y = (item['y'] as num).toDouble();
        var drawX = x, drawY = y;
        if (transform != null && transform.length == 16) {
          final ox = (item['transformOriginX'] as num?)?.toDouble() ?? 0;
          final oy = (item['transformOriginY'] as num?)?.toDouble() ?? 0;
          canvas.translate(x + ox, y + oy);
          canvas.transform(Float64List.fromList(
              transform.map((v) => (v as num).toDouble()).toList()));
          drawX = -ox;
          drawY = -oy;
        }
        final opacity =
            ((item['opacity'] as num?)?.toDouble() ?? 1).clamp(0.0, 1.0);
        canvas.drawImageRect(
            image,
            ui.Rect.fromLTWH(
                0, 0, image.width.toDouble(), image.height.toDouble()),
            ui.Rect.fromLTWH(drawX, drawY, (item['width'] as num).toDouble(),
                (item['height'] as num).toDouble()),
            ui.Paint()..color = ui.Color.fromRGBO(255, 255, 255, opacity));
        canvas.restore();
      }
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
    } finally {
      image.dispose();
    }
  }
}
