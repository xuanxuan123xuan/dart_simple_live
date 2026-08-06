/// The protocol or container detected from a live stream URL.
enum LiveStreamProtocol {
  flv,
  hls,
  fmp4,
  rtmp,
  unknown;

  /// A stable, log-friendly representation of this protocol.
  String get label => name;

  /// Lower values are preferred when choosing a live stream source.
  int get latencyPriority => switch (this) {
        LiveStreamProtocol.flv || LiveStreamProtocol.rtmp => 0,
        LiveStreamProtocol.fmp4 || LiveStreamProtocol.unknown => 1,
        LiveStreamProtocol.hls => 2,
      };
}

/// Classifies a live stream URL without inspecting or opening the stream.
///
/// Detection is deliberately conservative: RTMP schemes take precedence,
/// followed by an exact path extension and then explicit `format` or `type`
/// query parameters.
LiveStreamProtocol classifyLiveStreamProtocol(String? value) {
  final input = value?.trim();
  if (input == null || input.isEmpty) {
    return LiveStreamProtocol.unknown;
  }

  final uri = Uri.tryParse(input);
  if (uri == null || uri.host.isEmpty || uri.scheme.isEmpty) {
    return LiveStreamProtocol.unknown;
  }

  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'rtmp' || scheme == 'rtmps') {
    return LiveStreamProtocol.rtmp;
  }
  if (scheme != 'http' && scheme != 'https') {
    return LiveStreamProtocol.unknown;
  }

  final pathProtocol = _protocolFromPath(uri.pathSegments);
  if (pathProtocol != null) {
    return pathProtocol;
  }

  return _protocolFromQuery(uri) ?? LiveStreamProtocol.unknown;
}

/// Prefers lower-latency protocols while preserving the original CDN order
/// inside each protocol tier. No URL is removed.
List<String> sortLiveStreamUrlsByLatency(Iterable<String> urls) {
  final indexed = urls.indexed.toList();
  indexed.sort((left, right) {
    final priority = classifyLiveStreamProtocol(left.$2)
        .latencyPriority
        .compareTo(classifyLiveStreamProtocol(right.$2).latencyPriority);
    return priority != 0 ? priority : left.$1.compareTo(right.$1);
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

/// Returns all line indexes in the best available latency tier.
List<int> lowestLatencyLineIndices(Iterable<String> urls) {
  final values = urls.toList(growable: false);
  if (values.isEmpty) {
    return const [];
  }
  final bestPriority = values
      .map((url) => classifyLiveStreamProtocol(url).latencyPriority)
      .reduce((left, right) => left < right ? left : right);
  return [
    for (var index = 0; index < values.length; index += 1)
      if (classifyLiveStreamProtocol(values[index]).latencyPriority ==
          bestPriority)
        index,
  ];
}

LiveStreamProtocol? _protocolFromPath(List<String> pathSegments) {
  if (pathSegments.isEmpty) {
    return null;
  }

  final lastSegment = pathSegments.last.toLowerCase();
  if (lastSegment.endsWith('.flv')) {
    return LiveStreamProtocol.flv;
  }
  if (lastSegment.endsWith('.m3u8')) {
    return LiveStreamProtocol.hls;
  }
  if (lastSegment.endsWith('.fmp4') ||
      lastSegment.endsWith('.mp4') ||
      lastSegment.endsWith('.m4s')) {
    return LiveStreamProtocol.fmp4;
  }
  return null;
}

LiveStreamProtocol? _protocolFromQuery(Uri uri) {
  const queryKeys = ['format', 'type'];
  for (final queryKey in queryKeys) {
    for (final entry in uri.queryParametersAll.entries) {
      if (entry.key.toLowerCase() != queryKey) {
        continue;
      }
      for (final rawValue in entry.value) {
        final value = rawValue.trim().toLowerCase();
        switch (value) {
          case 'flv':
            return LiveStreamProtocol.flv;
          case 'hls':
          case 'm3u8':
            return LiveStreamProtocol.hls;
          case 'fmp4':
          case 'mp4':
            return LiveStreamProtocol.fmp4;
          case 'rtmp':
          case 'rtmps':
            return LiveStreamProtocol.rtmp;
        }
      }
    }
  }
  return null;
}
