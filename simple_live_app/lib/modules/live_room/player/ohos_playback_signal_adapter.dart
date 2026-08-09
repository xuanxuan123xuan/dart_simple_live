import 'package:video_player/video_player.dart';

enum OhosPlaybackSignalType {
  initialized,
  firstFrame,
  playing,
  bufferingStarted,
  bufferingEnded,
  positionAdvanced,
  nativeError,
  mediaHttpError,
  sourceAssigned,
  sourceReopened,
  disposed,
}

class OhosPlaybackSupportedMetrics {
  const OhosPlaybackSupportedMetrics({
    this.initialized = true,
    this.playing = true,
    this.buffering = true,
    this.position = true,
    this.nativeError = true,
    this.mediaHttpError = false,
    this.cacheDepth = false,
    this.throughput = false,
    this.audioUnderrun = false,
  });

  final bool initialized;
  final bool playing;
  final bool buffering;
  final bool position;
  final bool nativeError;
  final bool mediaHttpError;
  final bool cacheDepth;
  final bool throughput;
  final bool audioUnderrun;
}

class OhosPlaybackSignal {
  const OhosPlaybackSignal({
    required this.type,
    required this.roomGeneration,
    required this.playerGeneration,
    required this.occurredAt,
    required this.sourceFingerprint,
    required this.supportedMetrics,
    this.nativeErrorCode,
  });

  final OhosPlaybackSignalType type;
  final int roomGeneration;
  final int playerGeneration;
  final DateTime occurredAt;
  final String sourceFingerprint;
  final OhosPlaybackSupportedMetrics supportedMetrics;
  final String? nativeErrorCode;
}

/// Converts OHOS video_player values into discrete, generation-scoped events.
///
/// The adapter deliberately stores only a deterministic fingerprint of the
/// source. Full playback URLs and signed query parameters never enter events.
class OhosPlaybackSignalAdapter {
  OhosPlaybackSignalAdapter({
    this.supportedMetrics = const OhosPlaybackSupportedMetrics(),
  });

  final OhosPlaybackSupportedMetrics supportedMetrics;

  int? _roomGeneration;
  int? _playerGeneration;
  String _sourceFingerprint = '';
  VideoPlayerValue? _previousValue;
  bool _firstFrameEmitted = false;
  bool _disposed = false;

  bool get isActive => !_disposed && _playerGeneration != null;

  OhosPlaybackSignal beginSource({
    required int roomGeneration,
    required int playerGeneration,
    required String source,
    DateTime? at,
  }) {
    _roomGeneration = roomGeneration;
    _playerGeneration = playerGeneration;
    _sourceFingerprint = fingerprintOhosPlaybackSource(source);
    _previousValue = null;
    _firstFrameEmitted = false;
    _disposed = false;
    return _signal(OhosPlaybackSignalType.sourceAssigned, at: at);
  }

  List<OhosPlaybackSignal> update({
    required int roomGeneration,
    required int playerGeneration,
    required VideoPlayerValue value,
    DateTime? at,
  }) {
    if (!_matches(roomGeneration, playerGeneration)) {
      return const [];
    }

    final previous = _previousValue;
    final signals = <OhosPlaybackSignal>[];
    if (value.isInitialized && previous?.isInitialized != true) {
      signals.add(_signal(OhosPlaybackSignalType.initialized, at: at));
    }
    if (value.isBuffering != (previous?.isBuffering ?? false)) {
      signals.add(
        _signal(
          value.isBuffering
              ? OhosPlaybackSignalType.bufferingStarted
              : OhosPlaybackSignalType.bufferingEnded,
          at: at,
        ),
      );
    }
    if (value.isPlaying && previous?.isPlaying != true) {
      signals.add(_signal(OhosPlaybackSignalType.playing, at: at));
    }
    if (previous != null && value.position > previous.position) {
      signals.add(_signal(OhosPlaybackSignalType.positionAdvanced, at: at));
    }
    if (!_firstFrameEmitted &&
        value.isInitialized &&
        !value.isBuffering &&
        (value.position > Duration.zero || value.isPlaying)) {
      _firstFrameEmitted = true;
      signals.add(_signal(OhosPlaybackSignalType.firstFrame, at: at));
    }
    if (value.hasError && previous?.hasError != true) {
      signals.add(
        _signal(
          OhosPlaybackSignalType.nativeError,
          at: at,
          nativeErrorCode: sanitizeOhosNativeError(value.errorDescription),
        ),
      );
    }
    _previousValue = value;
    return signals;
  }

  OhosPlaybackSignal? markSourceReopened({
    required int roomGeneration,
    required int playerGeneration,
    DateTime? at,
  }) {
    if (!_matches(roomGeneration, playerGeneration)) {
      return null;
    }
    return _signal(OhosPlaybackSignalType.sourceReopened, at: at);
  }

  OhosPlaybackSignal? markMediaHttpError({
    required int roomGeneration,
    required int playerGeneration,
    required int statusCode,
    DateTime? at,
  }) {
    if (!_matches(roomGeneration, playerGeneration)) {
      return null;
    }
    return _signal(
      OhosPlaybackSignalType.mediaHttpError,
      at: at,
      nativeErrorCode: statusCode.toString(),
    );
  }

  OhosPlaybackSignal? dispose({
    required int roomGeneration,
    required int playerGeneration,
    DateTime? at,
  }) {
    if (!_matches(roomGeneration, playerGeneration)) {
      return null;
    }
    final signal = _signal(OhosPlaybackSignalType.disposed, at: at);
    _disposed = true;
    _previousValue = null;
    return signal;
  }

  bool _matches(int roomGeneration, int playerGeneration) {
    return !_disposed &&
        roomGeneration == _roomGeneration &&
        playerGeneration == _playerGeneration;
  }

  OhosPlaybackSignal _signal(
    OhosPlaybackSignalType type, {
    DateTime? at,
    String? nativeErrorCode,
  }) {
    return OhosPlaybackSignal(
      type: type,
      roomGeneration: _roomGeneration!,
      playerGeneration: _playerGeneration!,
      occurredAt: at ?? DateTime.now(),
      sourceFingerprint: _sourceFingerprint,
      supportedMetrics: supportedMetrics,
      nativeErrorCode: nativeErrorCode,
    );
  }
}

String fingerprintOhosPlaybackSource(String source) {
  final uri = Uri.tryParse(source.trim());
  if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
    return '';
  }
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path;
  final value = '$scheme://$host$port$path';
  var hash = 0xcbf29ce484222325;
  for (final byte in value.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String? sanitizeOhosNativeError(String? description) {
  if (description == null || description.trim().isEmpty) {
    return null;
  }
  final status = RegExp(r'\b(?:4|5)\d{2}\b').firstMatch(description);
  if (status != null) {
    return status.group(0);
  }
  final nativeCode = RegExp(r'\b\d{5,10}\b').firstMatch(description);
  return nativeCode?.group(0) ?? 'native_error';
}
