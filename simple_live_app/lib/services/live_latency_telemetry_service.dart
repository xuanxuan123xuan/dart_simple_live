import 'package:media_kit/media_kit.dart';

const mpvDemuxerCacheDurationProperty = 'demuxer-cache-duration';
const mpvSpeedProperty = 'speed';
const mpvAvsyncProperty = 'avsync';
const mpvDecoderFrameDropCountProperty = 'decoder-frame-drop-count';
const mpvFrameDropCountProperty = 'frame-drop-count';
const mpvMistimedFrameCountProperty = 'mistimed-frame-count';
const mpvVoDelayedFrameCountProperty = 'vo-delayed-frame-count';

class MpvTelemetryValue {
  final double? value;
  final bool supported;

  const MpvTelemetryValue._({required this.value, required this.supported});

  const MpvTelemetryValue.unsupported() : this._(value: null, supported: false);

  const MpvTelemetryValue.nullValue() : this._(value: null, supported: true);

  factory MpvTelemetryValue.parse(Object? raw) {
    if (raw is num && raw.isFinite) {
      return MpvTelemetryValue._(value: raw.toDouble(), supported: true);
    }
    final value = double.tryParse(raw?.toString().trim() ?? '');
    return MpvTelemetryValue._(
      value: value != null && value.isFinite ? value : null,
      supported: true,
    );
  }

  String format({int fractionDigits = 3}) {
    if (!supported) return 'unsupported';
    final number = value;
    return number == null ? 'null' : number.toStringAsFixed(fractionDigits);
  }
}

class MpvLiveLatencyProperties {
  final MpvTelemetryValue demuxerCacheDuration;
  final MpvTelemetryValue speed;
  final MpvTelemetryValue avsync;
  final MpvTelemetryValue decoderFrameDropCount;
  final MpvTelemetryValue frameDropCount;
  final MpvTelemetryValue mistimedFrameCount;
  final MpvTelemetryValue voDelayedFrameCount;

  const MpvLiveLatencyProperties({
    required this.demuxerCacheDuration,
    required this.speed,
    required this.avsync,
    required this.decoderFrameDropCount,
    required this.frameDropCount,
    required this.mistimedFrameCount,
    required this.voDelayedFrameCount,
  });

  const MpvLiveLatencyProperties.unsupported()
      : demuxerCacheDuration = const MpvTelemetryValue.unsupported(),
        speed = const MpvTelemetryValue.unsupported(),
        avsync = const MpvTelemetryValue.unsupported(),
        decoderFrameDropCount = const MpvTelemetryValue.unsupported(),
        frameDropCount = const MpvTelemetryValue.unsupported(),
        mistimedFrameCount = const MpvTelemetryValue.unsupported(),
        voDelayedFrameCount = const MpvTelemetryValue.unsupported();
}

class LiveLatencyTelemetrySample {
  final DateTime wallClock;
  final Duration position;
  final bool playing;
  final bool buffering;
  final MpvLiveLatencyProperties nativeProperties;

  const LiveLatencyTelemetrySample({
    required this.wallClock,
    required this.position,
    required this.playing,
    required this.buffering,
    required this.nativeProperties,
  });
}

class LiveLatencyTelemetryDelta {
  final Duration? wallClockDelta;
  final Duration? positionDelta;
  final double? progressRatio;

  const LiveLatencyTelemetryDelta({
    required this.wallClockDelta,
    required this.positionDelta,
    required this.progressRatio,
  });

  const LiveLatencyTelemetryDelta.initial()
      : wallClockDelta = null,
        positionDelta = null,
        progressRatio = null;
}

/// Maintains only the preceding sample. Call [reset] when a source is reopened.
class LiveLatencyTelemetryTracker {
  LiveLatencyTelemetrySample? _previous;

  void reset() {
    _previous = null;
  }

  LiveLatencyTelemetryDelta record(LiveLatencyTelemetrySample sample) {
    final previous = _previous;
    _previous = sample;
    if (previous == null) return const LiveLatencyTelemetryDelta.initial();

    final wallClockDelta = sample.wallClock.difference(previous.wallClock);
    final positionDelta = sample.position - previous.position;
    final progressRatio = wallClockDelta.inMicroseconds > 0
        ? positionDelta.inMicroseconds / wallClockDelta.inMicroseconds
        : null;
    return LiveLatencyTelemetryDelta(
      wallClockDelta: wallClockDelta,
      positionDelta: positionDelta,
      progressRatio: progressRatio,
    );
  }
}

double? parseMpvDemuxerCacheDuration(String? raw) {
  final value = MpvTelemetryValue.parse(raw).value;
  return value != null && value >= 0 ? value : null;
}

Future<MpvLiveLatencyProperties> sampleMpvLiveLatencyProperties(
  Player player,
) async {
  final platform = player.platform;
  if (platform is! NativePlayer) {
    return const MpvLiveLatencyProperties.unsupported();
  }
  // NativePlayer's web stub omits getProperty, so keep this call dynamic.
  final dynamic native = platform;
  final values = await Future.wait([
    _sampleMpvProperty(native, mpvDemuxerCacheDurationProperty),
    _sampleMpvProperty(native, mpvSpeedProperty),
    _sampleMpvProperty(native, mpvAvsyncProperty),
    _sampleMpvProperty(native, mpvDecoderFrameDropCountProperty),
    _sampleMpvProperty(native, mpvFrameDropCountProperty),
    _sampleMpvProperty(native, mpvMistimedFrameCountProperty),
    _sampleMpvProperty(native, mpvVoDelayedFrameCountProperty),
  ]);
  return MpvLiveLatencyProperties(
    demuxerCacheDuration: values[0],
    speed: values[1],
    avsync: values[2],
    decoderFrameDropCount: values[3],
    frameDropCount: values[4],
    mistimedFrameCount: values[5],
    voDelayedFrameCount: values[6],
  );
}

Future<MpvTelemetryValue> _sampleMpvProperty(
  dynamic native,
  String property,
) async {
  try {
    return MpvTelemetryValue.parse(await native.getProperty(property));
  } catch (_) {
    return const MpvTelemetryValue.unsupported();
  }
}

Future<double?> sampleMpvDemuxerCacheDuration(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) {
    return null;
  }
  try {
    // The chase loop runs more often than diagnostics; keep it to one property
    // read so telemetry cannot add seven native calls every two seconds.
    final dynamic native = platform;
    final dynamic raw =
        await native.getProperty(mpvDemuxerCacheDurationProperty);
    return parseMpvDemuxerCacheDuration(raw?.toString());
  } catch (_) {
    return null;
  }
}

String formatLiveLatencyTelemetry({
  required String target,
  required int lineIndex,
  required int lineCount,
  required String protocol,
  required Duration elapsed,
  required LiveLatencyTelemetrySample sample,
  required LiveLatencyTelemetryDelta delta,
}) {
  final properties = sample.nativeProperties;
  return '[live-latency] target=$target '
      'line=${lineIndex + 1}/$lineCount '
      'protocol=$protocol '
      'elapsed=${_formatSeconds(elapsed)} '
      'position=${_formatSeconds(sample.position)} '
      'wallDelta=${_formatOptionalSeconds(delta.wallClockDelta)} '
      'positionDelta=${_formatOptionalSeconds(delta.positionDelta)} '
      'progressRatio=${_formatOptionalNumber(delta.progressRatio)} '
      'playing=${sample.playing} '
      'buffering=${sample.buffering} '
      'speed=${properties.speed.format()} '
      'demuxerCache=${properties.demuxerCacheDuration.format()} '
      'avsync=${properties.avsync.format()} '
      'decoderFrameDropCount=${properties.decoderFrameDropCount.format()} '
      'frameDropCount=${properties.frameDropCount.format()} '
      'mistimedFrameCount=${properties.mistimedFrameCount.format()} '
      'voDelayedFrameCount=${properties.voDelayedFrameCount.format()}';
}

String _formatSeconds(Duration duration) =>
    '${(duration.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(3)}s';

String _formatOptionalSeconds(Duration? duration) =>
    duration == null ? 'null' : _formatSeconds(duration);

String _formatOptionalNumber(double? value) =>
    value == null ? 'null' : value.toStringAsFixed(3);
