import 'live_link_health_models.dart';

const liveLinkHealthDataUnavailableLabel = '数据不足';

enum LiveLinkHealthPresentationMetric {
  currentBuffering,
  cache,
  cacheTrend,
  throughput,
  noDataDuration,
  audioUnderruns,
  buffering,
  reconnects,
  reconnectHostChange,
  reconnectRecovery,
  progress,
}

class LiveLinkHealthPresentationRow {
  const LiveLinkHealthPresentationRow({
    required this.metric,
    required this.label,
    required this.value,
    required this.supported,
  });

  final LiveLinkHealthPresentationMetric metric;
  final String label;
  final String value;
  final bool supported;
}

class LiveLinkHealthPresentation {
  const LiveLinkHealthPresentation({
    required this.levelLabel,
    required this.scoreLabel,
    required this.primaryCauseLabel,
    required this.rows,
  });

  final String levelLabel;
  final String scoreLabel;
  final String primaryCauseLabel;
  final List<LiveLinkHealthPresentationRow> rows;
}

LiveLinkHealthPresentation presentLiveLinkHealthSnapshot(
  LiveLinkHealthSnapshot snapshot, {
  required bool? currentBuffering,
}) {
  final metrics = snapshot.metrics;
  return LiveLinkHealthPresentation(
    levelLabel: _levelLabel(snapshot.level),
    scoreLabel: snapshot.score == null
        ? liveLinkHealthDataUnavailableLabel
        : '${snapshot.score}/100',
    primaryCauseLabel: _causeLabel(snapshot.primaryCause),
    rows: List.unmodifiable([
      LiveLinkHealthPresentationRow(
        metric: LiveLinkHealthPresentationMetric.currentBuffering,
        label: '当前播放状态',
        value: currentBuffering == null
            ? liveLinkHealthDataUnavailableLabel
            : currentBuffering
                ? '正在缓冲'
                : '正常播放',
        supported: currentBuffering != null,
      ),
      _optionalMetricRow(
        metric: LiveLinkHealthPresentationMetric.cache,
        label: '当前缓存',
        value: metrics.cacheSeconds,
        isSupported: (value) => value >= 0,
        format: (value) => '${value.toStringAsFixed(1)} 秒',
      ),
      _cacheTrendRow(metrics.cacheSlopeSecondsPerSecond),
      _optionalMetricRow(
        metric: LiveLinkHealthPresentationMetric.throughput,
        label: '接收吞吐/媒体码率',
        value: metrics.throughputRatio,
        isSupported: (value) => value >= 0,
        format: _formatThroughputRatio,
      ),
      _optionalDurationRow(
        metric: LiveLinkHealthPresentationMetric.noDataDuration,
        label: '连续无数据',
        duration: metrics.noDataDuration,
      ),
      _optionalCountRow(
        metric: LiveLinkHealthPresentationMetric.audioUnderruns,
        label: '音频欠载（最近60秒）',
        count: metrics.audioUnderrunCount,
      ),
      LiveLinkHealthPresentationRow(
        metric: LiveLinkHealthPresentationMetric.buffering,
        label: '缓冲（最近60秒）',
        value: '${metrics.bufferingCount} 次，共 '
            '${_formatDuration(metrics.bufferingDuration)}',
        supported: true,
      ),
      _optionalCountRow(
        metric: LiveLinkHealthPresentationMetric.reconnects,
        label: '自动重连（最近60秒）',
        count: metrics.automaticReconnectCount,
      ),
      _optionalBoolRow(
        metric: LiveLinkHealthPresentationMetric.reconnectHostChange,
        label: '最近重连更换 host',
        value: metrics.latestAutomaticReconnectHostChanged,
        trueLabel: '是',
        falseLabel: '否',
      ),
      _optionalDurationRow(
        metric: LiveLinkHealthPresentationMetric.reconnectRecovery,
        label: '最近重连恢复耗时',
        duration: metrics.latestAutomaticReconnectRecoveryDuration,
      ),
      _optionalMetricRow(
        metric: LiveLinkHealthPresentationMetric.progress,
        label: '播放推进',
        value: metrics.normalizedProgressRatio,
        isSupported: (value) => value >= 0,
        format: (value) => '${(value * 100).toStringAsFixed(0)}%',
      ),
    ]),
  );
}

LiveLinkHealthPresentationRow _optionalMetricRow({
  required LiveLinkHealthPresentationMetric metric,
  required String label,
  required double? value,
  required bool Function(double value) isSupported,
  required String Function(double value) format,
}) {
  if (value == null || !value.isFinite || !isSupported(value)) {
    return LiveLinkHealthPresentationRow(
      metric: metric,
      label: label,
      value: liveLinkHealthDataUnavailableLabel,
      supported: false,
    );
  }
  return LiveLinkHealthPresentationRow(
    metric: metric,
    label: label,
    value: format(value),
    supported: true,
  );
}

LiveLinkHealthPresentationRow _optionalCountRow({
  required LiveLinkHealthPresentationMetric metric,
  required String label,
  required int? count,
}) {
  if (count == null || count < 0) {
    return LiveLinkHealthPresentationRow(
      metric: metric,
      label: label,
      value: liveLinkHealthDataUnavailableLabel,
      supported: false,
    );
  }
  return LiveLinkHealthPresentationRow(
    metric: metric,
    label: label,
    value: '$count 次',
    supported: true,
  );
}

LiveLinkHealthPresentationRow _optionalDurationRow({
  required LiveLinkHealthPresentationMetric metric,
  required String label,
  required Duration? duration,
}) {
  if (duration == null || duration.isNegative) {
    return LiveLinkHealthPresentationRow(
      metric: metric,
      label: label,
      value: liveLinkHealthDataUnavailableLabel,
      supported: false,
    );
  }
  return LiveLinkHealthPresentationRow(
    metric: metric,
    label: label,
    value: _formatDuration(duration),
    supported: true,
  );
}

LiveLinkHealthPresentationRow _optionalBoolRow({
  required LiveLinkHealthPresentationMetric metric,
  required String label,
  required bool? value,
  required String trueLabel,
  required String falseLabel,
}) {
  return LiveLinkHealthPresentationRow(
    metric: metric,
    label: label,
    value: value == null
        ? liveLinkHealthDataUnavailableLabel
        : value
            ? trueLabel
            : falseLabel,
    supported: value != null,
  );
}

LiveLinkHealthPresentationRow _cacheTrendRow(double? slope) {
  if (slope == null || !slope.isFinite) {
    return const LiveLinkHealthPresentationRow(
      metric: LiveLinkHealthPresentationMetric.cacheTrend,
      label: '缓存趋势',
      value: liveLinkHealthDataUnavailableLabel,
      supported: false,
    );
  }
  return LiveLinkHealthPresentationRow(
    metric: LiveLinkHealthPresentationMetric.cacheTrend,
    label: '缓存趋势',
    value: '${_cacheTrendLabel(slope)}'
        '（${slope.toStringAsFixed(3)} 秒/秒）',
    supported: true,
  );
}

String _cacheTrendLabel(double slope) {
  if (slope < -0.05) return '快速下降';
  if (slope < -0.02) return '持续下降';
  if (slope > 0.05) return '快速上升';
  if (slope > 0.02) return '持续上升';
  return '基本稳定';
}

String _formatThroughputRatio(double ratio) {
  final status = ratio >= 1.25
      ? '充足'
      : ratio >= 1.0
          ? '临界'
          : ratio >= 0.75
              ? '不足'
              : '严重不足';
  return '${(ratio * 100).toStringAsFixed(0)}%（$status）';
}

String _formatDuration(Duration duration) {
  final totalSeconds =
      duration.inMicroseconds / Duration.microsecondsPerSecond;
  if (totalSeconds < 60) {
    return '${totalSeconds.toStringAsFixed(1)} 秒';
  }
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds - minutes * 60;
  return '$minutes 分 ${seconds.toStringAsFixed(1)} 秒';
}

String _levelLabel(LiveLinkHealthLevel level) {
  switch (level) {
    case LiveLinkHealthLevel.excellent:
      return '优秀';
    case LiveLinkHealthLevel.good:
      return '良好';
    case LiveLinkHealthLevel.fair:
      return '一般';
    case LiveLinkHealthLevel.poor:
      return '较差';
    case LiveLinkHealthLevel.critical:
      return '严重';
    case LiveLinkHealthLevel.unknown:
      return liveLinkHealthDataUnavailableLabel;
  }
}

String _causeLabel(LiveLinkHealthCause cause) {
  switch (cause) {
    case LiveLinkHealthCause.catchupCacheDrain:
      return '播放器追帧正在消耗缓存';
    case LiveLinkHealthCause.intakeInsufficient:
      return '直播数据接收供给不足';
    case LiveLinkHealthCause.decoderOrRenderStall:
      return '解码或渲染可能停滞';
    case LiveLinkHealthCause.playbackInstability:
      return '最近播放不稳定';
    case LiveLinkHealthCause.automaticReconnects:
      return '当前会话发生过自动重连';
    case LiveLinkHealthCause.healthy:
      return '直播链路状态正常';
    case LiveLinkHealthCause.insufficientData:
      return liveLinkHealthDataUnavailableLabel;
  }
}
