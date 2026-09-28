/// Layout choices and aspect-ratio helpers used by the live player.
///
/// Douyin's two-camera/game presentation is normally a single composited
/// stream.  These helpers deliberately only describe the containing video
/// surface; they do not imply that the stream can be split into two players.
enum LivePlayerLayoutMode {
  /// Follow the dimensions reported by the player (or the stream metadata).
  automatic('auto', '自动'),

  /// A portrait composited stream, normally arranged vertically.
  portraitDualScreen('portrait-dual-screen', '竖屏双屏'),

  /// A landscape composited stream, normally with a camera inset.
  landscapeDualScreen('landscape-dual-screen', '横屏双屏');

  const LivePlayerLayoutMode(this.storageValue, this.label);

  /// Stable textual value useful for profile exports and future migrations.
  final String storageValue;

  final String label;

  static const LivePlayerLayoutMode defaultMode =
      LivePlayerLayoutMode.automatic;

  /// Reads both the current numeric representation and textual values.
  ///
  /// Unknown values intentionally fall back to [defaultMode], so a newer
  /// client cannot make an older client fail during startup.
  static LivePlayerLayoutMode fromStorage(Object? value) {
    if (value is LivePlayerLayoutMode) {
      return value;
    }
    if (value is num && value.isFinite) {
      final index = value.toInt();
      return values.firstWhere(
        (mode) => values.indexOf(mode) == index,
        orElse: () => defaultMode,
      );
    }
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return defaultMode;
    }
    return values.firstWhere(
      (mode) => mode.storageValue == normalized ||
          mode.name.toLowerCase() == normalized,
      orElse: () => defaultMode,
    );
  }

  bool get isDualScreen => this != automatic;

  /// Aspect ratio forced by a manually selected dual-screen mode.
  double? get forcedAspectRatio {
    switch (this) {
      case automatic:
        return null;
      case portraitDualScreen:
        return 9 / 16;
      case landscapeDualScreen:
        return 16 / 9;
    }
  }
}

/// Parses a width/height pair into a valid aspect ratio.
///
/// Invalid, zero, and non-finite dimensions return `null`. Keeping this
/// function free of Flutter/media_kit types makes it usable by metadata
/// parsers and unit tests alike.
double? parseLivePlayerAspectRatio(Object? width, Object? height) {
  final parsedWidth = _parsePositiveNumber(width);
  final parsedHeight = _parsePositiveNumber(height);
  if (parsedWidth == null || parsedHeight == null) {
    return null;
  }
  final ratio = parsedWidth / parsedHeight;
  return ratio.isFinite && ratio > 0 ? ratio : null;
}

/// Parses common Douyin resolution representations such as `1920x1080`,
/// `1080*1920`, or a map containing `width` and `height`.
double? parseLivePlayerResolutionAspectRatio(Object? resolution) {
  if (resolution is Map) {
    final width = resolution['width'] ?? resolution['w'];
    final height = resolution['height'] ?? resolution['h'];
    final ratio = parseLivePlayerAspectRatio(width, height);
    if (ratio != null) {
      return ratio;
    }
    for (final key in const ['resolution', 'size', 'value']) {
      final nested = parseLivePlayerResolutionAspectRatio(resolution[key]);
      if (nested != null) {
        return nested;
      }
    }
  }

  if (resolution is Iterable) {
    final values = resolution.toList(growable: false);
    if (values.length >= 2) {
      final ratio = parseLivePlayerAspectRatio(values[0], values[1]);
      if (ratio != null) {
        return ratio;
      }
    }
  }

  final text = resolution?.toString().trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  final match = RegExp(
    r'(\d+(?:\.\d+)?)\s*[x×*/]\s*(\d+(?:\.\d+)?)',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) {
    return null;
  }
  return parseLivePlayerAspectRatio(match.group(1), match.group(2));
}

/// Resolves the display aspect ratio for a selected layout.
///
/// In automatic mode, the actual decoded dimensions win. Before the first
/// frame, resolution and orientation metadata provide a useful fallback.
/// `play` accepts either a scalar metadata value or a map; map values are
/// searched for common resolution/orientation keys.
double? resolveDualScreenAspectRatio({
  required LivePlayerLayoutMode mode,
  Object? videoWidth,
  Object? videoHeight,
  Object? resolution,
  String? streamOrientation,
  Object? play,
  Object? sdkParamsResolution,
}) {
  final forced = mode.forcedAspectRatio;
  if (forced != null) {
    return forced;
  }

  final actual = parseLivePlayerAspectRatio(videoWidth, videoHeight);
  if (actual != null) {
    return actual;
  }

  for (final candidate in [
    resolution,
    sdkParamsResolution,
    if (play is Map) play['resolution'],
    if (play is Map) play['size'],
    if (play is Map) play['width'] != null && play['height'] != null
        ? {'width': play['width'], 'height': play['height']}
        : null,
  ]) {
    final ratio = parseLivePlayerResolutionAspectRatio(candidate);
    if (ratio != null) {
      return ratio;
    }
  }

  final orientation = _orientationText(
    streamOrientation ?? (play is Map ? play['orientation']?.toString() : null),
  );
  if (orientation == _Orientation.portrait) {
    return 9 / 16;
  }
  if (orientation == _Orientation.landscape) {
    return 16 / 9;
  }
  return null;
}

/// Infers the dual-screen direction from a known aspect ratio or metadata.
/// Returns `null` when no reliable direction is available.
LivePlayerLayoutMode? inferDualScreenLayoutMode({
  Object? videoWidth,
  Object? videoHeight,
  Object? resolution,
  String? streamOrientation,
  Object? play,
  Object? sdkParamsResolution,
}) {
  final ratio = resolveDualScreenAspectRatio(
    mode: LivePlayerLayoutMode.automatic,
    videoWidth: videoWidth,
    videoHeight: videoHeight,
    resolution: resolution,
    streamOrientation: streamOrientation,
    play: play,
    sdkParamsResolution: sdkParamsResolution,
  );
  if (ratio == null) {
    return null;
  }
  return ratio < 1
      ? LivePlayerLayoutMode.portraitDualScreen
      : LivePlayerLayoutMode.landscapeDualScreen;
}

enum _Orientation { portrait, landscape }

_Orientation? _orientationText(String? value) {
  final text = value?.trim().toLowerCase() ?? '';
  if (text.isEmpty) {
    return null;
  }
  if (text.contains('portrait') ||
      text.contains('vertical') ||
      text.contains('竖') ||
      text.contains('垂直') ||
      text == 'v') {
    return _Orientation.portrait;
  }
  if (text.contains('landscape') ||
      text.contains('horizontal') ||
      text.contains('横') ||
      text.contains('水平') ||
      text == 'h') {
    return _Orientation.landscape;
  }
  return null;
}

double? _parsePositiveNumber(Object? value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  if (number == null || !number.isFinite || number <= 0) {
    return null;
  }
  return number;
}
