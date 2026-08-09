enum LiveLinkHealthLevel {
  excellent,
  good,
  fair,
  poor,
  critical,
  unknown,
}

enum LiveLinkHealthCause {
  catchupCacheDrain,
  intakeInsufficient,
  decoderOrRenderStall,
  playbackInstability,
  automaticReconnects,
  healthy,
  insufficientData,
}

enum LiveLinkEventType {
  bufferingStarted,
  bufferingEnded,
  audioUnderrun,
  streamOpened,
  cdnReconnect,
  lineChangedByUser,
  qualityChangedByUser,
  playbackPausedByUser,
  playbackResumedByUser,
  appBackgrounded,
  appForegrounded,
}

enum LiveReconnectReason {
  mediaError,
  mediaEnd,
  sustainedBuffering,
  playbackUrlRefresh,
  automaticLineFailover,
}

class LiveLinkHealthCapabilities {
  const LiveLinkHealthCapabilities({
    this.audioUnderrunEvents = false,
    this.automaticReconnectEvents = false,
  });

  final bool audioUnderrunEvents;
  final bool automaticReconnectEvents;
}

class LiveLinkHealthSample {
  const LiveLinkHealthSample({
    required this.generation,
    required this.sampledAt,
    required this.position,
    required this.playing,
    required this.buffering,
    required this.playbackSpeed,
    this.streamActive = true,
    this.demuxerCacheSeconds,
    this.receiveBytesPerSecond,
    this.estimatedMediaBitsPerSecond,
    this.avsyncSeconds,
    this.decoderFrameDropCount,
    this.frameDropCount,
    this.playbackEndpointReachable,
  });

  final int generation;
  final DateTime sampledAt;
  final Duration position;
  final bool playing;
  final bool buffering;
  final double playbackSpeed;
  final bool streamActive;
  final double? demuxerCacheSeconds;
  final double? receiveBytesPerSecond;
  final double? estimatedMediaBitsPerSecond;
  final double? avsyncSeconds;
  final int? decoderFrameDropCount;
  final int? frameDropCount;
  final bool? playbackEndpointReachable;
}

class LiveLinkHealthEvent {
  const LiveLinkHealthEvent({
    required this.generation,
    required this.occurredAt,
    required this.type,
    this.reconnectReason,
  }) : assert(
          type != LiveLinkEventType.cdnReconnect || reconnectReason != null,
          'cdnReconnect events require a structured reconnect reason',
        );

  final int generation;
  final DateTime occurredAt;
  final LiveLinkEventType type;
  final LiveReconnectReason? reconnectReason;
}

class LiveLinkHealthPenalties {
  const LiveLinkHealthPenalties({
    required this.intake,
    required this.buffer,
    required this.continuity,
    required this.recovery,
  });

  final int intake;
  final int buffer;
  final int continuity;
  final int recovery;

  int get total => intake + buffer + continuity + recovery;
}

class LiveLinkHealthMetrics {
  const LiveLinkHealthMetrics({
    required this.eligibleWindow,
    required this.availableDomainCount,
    required this.cacheSeconds,
    required this.cacheSlopeSecondsPerSecond,
    required this.throughputRatio,
    required this.noDataDuration,
    required this.audioUnderrunCount,
    required this.bufferingCount,
    required this.bufferingDuration,
    required this.bufferingRatio,
    required this.longestBuffering,
    required this.automaticReconnectCount,
    required this.automaticReconnectReasons,
    required this.normalizedProgressRatio,
    required this.longestProgressStall,
    required this.playbackEndpointReachable,
    required this.penalties,
  });

  final Duration eligibleWindow;
  final int availableDomainCount;
  final double? cacheSeconds;
  final double? cacheSlopeSecondsPerSecond;
  final double? throughputRatio;
  final Duration? noDataDuration;
  final int? audioUnderrunCount;
  final int bufferingCount;
  final Duration bufferingDuration;
  final double bufferingRatio;
  final Duration longestBuffering;
  final int? automaticReconnectCount;
  final List<LiveReconnectReason> automaticReconnectReasons;
  final double? normalizedProgressRatio;
  final Duration longestProgressStall;
  final bool? playbackEndpointReachable;
  final LiveLinkHealthPenalties penalties;
}

class LiveLinkHealthSnapshot {
  const LiveLinkHealthSnapshot({
    required this.score,
    required this.level,
    required this.causes,
    required this.window,
    required this.hasEnoughData,
    required this.metrics,
    required this.suggestions,
  });

  /// Null while observation time or supported domains are insufficient.
  final int? score;
  final LiveLinkHealthLevel level;
  final List<LiveLinkHealthCause> causes;
  final Duration window;
  final bool hasEnoughData;
  final LiveLinkHealthMetrics metrics;
  final List<String> suggestions;

  LiveLinkHealthCause get primaryCause => causes.first;
}
