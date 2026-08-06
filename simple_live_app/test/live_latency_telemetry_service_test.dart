import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/live_latency_telemetry_service.dart';

void main() {
  group('MpvTelemetryValue', () {
    test('parses finite numeric values and preserves null values', () {
      expect(MpvTelemetryValue.parse(1.25).value, 1.25);
      expect(MpvTelemetryValue.parse(' 2.5 ').value, 2.5);
      expect(MpvTelemetryValue.parse(null).format(), 'null');
      expect(MpvTelemetryValue.parse('NaN').format(), 'null');
      expect(const MpvTelemetryValue.unsupported().format(), 'unsupported');
    });
  });

  group('parseMpvDemuxerCacheDuration', () {
    test('accepts finite non-negative seconds', () {
      expect(parseMpvDemuxerCacheDuration('0'), 0);
      expect(parseMpvDemuxerCacheDuration(' 1.25 '), 1.25);
    });

    test('keeps unsupported and malformed values unknown', () {
      expect(parseMpvDemuxerCacheDuration(null), isNull);
      expect(parseMpvDemuxerCacheDuration(''), isNull);
      expect(parseMpvDemuxerCacheDuration('N/A'), isNull);
      expect(parseMpvDemuxerCacheDuration('-0.1'), isNull);
      expect(parseMpvDemuxerCacheDuration('NaN'), isNull);
      expect(parseMpvDemuxerCacheDuration('Infinity'), isNull);
    });
  });

  group('LiveLatencyTelemetryTracker', () {
    test('calculates adjacent wall clock and position progress', () {
      final tracker = LiveLatencyTelemetryTracker();
      final start = DateTime(2026, 8, 6, 12);

      expect(
        tracker.record(_sample(start, const Duration(seconds: 10))).progressRatio,
        isNull,
      );
      final delta = tracker.record(
        _sample(
          start.add(const Duration(seconds: 5)),
          const Duration(seconds: 14),
        ),
      );

      expect(delta.wallClockDelta, const Duration(seconds: 5));
      expect(delta.positionDelta, const Duration(seconds: 4));
      expect(delta.progressRatio, closeTo(0.8, 0.0001));
    });

    test('reset makes the next sample a new baseline', () {
      final tracker = LiveLatencyTelemetryTracker();
      final start = DateTime(2026, 8, 6, 12);
      tracker.record(_sample(start, const Duration(seconds: 10)));
      tracker.reset();

      final delta = tracker.record(
        _sample(
          start.add(const Duration(seconds: 5)),
          const Duration(seconds: 14),
        ),
      );

      expect(delta.wallClockDelta, isNull);
      expect(delta.positionDelta, isNull);
      expect(delta.progressRatio, isNull);
    });
  });

  test('formats diagnostics without a playback URL or token', () {
    final sample = _sample(
      DateTime(2026, 8, 6, 12),
      const Duration(seconds: 12),
      nativeProperties: const MpvLiveLatencyProperties.unsupported(),
    );
    final log = formatLiveLatencyTelemetry(
      target: 'bilibili/123',
      lineIndex: 0,
      lineCount: 2,
      protocol: 'FLV',
      elapsed: const Duration(seconds: 5),
      sample: sample,
      delta: const LiveLatencyTelemetryDelta.initial(),
    );

    expect(log, contains('position=12.000s'));
    expect(log, contains('wallDelta=null'));
    expect(log, contains('speed=unsupported'));
    expect(log, contains('frameDropCount=unsupported'));
    expect(log, isNot(contains('http')));
    expect(log, isNot(contains('token')));
  });
}

LiveLatencyTelemetrySample _sample(
  DateTime wallClock,
  Duration position, {
  MpvLiveLatencyProperties nativeProperties = const MpvLiveLatencyProperties(
    demuxerCacheDuration: MpvTelemetryValue.nullValue(),
    speed: MpvTelemetryValue.nullValue(),
    avsync: MpvTelemetryValue.nullValue(),
    decoderFrameDropCount: MpvTelemetryValue.nullValue(),
    frameDropCount: MpvTelemetryValue.nullValue(),
    mistimedFrameCount: MpvTelemetryValue.nullValue(),
    voDelayedFrameCount: MpvTelemetryValue.nullValue(),
  ),
}) {
  return LiveLatencyTelemetrySample(
    wallClock: wallClock,
    position: position,
    playing: true,
    buffering: false,
    nativeProperties: nativeProperties,
  );
}
