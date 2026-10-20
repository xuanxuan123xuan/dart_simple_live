import 'dart:typed_data';

enum RecordingMode { videoOnly, videoWithDanmaku, burnDanmaku }

enum RecordingStatus {
  recording,
  interrupted,
  ready,
  queued,
  exporting,
  complete,
  failed
}

typedef RecordingState = RecordingStatus;

/// The source records the already-open player stream; it must not open a URL.
abstract interface class RecordingSource {
  Future<void> start(String path);
  Future<void> stop();

  /// Absolute player media time. Never derive solely from a wall-clock timer.
  Future<Duration> mediaPosition();
  Future<RecordingTimeline?> timeline();
}

class RecordingTimeline {
  const RecordingTimeline(
      {required this.mediaStart,
      required this.confirmed,
      this.fileStart = Duration.zero});
  final Duration mediaStart;
  final bool confirmed;

  /// Absolute timestamp of the first decoded frame retained in the raw file.
  final Duration fileStart;
}

class RecordingStartRequest {
  const RecordingStartRequest(
      {required this.roomId,
      required this.roomTitle,
      required this.platform,
      required this.mode,
      required this.source,
      this.beforeStop});
  final String roomId;
  final String roomTitle;
  final String platform;
  final RecordingMode mode;
  final RecordingSource source;
  final Future<void> Function()? beforeStop;
}

class RecordingSession {
  RecordingSession(
      {required this.id,
      required this.directory,
      required this.roomId,
      required this.roomTitle,
      required this.platform,
      required this.mode,
      required this.createdAt,
      this.status = RecordingStatus.recording,
      this.durationMs = 0,
      this.error,
      this.outputPath,
      this.stopReason,
      this.mediaStartMs,
      this.timelineConfirmed = false,
      this.captureDurationMs,
      this.fileStartMs = 0,
      this.exportBurnDanmaku = false,
      this.captureFailed = false,
      this.exportProgress = 0});
  final String id;
  final String directory;
  final String roomId;
  final String roomTitle;
  final String platform;
  final RecordingMode mode;
  final DateTime createdAt;
  RecordingStatus status;
  int durationMs;
  String? error;
  String? outputPath;
  String? stopReason;
  int? mediaStartMs;
  bool timelineConfirmed;
  int? captureDurationMs;
  int fileStartMs;
  bool exportBurnDanmaku;
  bool captureFailed;
  double exportProgress;
  String get rawPath => '$directory/raw.mkv';
  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'roomId': roomId,
        'roomTitle': roomTitle,
        'platform': platform,
        'mode': mode.name,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'durationMs': durationMs,
        'error': error,
        'outputPath': outputPath,
        'stopReason': stopReason,
        'mediaStartMs': mediaStartMs,
        'timelineConfirmed': timelineConfirmed,
        'captureDurationMs': captureDurationMs,
        'fileStartMs': fileStartMs,
        'exportBurnDanmaku': exportBurnDanmaku,
        'captureFailed': captureFailed,
        'exportProgress': exportProgress,
      };
  factory RecordingSession.fromJson(
          Map<String, dynamic> json, String directory) =>
      RecordingSession(
          id: json['id'] as String,
          directory: directory,
          roomId: json['roomId'] as String,
          roomTitle: json['roomTitle'] as String,
          platform: json['platform'] as String,
          mode: RecordingMode.values.byName(json['mode'] as String),
          createdAt: DateTime.parse(json['createdAt'] as String),
          status: RecordingStatus.values.byName(json['status'] as String),
          durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
          error: json['error'] as String?,
          outputPath: json['outputPath'] as String?,
          stopReason: json['stopReason'] as String?,
          mediaStartMs: (json['mediaStartMs'] as num?)?.toInt(),
          timelineConfirmed: json['timelineConfirmed'] == true,
          captureDurationMs: (json['captureDurationMs'] as num?)?.toInt(),
          fileStartMs: (json['fileStartMs'] as num?)?.toInt() ?? 0,
          exportBurnDanmaku: json['exportBurnDanmaku'] == true,
          captureFailed: json['captureFailed'] == true,
          exportProgress: (json['exportProgress'] as num?)?.toDouble() ?? 0);
}

class RecordingOverlayItem {
  const RecordingOverlayItem(
      {required this.spriteId,
      required this.x,
      required this.y,
      required this.width,
      required this.height,
      this.opacity = 1,
      this.transform,
      this.transformOriginX = 0,
      this.transformOriginY = 0});
  final String spriteId;
  final double x, y, width, height, opacity;
  final List<double>? transform;
  final double transformOriginX, transformOriginY;
  Map<String, dynamic> toJson() => {
        'spriteId': spriteId,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'opacity': opacity,
        'transform': transform,
        'transformOriginX': transformOriginX,
        'transformOriginY': transformOriginY
      };
}

class RecordingOverlayFrame {
  const RecordingOverlayFrame(
      {required this.position,
      required this.canvasWidth,
      required this.canvasHeight,
      required this.items,
      this.videoLeft = 0,
      this.videoTop = 0,
      this.videoWidth,
      this.videoHeight,
      this.opacity = 1});
  final Duration position;
  final double canvasWidth, canvasHeight;
  final double opacity;
  final double videoLeft, videoTop;
  final double? videoWidth, videoHeight;
  final List<RecordingOverlayItem> items;
  Map<String, dynamic> toJson() => {
        'positionMs': position.inMilliseconds,
        'canvasWidth': canvasWidth,
        'canvasHeight': canvasHeight,
        'videoLeft': videoLeft,
        'videoTop': videoTop,
        'videoWidth': videoWidth ?? canvasWidth,
        'videoHeight': videoHeight ?? canvasHeight,
        'opacity': opacity,
        'items': items.map((item) => item.toJson()).toList()
      };
}

class RecordingMediaInfo {
  const RecordingMediaInfo(
      {required this.duration,
      required this.width,
      required this.height,
      required this.videoCodec,
      this.audioCodec,
      this.frameRate = 30});
  final Duration duration;
  final int width, height;
  final String videoCodec;
  final String? audioCodec;
  final double frameRate;
  bool get valid => duration > Duration.zero && width > 0 && height > 0;
  bool get mp4Compatible =>
      (videoCodec == 'h264' || videoCodec == 'hevc') &&
      (audioCodec == null || audioCodec == 'aac');
}

abstract interface class RecordingBackend {
  Future<RecordingMediaInfo> probe(String path);
  Future<void> remux(String input, String output,
      {Duration? duration, Duration start = Duration.zero});
  Future<void> transcode(String input, String output);
  Future<void> burn(
      RecordingSession session, String output, bool Function() cancelled,
      {void Function(double progress)? onProgress});
  Future<void> cancel();
}

typedef RecordingSpriteBytes = Uint8List;
