import 'dart:math' as math;

import 'live_link_health_models.dart';

class LiveLinkHealthEvaluationInput {
  const LiveLinkHealthEvaluationInput({
    required this.now,
    required this.samples,
    required this.events,
    this.capabilities = const LiveLinkHealthCapabilities(),
  });

  final DateTime now;
  final List<LiveLinkHealthSample> samples;
  final List<LiveLinkHealthEvent> events;
  final LiveLinkHealthCapabilities capabilities;
}

class LiveLinkHealthEvaluator {
  const LiveLinkHealthEvaluator();

  static const shortWindow = Duration(seconds: 10);
  static const longWindow = Duration(seconds: 60);
  static const minimumObservation = Duration(seconds: 10);

  LiveLinkHealthSnapshot evaluate(LiveLinkHealthEvaluationInput input) {
    final longSamples = _within(input.samples, input.now, longWindow);
    final shortSamples = _within(longSamples, input.now, shortWindow);
    final events = input.events
        .where((event) =>
            !event.occurredAt.isBefore(input.now.subtract(longWindow)) &&
            !event.occurredAt.isAfter(input.now))
        .toList(growable: false);

    final eligibleSeconds = math.min(longSamples.length, longWindow.inSeconds);
    final eligibleWindow = Duration(seconds: eligibleSeconds);
    final cacheSamples = shortSamples
        .where((sample) => sample.demuxerCacheSeconds != null)
        .toList(growable: false);
    final cacheSeconds = cacheSamples.isEmpty
        ? null
        : cacheSamples.last.demuxerCacheSeconds;
    final cacheSlope = cacheRegressionSlope(cacheSamples);

    final ratios = <double>[];
    for (final sample in shortSamples) {
      final received = sample.receiveBytesPerSecond;
      final estimatedBits = sample.estimatedMediaBitsPerSecond;
      if (received == null || estimatedBits == null || estimatedBits <= 0) {
        continue;
      }
      ratios.add(received * 8 / estimatedBits);
    }
    final throughputRatio = ratios.isEmpty ? null : _median(ratios);
    final noDataDuration = _noDataDuration(longSamples, input.now);
    final endpointReachable = _latestEndpointReachability(longSamples);

    final audioUnderrunCount = input.capabilities.audioUnderrunEvents
        ? events
            .where((event) => event.type == LiveLinkEventType.audioUnderrun)
            .length
        : null;
    final bufferingCount = events
        .where((event) => event.type == LiveLinkEventType.bufferingStarted)
        .length;
    final buffering = _bufferingMetrics(longSamples);
    final automaticReconnectCount = input.capabilities.automaticReconnectEvents
        ? events
            .where((event) => event.type == LiveLinkEventType.cdnReconnect)
            .length
        : null;
    final automaticReconnectReasons =
        input.capabilities.automaticReconnectEvents
            ? events
                .where((event) => event.type == LiveLinkEventType.cdnReconnect)
                .map((event) => event.reconnectReason)
                .whereType<LiveReconnectReason>()
                .toList(growable: false)
            : const <LiveReconnectReason>[];
    final progress = _progressMetrics(shortSamples);

    final intakeAvailable = longSamples.any(
          (sample) => sample.receiveBytesPerSecond != null,
        ) ||
        endpointReachable != null;
    final bufferAvailable = cacheSamples.isNotEmpty;
    final continuityAvailable = longSamples.length >= 2;
    final recoveryAvailable = input.capabilities.automaticReconnectEvents;
    final availableDomainCount = [
      intakeAvailable,
      bufferAvailable,
      continuityAvailable,
      recoveryAvailable,
    ].where((available) => available).length;

    final intakePenalty = _intakePenalty(
      noDataDuration: noDataDuration,
      throughputRatio: throughputRatio,
      throughputSampleCount: ratios.length,
      endpointReachable: endpointReachable,
      normalizedProgressRatio: progress.normalizedRatio,
    );
    final bufferPenalty = _bufferPenalty(
      cacheSeconds: cacheSeconds,
      cacheSlope: cacheSlope,
      playbackSpeed:
          shortSamples.isEmpty ? null : shortSamples.last.playbackSpeed,
    );
    final continuityPenalty = _continuityPenalty(
      bufferingCount: bufferingCount,
      bufferingRatio: buffering.ratio,
      audioUnderrunCount: audioUnderrunCount,
      normalizedProgressRatio: progress.normalizedRatio,
      progressWindow: progress.observedDuration,
    );
    final reconnectCount = automaticReconnectCount ?? 0;
    final recoveryPenalty = reconnectCount >= 2
        ? 10
        : reconnectCount == 1
            ? 5
            : 0;
    final penalties = LiveLinkHealthPenalties(
      intake: intakePenalty,
      buffer: bufferPenalty,
      continuity: continuityPenalty,
      recovery: recoveryPenalty,
    );
    final hasEnoughData = eligibleWindow >= minimumObservation &&
        availableDomainCount >= 2;
    final score = hasEnoughData
        ? (100 - penalties.total).clamp(0, 100).toInt()
        : null;
    final level = score == null ? LiveLinkHealthLevel.unknown : levelFor(score);

    final primaryCause = _primaryCause(
      samples: shortSamples,
      cacheSeconds: cacheSeconds,
      cacheSlope: cacheSlope,
      throughputRatio: throughputRatio,
      noDataDuration: noDataDuration,
      endpointReachable: endpointReachable,
      normalizedProgressRatio: progress.normalizedRatio,
      longestProgressStall: progress.longestStall,
      frameDropGrowth: progress.frameDropGrowth,
      bufferPenalty: bufferPenalty,
      continuityPenalty: continuityPenalty,
      recoveryPenalty: recoveryPenalty,
      hasEnoughData: hasEnoughData,
    );
    final metrics = LiveLinkHealthMetrics(
      eligibleWindow: eligibleWindow,
      availableDomainCount: availableDomainCount,
      cacheSeconds: cacheSeconds,
      cacheSlopeSecondsPerSecond: cacheSlope,
      throughputRatio: throughputRatio,
      noDataDuration: noDataDuration,
      audioUnderrunCount: audioUnderrunCount,
      bufferingCount: bufferingCount,
      bufferingDuration: buffering.duration,
      bufferingRatio: buffering.ratio,
      longestBuffering: buffering.longest,
      automaticReconnectCount: automaticReconnectCount,
      automaticReconnectReasons: automaticReconnectReasons,
      normalizedProgressRatio: progress.normalizedRatio,
      longestProgressStall: progress.longestStall,
      playbackEndpointReachable: endpointReachable,
      penalties: penalties,
    );

    return LiveLinkHealthSnapshot(
      score: score,
      level: level,
      causes: [primaryCause],
      window: longWindow,
      hasEnoughData: hasEnoughData,
      metrics: metrics,
      suggestions: _suggestions(primaryCause),
    );
  }

  static double? cacheRegressionSlope(List<LiveLinkHealthSample> samples) {
    if (samples.length < 2) {
      return null;
    }
    final origin = samples.first.sampledAt;
    final xs = <double>[];
    final ys = <double>[];
    for (final sample in samples) {
      final cache = sample.demuxerCacheSeconds;
      if (cache == null) {
        continue;
      }
      xs.add(sample.sampledAt.difference(origin).inMicroseconds / 1000000);
      ys.add(cache);
    }
    if (xs.length < 2) {
      return null;
    }
    final meanX = xs.reduce((a, b) => a + b) / xs.length;
    final meanY = ys.reduce((a, b) => a + b) / ys.length;
    var numerator = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < xs.length; i += 1) {
      final dx = xs[i] - meanX;
      numerator += dx * (ys[i] - meanY);
      denominator += dx * dx;
    }
    return denominator == 0 ? null : numerator / denominator;
  }

  static LiveLinkHealthLevel levelFor(int score) {
    if (score >= 90) return LiveLinkHealthLevel.excellent;
    if (score >= 75) return LiveLinkHealthLevel.good;
    if (score >= 55) return LiveLinkHealthLevel.fair;
    if (score >= 30) return LiveLinkHealthLevel.poor;
    return LiveLinkHealthLevel.critical;
  }

  static int scoreForDisplayedLevel(
    int rawScore,
    LiveLinkHealthLevel displayedLevel,
  ) {
    final (minimum, maximum) = switch (displayedLevel) {
      LiveLinkHealthLevel.excellent => (90, 100),
      LiveLinkHealthLevel.good => (75, 89),
      LiveLinkHealthLevel.fair => (55, 74),
      LiveLinkHealthLevel.poor => (30, 54),
      LiveLinkHealthLevel.critical => (0, 29),
      LiveLinkHealthLevel.unknown => (0, 100),
    };
    return rawScore.clamp(minimum, maximum).toInt();
  }

  List<LiveLinkHealthSample> _within(
    List<LiveLinkHealthSample> samples,
    DateTime now,
    Duration window,
  ) {
    final cutoff = now.subtract(window);
    final result = samples
        .where((sample) =>
            !sample.sampledAt.isBefore(cutoff) &&
            !sample.sampledAt.isAfter(now))
        .toList(growable: false);
    result.sort((a, b) => a.sampledAt.compareTo(b.sampledAt));
    return result;
  }

  Duration? _noDataDuration(
    List<LiveLinkHealthSample> samples,
    DateTime now,
  ) {
    final supported = samples
        .where((sample) => sample.receiveBytesPerSecond != null)
        .toList(growable: false);
    if (supported.isEmpty || samples.last.receiveBytesPerSecond == null) {
      return null;
    }
    for (final sample in supported.reversed) {
      if (sample.receiveBytesPerSecond! > 0) {
        return now.difference(sample.sampledAt);
      }
    }
    return now.difference(supported.first.sampledAt);
  }

  bool? _latestEndpointReachability(List<LiveLinkHealthSample> samples) {
    for (final sample in samples.reversed) {
      if (sample.playbackEndpointReachable != null) {
        return sample.playbackEndpointReachable;
      }
    }
    return null;
  }

  _BufferingMetrics _bufferingMetrics(List<LiveLinkHealthSample> samples) {
    var bufferingSeconds = 0;
    var currentRun = 0;
    var longestRun = 0;
    for (final sample in samples) {
      if (sample.buffering) {
        bufferingSeconds += 1;
        currentRun += 1;
        longestRun = math.max(longestRun, currentRun);
      } else {
        currentRun = 0;
      }
    }
    final eligibleSeconds = math.min(samples.length, longWindow.inSeconds);
    bufferingSeconds = math.min(bufferingSeconds, eligibleSeconds);
    longestRun = math.min(longestRun, eligibleSeconds);
    return _BufferingMetrics(
      duration: Duration(seconds: bufferingSeconds),
      ratio: eligibleSeconds == 0 ? 0 : bufferingSeconds / eligibleSeconds,
      longest: Duration(seconds: longestRun),
    );
  }

  _ProgressMetrics _progressMetrics(List<LiveLinkHealthSample> samples) {
    var observedUs = 0;
    var expectedProgressUs = 0.0;
    var actualProgressUs = 0;
    var currentStallUs = 0;
    var longestStallUs = 0;
    for (var i = 1; i < samples.length; i += 1) {
      final previous = samples[i - 1];
      final current = samples[i];
      final wallUs =
          current.sampledAt.difference(previous.sampledAt).inMicroseconds;
      final positionUs =
          (current.position - previous.position).inMicroseconds;
      if (wallUs <= 0 || wallUs > const Duration(seconds: 2).inMicroseconds) {
        currentStallUs = 0;
        continue;
      }
      if (positionUs < 0) {
        currentStallUs = 0;
        continue;
      }
      final speed = ((previous.playbackSpeed + current.playbackSpeed) / 2)
          .clamp(0.01, 10.0)
          .toDouble();
      observedUs += wallUs;
      expectedProgressUs += wallUs * speed;
      actualProgressUs += positionUs;
      if (current.playing && !current.buffering && positionUs <= 50000) {
        currentStallUs += wallUs;
        longestStallUs = math.max(longestStallUs, currentStallUs);
      } else {
        currentStallUs = 0;
      }
    }
    final firstDrops = _combinedDrops(samples, first: true);
    final lastDrops = _combinedDrops(samples, first: false);
    return _ProgressMetrics(
      normalizedRatio: expectedProgressUs <= 0
          ? null
          : actualProgressUs / expectedProgressUs,
      observedDuration: Duration(microseconds: observedUs),
      longestStall: Duration(microseconds: longestStallUs),
      frameDropGrowth: firstDrops == null || lastDrops == null
          ? null
          : math.max(0, lastDrops - firstDrops),
    );
  }

  int? _combinedDrops(List<LiveLinkHealthSample> samples,
      {required bool first}) {
    final iterable = first ? samples : samples.reversed;
    for (final sample in iterable) {
      if (sample.decoderFrameDropCount != null || sample.frameDropCount != null) {
        return (sample.decoderFrameDropCount ?? 0) +
            (sample.frameDropCount ?? 0);
      }
    }
    return null;
  }

  int _intakePenalty({
    required Duration? noDataDuration,
    required double? throughputRatio,
    required int throughputSampleCount,
    required bool? endpointReachable,
    required double? normalizedProgressRatio,
  }) {
    var penalty = 0;
    if (noDataDuration != null) {
      if (noDataDuration >= const Duration(seconds: 5)) {
        penalty = math.max(penalty, 35);
      } else if (noDataDuration >= const Duration(seconds: 2)) {
        penalty = math.max(penalty, 25);
      } else if (noDataDuration >= const Duration(seconds: 1)) {
        penalty = math.max(penalty, 10);
      }
    }
    if (throughputRatio != null && throughputSampleCount >= 5) {
      if (throughputRatio < 0.75) {
        penalty = math.max(penalty, 30);
      } else if (throughputRatio < 1.0) {
        penalty = math.max(penalty, 15);
      }
    }
    if (endpointReachable == false &&
        normalizedProgressRatio != null &&
        normalizedProgressRatio < 0.8) {
      penalty = math.max(penalty, 35);
    }
    return penalty;
  }

  int _bufferPenalty({
    required double? cacheSeconds,
    required double? cacheSlope,
    required double? playbackSpeed,
  }) {
    var penalty = 0;
    if (cacheSlope != null) {
      if (cacheSlope < -0.05) {
        penalty = math.max(penalty, 15);
      } else if (cacheSlope < -0.02) {
        penalty = math.max(penalty, 8);
      }
    }
    if (cacheSeconds != null) {
      if (cacheSeconds < 0.3) {
        penalty = math.max(penalty, 25);
      } else if (cacheSeconds < 1.0) {
        penalty = math.max(penalty, 15);
      }
    }
    if (playbackSpeed != null &&
        playbackSpeed > 1.01 &&
        cacheSeconds != null &&
        cacheSeconds < 1.0 &&
        cacheSlope != null &&
        cacheSlope < -0.02) {
      penalty = math.max(penalty, 25);
    }
    return penalty;
  }

  int _continuityPenalty({
    required int bufferingCount,
    required double bufferingRatio,
    required int? audioUnderrunCount,
    required double? normalizedProgressRatio,
    required Duration progressWindow,
  }) {
    var penalty = 0;
    if (bufferingCount >= 3) {
      penalty = math.max(penalty, 25);
    } else if (bufferingCount == 2) {
      penalty = math.max(penalty, 15);
    } else if (bufferingCount == 1) {
      penalty = math.max(penalty, 8);
    }
    if (bufferingRatio > 0.15) {
      penalty = math.max(penalty, 30);
    } else if (bufferingRatio >= 0.05) {
      penalty = math.max(penalty, 15);
    }
    if (audioUnderrunCount != null) {
      if (audioUnderrunCount >= 2) {
        penalty = math.max(penalty, 20);
      } else if (audioUnderrunCount == 1) {
        penalty = math.max(penalty, 10);
      }
    }
    if (normalizedProgressRatio != null &&
        normalizedProgressRatio < 0.8 &&
        progressWindow >= const Duration(seconds: 3)) {
      penalty = math.max(penalty, 25);
    }
    return penalty;
  }

  LiveLinkHealthCause _primaryCause({
    required List<LiveLinkHealthSample> samples,
    required double? cacheSeconds,
    required double? cacheSlope,
    required double? throughputRatio,
    required Duration? noDataDuration,
    required bool? endpointReachable,
    required double? normalizedProgressRatio,
    required Duration longestProgressStall,
    required int? frameDropGrowth,
    required int bufferPenalty,
    required int continuityPenalty,
    required int recoveryPenalty,
    required bool hasEnoughData,
  }) {
    if (!hasEnoughData) {
      return LiveLinkHealthCause.insufficientData;
    }
    final speed = samples.isEmpty ? 1.0 : samples.last.playbackSpeed;
    final cacheAtRisk = (cacheSeconds != null && cacheSeconds < 1.0) ||
        (cacheSlope != null && cacheSlope < -0.05);
    final sustainedNoData =
        noDataDuration != null && noDataDuration >= const Duration(seconds: 2);
    if (speed > 1.01 &&
        cacheAtRisk &&
        endpointReachable != false &&
        !sustainedNoData &&
        (throughputRatio == null || throughputRatio >= 0.75)) {
      return LiveLinkHealthCause.catchupCacheDrain;
    }
    final cacheStable = cacheSlope == null || cacheSlope >= -0.02;
    final decoderEvidence =
        longestProgressStall >= const Duration(seconds: 3) ||
            (frameDropGrowth != null && frameDropGrowth >= 10);
    if (throughputRatio != null &&
        throughputRatio >= 1.25 &&
        cacheStable &&
        decoderEvidence) {
      return LiveLinkHealthCause.decoderOrRenderStall;
    }
    final intakeEvidence = sustainedNoData ||
        (throughputRatio != null &&
            throughputRatio < 0.75 &&
            cacheSlope != null &&
            cacheSlope < -0.02) ||
        (endpointReachable == false &&
            normalizedProgressRatio != null &&
            normalizedProgressRatio < 0.8);
    if (intakeEvidence) {
      return LiveLinkHealthCause.intakeInsufficient;
    }
    if (bufferPenalty > 0 || continuityPenalty > 0) {
      return LiveLinkHealthCause.playbackInstability;
    }
    if (recoveryPenalty > 0) {
      return LiveLinkHealthCause.automaticReconnects;
    }
    return LiveLinkHealthCause.healthy;
  }

  List<String> _suggestions(LiveLinkHealthCause cause) {
    switch (cause) {
      case LiveLinkHealthCause.catchupCacheDrain:
        return const ['播放器追帧正在消耗缓存，请继续观察缓存变化。'];
      case LiveLinkHealthCause.intakeInsufficient:
        return const ['当前直播线路供给不足，可稍后尝试其他线路或清晰度。'];
      case LiveLinkHealthCause.decoderOrRenderStall:
        return const ['网络供给正常，优先检查解码、渲染或画质设置。'];
      case LiveLinkHealthCause.playbackInstability:
        return const ['最近发生播放中断，请继续观察是否重复出现。'];
      case LiveLinkHealthCause.automaticReconnects:
        return const ['当前会话发生自动重连，请观察线路恢复情况。'];
      case LiveLinkHealthCause.healthy:
        return const [];
      case LiveLinkHealthCause.insufficientData:
        return const ['数据采集中，或当前播放器不支持完整遥测。'];
    }
  }

  double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle];
    }
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

class LiveLinkHealthLevelHysteresis {
  LiveLinkHealthLevelHysteresis({
    this.recoveryDuration = const Duration(seconds: 10),
  });

  final Duration recoveryDuration;
  LiveLinkHealthLevel? _displayed;
  LiveLinkHealthLevel? _healthierCandidate;
  DateTime? _healthierSince;

  LiveLinkHealthLevel apply(LiveLinkHealthLevel raw, DateTime now) {
    if (raw == LiveLinkHealthLevel.unknown) {
      reset();
      return raw;
    }
    final displayed = _displayed;
    if (displayed == null || _severity(raw) >= _severity(displayed)) {
      _displayed = raw;
      _healthierCandidate = null;
      _healthierSince = null;
      return raw;
    }
    if (_healthierCandidate != raw) {
      _healthierCandidate = raw;
      _healthierSince = now;
      return displayed;
    }
    if (now.difference(_healthierSince!) >= recoveryDuration) {
      _displayed = raw;
      _healthierCandidate = null;
      _healthierSince = null;
      return raw;
    }
    return displayed;
  }

  void reset() {
    _displayed = null;
    _healthierCandidate = null;
    _healthierSince = null;
  }

  int _severity(LiveLinkHealthLevel level) => switch (level) {
        LiveLinkHealthLevel.excellent => 0,
        LiveLinkHealthLevel.good => 1,
        LiveLinkHealthLevel.fair => 2,
        LiveLinkHealthLevel.poor => 3,
        LiveLinkHealthLevel.critical => 4,
        LiveLinkHealthLevel.unknown => -1,
      };
}

class _BufferingMetrics {
  const _BufferingMetrics({
    required this.duration,
    required this.ratio,
    required this.longest,
  });

  final Duration duration;
  final double ratio;
  final Duration longest;
}

class _ProgressMetrics {
  const _ProgressMetrics({
    required this.normalizedRatio,
    required this.observedDuration,
    required this.longestStall,
    required this.frameDropGrowth,
  });

  final double? normalizedRatio;
  final Duration observedDuration;
  final Duration longestStall;
  final int? frameDropGrowth;
}
