import 'live_link_health_models.dart';
import 'live_link_health_tracker.dart';

/// Returns the minimum stable identity needed by generation gates.
///
/// Paths, user info, queries, fragments, and signed tokens are deliberately
/// discarded so the health layer never retains a complete playback URL.
String canonicalizeLivePlaybackSource(String source) {
  final uri = Uri.tryParse(source.trim());
  if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
    return '';
  }
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final authorityHost = host.contains(':') ? '[$host]' : host;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '$scheme://$authorityHost$port';
}

/// Compares only normalized URL hosts. No URL, path, query, or signature is
/// retained in the returned reconnect observation.
bool? didLivePlaybackHostChange(String? previousSource, String? nextSource) {
  final previousHost = _normalizedLivePlaybackHost(previousSource);
  final nextHost = _normalizedLivePlaybackHost(nextSource);
  if (previousHost == null || nextHost == null) {
    return null;
  }
  return previousHost != nextHost;
}

String? _normalizedLivePlaybackHost(String? source) {
  final uri = source == null ? null : Uri.tryParse(source.trim());
  final host = uri?.host.trim().toLowerCase();
  return host == null || host.isEmpty ? null : host;
}

/// Shadow-only coordinator for one live playback generation.
///
/// It deliberately owns no player controls. Callers provide lightweight
/// samples and may log the returned summary; stale generations are rejected
/// before they can reach [LiveLinkHealthTracker].
class LiveLinkHealthShadowCollector {
  LiveLinkHealthShadowCollector({
    LiveLinkHealthTracker? tracker,
    this.logInterval = const Duration(seconds: 5),
  }) : _tracker = tracker ?? LiveLinkHealthTracker();

  final LiveLinkHealthTracker _tracker;
  final Duration logInterval;

  int? _generation;
  String _target = 'unknown';
  DateTime? _lastLoggedAt;

  int? get generation => _generation;
  int get sampleCount => _tracker.sampleCount;
  int get eventCount => _tracker.eventCount;
  bool get isActive => _generation != null;

  void startGeneration({
    required int generation,
    required String target,
    DateTime? at,
  }) {
    _generation = generation;
    _target = target;
    _lastLoggedAt = null;
    _tracker.startGeneration(generation, at: at);
  }

  void stop() {
    _generation = null;
    _target = 'unknown';
    _lastLoggedAt = null;
    _tracker.reset();
  }

  bool addEvent(LiveLinkHealthEvent event) {
    if (event.generation != _generation) {
      return false;
    }
    _tracker.addEvent(event);
    return true;
  }

  /// Returns at most one shadow summary per [logInterval].
  String? addSample(LiveLinkHealthSample sample) {
    if (sample.generation != _generation) {
      return null;
    }
    _tracker.addSample(sample);
    final previousLog = _lastLoggedAt;
    if (previousLog != null &&
        sample.sampledAt.difference(previousLog) < logInterval) {
      return null;
    }
    _lastLoggedAt = sample.sampledAt;
    return formatLiveLinkHealthShadow(
      target: _target,
      generation: sample.generation,
      sample: sample,
      snapshot: _tracker.snapshot(at: sample.sampledAt),
    );
  }

  LiveLinkHealthSnapshot? snapshot({DateTime? at}) {
    if (_generation == null) {
      return null;
    }
    return _tracker.snapshot(at: at);
  }
}

String formatLiveLinkHealthShadow({
  required String target,
  required int generation,
  required LiveLinkHealthSample sample,
  required LiveLinkHealthSnapshot snapshot,
}) {
  final metrics = snapshot.metrics;
  return '[live-health] target=$target '
      'generation=$generation '
      'score=${snapshot.score?.toString() ?? 'unknown'} '
      'level=${snapshot.level.name} '
      'cause=${snapshot.primaryCause.name} '
      'cache=${_formatMetric(metrics.cacheSeconds, suffix: 's')} '
      'slope=${_formatMetric(metrics.cacheSlopeSecondsPerSecond, suffix: 's/s')} '
      'throughput=${_formatMetric(metrics.throughputRatio)} '
      'underruns60s=${_formatOptionalValue(metrics.audioUnderrunCount)} '
      'reconnects60s=${_formatOptionalValue(metrics.automaticReconnectCount)} '
      'reconnectHostChanged=${_formatOptionalValue(metrics.latestAutomaticReconnectHostChanged)} '
      'reconnectRecovery=${_formatOptionalDuration(metrics.latestAutomaticReconnectRecoveryDuration)} '
      'buffering=${sample.buffering} '
      'progress=${_formatMetric(metrics.normalizedProgressRatio)}';
}

String _formatMetric(double? value, {String suffix = ''}) {
  return value == null ? 'unknown' : '${value.toStringAsFixed(3)}$suffix';
}

String _formatOptionalValue(Object? value) => value?.toString() ?? 'unknown';

String _formatOptionalDuration(Duration? value) =>
    value == null ? 'unknown' : '${value.inMilliseconds}ms';
