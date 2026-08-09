import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/live_link_health_models.dart';
import 'package:simple_live_app/services/live_link_health_presentation.dart';

void main() {
  test('maps a health snapshot to ordered Chinese diagnosis rows', () {
    final presentation = presentLiveLinkHealthSnapshot(
      _snapshot(
        score: 42,
        level: LiveLinkHealthLevel.poor,
        cause: LiveLinkHealthCause.catchupCacheDrain,
        cache: 0.603,
        slope: -0.061,
        throughput: 0.72,
        noDataDuration: const Duration(milliseconds: 200),
        audioUnderruns: 3,
        bufferingCount: 3,
        bufferingDuration: const Duration(milliseconds: 2800),
        reconnects: 1,
        progress: 0.93,
      ),
      currentBuffering: true,
    );

    expect(presentation.levelLabel, '较差');
    expect(presentation.scoreLabel, '42/100');
    expect(presentation.primaryCauseLabel, '播放器追帧正在消耗缓存');
    expect(presentation.rows, hasLength(9));
    expect(
      presentation.rows.map((row) => row.metric),
      const [
        LiveLinkHealthPresentationMetric.currentBuffering,
        LiveLinkHealthPresentationMetric.cache,
        LiveLinkHealthPresentationMetric.cacheTrend,
        LiveLinkHealthPresentationMetric.throughput,
        LiveLinkHealthPresentationMetric.noDataDuration,
        LiveLinkHealthPresentationMetric.audioUnderruns,
        LiveLinkHealthPresentationMetric.buffering,
        LiveLinkHealthPresentationMetric.reconnects,
        LiveLinkHealthPresentationMetric.progress,
      ],
    );
    expect(
      _row(
        presentation,
        LiveLinkHealthPresentationMetric.currentBuffering,
      ).value,
      '正在缓冲',
    );
    expect(_row(presentation, LiveLinkHealthPresentationMetric.cache).value,
        '0.6 秒');
    expect(
      _row(presentation, LiveLinkHealthPresentationMetric.cacheTrend).value,
      '快速下降（-0.061 秒/秒）',
    );
    expect(
      _row(presentation, LiveLinkHealthPresentationMetric.throughput).value,
      '72%（严重不足）',
    );
    expect(
      _row(
        presentation,
        LiveLinkHealthPresentationMetric.noDataDuration,
      ).value,
      '0.2 秒',
    );
    expect(
      _row(presentation, LiveLinkHealthPresentationMetric.audioUnderruns).value,
      '3 次',
    );
    expect(
      _row(presentation, LiveLinkHealthPresentationMetric.buffering).value,
      '3 次，共 2.8 秒',
    );
    expect(
      _row(presentation, LiveLinkHealthPresentationMetric.reconnects).value,
      '1 次',
    );
    expect(
      _row(presentation, LiveLinkHealthPresentationMetric.progress).value,
      '93%',
    );
  });

  test('renders every unsupported optional metric as data unavailable', () {
    final presentation = presentLiveLinkHealthSnapshot(
      _snapshot(
        score: null,
        level: LiveLinkHealthLevel.unknown,
        cause: LiveLinkHealthCause.insufficientData,
        cache: null,
        slope: null,
        throughput: null,
        noDataDuration: null,
        audioUnderruns: null,
        bufferingCount: 0,
        bufferingDuration: Duration.zero,
        reconnects: null,
        progress: null,
      ),
      currentBuffering: null,
    );

    expect(presentation.levelLabel, liveLinkHealthDataUnavailableLabel);
    expect(presentation.scoreLabel, liveLinkHealthDataUnavailableLabel);
    expect(presentation.primaryCauseLabel, liveLinkHealthDataUnavailableLabel);
    for (final metric in const [
      LiveLinkHealthPresentationMetric.currentBuffering,
      LiveLinkHealthPresentationMetric.cache,
      LiveLinkHealthPresentationMetric.cacheTrend,
      LiveLinkHealthPresentationMetric.throughput,
      LiveLinkHealthPresentationMetric.noDataDuration,
      LiveLinkHealthPresentationMetric.audioUnderruns,
      LiveLinkHealthPresentationMetric.reconnects,
      LiveLinkHealthPresentationMetric.progress,
    ]) {
      final row = _row(presentation, metric);
      expect(row.supported, isFalse);
      expect(row.value, liveLinkHealthDataUnavailableLabel);
    }
    expect(
      _row(presentation, LiveLinkHealthPresentationMetric.buffering).value,
      '0 次，共 0.0 秒',
    );
  });

  test('maps a false current buffering state to normal playback', () {
    final presentation = presentLiveLinkHealthSnapshot(
      _snapshot(
        score: null,
        level: LiveLinkHealthLevel.unknown,
        cause: LiveLinkHealthCause.insufficientData,
        cache: null,
        slope: null,
        throughput: null,
        noDataDuration: null,
        audioUnderruns: null,
        bufferingCount: 0,
        bufferingDuration: Duration.zero,
        reconnects: null,
        progress: null,
      ),
      currentBuffering: false,
    );

    final row = _row(
      presentation,
      LiveLinkHealthPresentationMetric.currentBuffering,
    );
    expect(row.supported, isTrue);
    expect(row.value, '正常播放');
  });
}

LiveLinkHealthPresentationRow _row(
  LiveLinkHealthPresentation presentation,
  LiveLinkHealthPresentationMetric metric,
) =>
    presentation.rows.singleWhere((row) => row.metric == metric);

LiveLinkHealthSnapshot _snapshot({
  required int? score,
  required LiveLinkHealthLevel level,
  required LiveLinkHealthCause cause,
  required double? cache,
  required double? slope,
  required double? throughput,
  required Duration? noDataDuration,
  required int? audioUnderruns,
  required int bufferingCount,
  required Duration bufferingDuration,
  required int? reconnects,
  required double? progress,
}) {
  return LiveLinkHealthSnapshot(
    score: score,
    level: level,
    causes: [cause],
    window: const Duration(seconds: 60),
    hasEnoughData: score != null,
    metrics: LiveLinkHealthMetrics(
      eligibleWindow: const Duration(seconds: 10),
      availableDomainCount: 4,
      cacheSeconds: cache,
      cacheSlopeSecondsPerSecond: slope,
      throughputRatio: throughput,
      noDataDuration: noDataDuration,
      audioUnderrunCount: audioUnderruns,
      bufferingCount: bufferingCount,
      bufferingDuration: bufferingDuration,
      bufferingRatio: 0,
      longestBuffering: bufferingDuration,
      automaticReconnectCount: reconnects,
      automaticReconnectReasons: const [],
      normalizedProgressRatio: progress,
      longestProgressStall: Duration.zero,
      playbackEndpointReachable: null,
      penalties: const LiveLinkHealthPenalties(
        intake: 0,
        buffer: 0,
        continuity: 0,
        recovery: 0,
      ),
    ),
    suggestions: const [],
  );
}
