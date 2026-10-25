import 'dart:math' as math;

/// Returns a sampled overlay frame between [current] and [next] when it is
/// safe to interpolate their continuous item properties.
///
/// Items are emitted from [current] only. This keeps births and disappearances
/// aligned with the timestamp of the snapshot that contains the change.
Map<String, dynamic>? interpolateRecordingOverlayFrame(
  Map<String, dynamic>? current,
  Map<String, dynamic>? next,
  double mediaMs,
) {
  if (current == null || !mediaMs.isFinite) return current;

  final currentTime = _finiteNumber(current['positionMs']);
  final nextTime = next == null ? null : _finiteNumber(next['positionMs']);
  if (next == null || currentTime == null || nextTime == null) return current;

  // Snapshots take effect at their own timestamp, including discrete item
  // births. An empty current frame still stays empty before the first snapshot.
  if (mediaMs == nextTime) return next;
  if (mediaMs == currentTime || mediaMs < currentTime || mediaMs > nextTime) {
    return current;
  }

  final gapMs = nextTime - currentTime;
  if (gapMs <= 0 || gapMs > _maximumInterpolationGapMs) return current;

  final currentViewport = _viewport(current);
  final nextViewport = _viewport(next);
  if (currentViewport == null ||
      nextViewport == null ||
      !_sameViewport(currentViewport, nextViewport)) {
    return current;
  }

  final currentItems = _items(current);
  final nextItems = _items(next);
  if (currentItems == null || nextItems == null) return current;

  final fraction = (mediaMs - currentTime) / gapMs;
  final matches = _matchItems(
    currentItems,
    nextItems,
    gapMs: gapMs,
    viewportWidth: currentViewport.canvasWidth,
  );

  final outputItems = <dynamic>[];
  var interpolatedAnyItem = false;
  for (var index = 0; index < currentItems.length; index++) {
    final currentItem = currentItems[index];
    if (currentItem is! Map<String, dynamic>) return current;

    final nextIndex = matches[index];
    if (nextIndex == null) {
      outputItems.add(Map<String, dynamic>.from(currentItem));
      continue;
    }

    final nextItem = nextItems[nextIndex];
    if (nextItem is! Map<String, dynamic>) return current;

    final outputItem = Map<String, dynamic>.from(currentItem);
    var interpolatedThisItem = false;
    for (final field in const ['x', 'y']) {
      final value = _interpolateNumber(
        currentItem[field],
        nextItem[field],
        fraction,
      );
      if (value != null) {
        outputItem[field] = value;
        interpolatedThisItem = true;
      }
    }

    final opacity = _interpolateNumber(
      currentItem['opacity'] ?? 1,
      nextItem['opacity'] ?? 1,
      fraction,
    );
    if (opacity != null) {
      outputItem['opacity'] = opacity;
      interpolatedThisItem = true;
    }

    final currentTransform = _matrix(currentItem['transform']);
    final nextTransform = _matrix(nextItem['transform']);
    if (currentTransform != null && nextTransform != null) {
      final transform = _interpolateMatrix(
        currentTransform,
        nextTransform,
        fraction,
      );
      if (transform != null) {
        outputItem['transform'] = transform;
        interpolatedThisItem = true;
      }
    }

    outputItems.add(outputItem);
    interpolatedAnyItem = interpolatedAnyItem || interpolatedThisItem;
  }

  if (!interpolatedAnyItem) return current;
  return <String, dynamic>{
    ...current,
    'positionMs': mediaMs,
    'items': outputItems,
  };
}

const double _maximumInterpolationGapMs = 100;

double? _finiteNumber(dynamic value) {
  if (value is! num) return null;
  final number = value.toDouble();
  return number.isFinite ? number : null;
}

double? _interpolateNumber(dynamic from, dynamic to, double fraction) {
  final start = _finiteNumber(from);
  final end = _finiteNumber(to);
  if (start == null || end == null) return null;
  final result = _lerp(start, end, fraction);
  return result.isFinite ? result : null;
}

double _lerp(double from, double to, double fraction) =>
    from + (to - from) * fraction;

class _Viewport {
  const _Viewport({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.videoLeft,
    required this.videoTop,
    required this.videoWidth,
    required this.videoHeight,
    required this.groupOpacity,
  });

  final double canvasWidth;
  final double canvasHeight;
  final double videoLeft;
  final double videoTop;
  final double videoWidth;
  final double videoHeight;
  final double groupOpacity;
}

_Viewport? _viewport(Map<String, dynamic> frame) {
  final canvasWidth = _finiteNumber(frame['canvasWidth']);
  final canvasHeight = _finiteNumber(frame['canvasHeight']);
  if (canvasWidth == null ||
      canvasHeight == null ||
      canvasWidth <= 0 ||
      canvasHeight <= 0) {
    return null;
  }

  final videoLeft = _optionalNumber(frame, 'videoLeft', 0);
  final videoTop = _optionalNumber(frame, 'videoTop', 0);
  final videoWidth = _optionalNumber(frame, 'videoWidth', canvasWidth);
  final videoHeight = _optionalNumber(frame, 'videoHeight', canvasHeight);
  final groupOpacity = _optionalNumber(frame, 'opacity', 1);
  if (videoLeft == null ||
      videoTop == null ||
      videoWidth == null ||
      videoHeight == null ||
      groupOpacity == null ||
      videoWidth <= 0 ||
      videoHeight <= 0) {
    return null;
  }

  return _Viewport(
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
    videoLeft: videoLeft,
    videoTop: videoTop,
    videoWidth: videoWidth,
    videoHeight: videoHeight,
    groupOpacity: groupOpacity,
  );
}

double? _optionalNumber(
  Map<String, dynamic> frame,
  String field,
  double defaultValue,
) {
  final value = frame[field];
  return value == null ? defaultValue : _finiteNumber(value);
}

bool _sameViewport(_Viewport a, _Viewport b) =>
    a.canvasWidth == b.canvasWidth &&
    a.canvasHeight == b.canvasHeight &&
    a.videoLeft == b.videoLeft &&
    a.videoTop == b.videoTop &&
    a.videoWidth == b.videoWidth &&
    a.videoHeight == b.videoHeight &&
    a.groupOpacity == b.groupOpacity;

List<dynamic>? _items(Map<String, dynamic> frame) {
  final value = frame['items'];
  return value is List<dynamic> ? value : null;
}

List<int?> _matchItems(
  List<dynamic> currentItems,
  List<dynamic> nextItems, {
  required double gapMs,
  required double viewportWidth,
}) {
  final matches = List<int?>.filled(currentItems.length, null);
  final usedNext = <int>{};
  final currentById = _uniqueInstanceIds(currentItems);
  final nextById = _uniqueInstanceIds(nextItems);

  for (final entry in currentById.entries) {
    final nextIndex = nextById[entry.key];
    if (nextIndex == null) continue;
    final currentItem = currentItems[entry.value];
    final nextItem = nextItems[nextIndex];
    if (currentItem is! Map<String, dynamic> ||
        nextItem is! Map<String, dynamic> ||
        !_sameItemLayout(currentItem, nextItem)) {
      continue;
    }
    matches[entry.value] = nextIndex;
    usedNext.add(nextIndex);
  }

  final legacyCurrent = <int>[];
  for (var index = 0; index < currentItems.length; index++) {
    if (matches[index] != null) continue;
    final item = currentItems[index];
    if (item is Map<String, dynamic> &&
        _instanceId(item) == null &&
        _legacyPosition(item) != null) {
      legacyCurrent.add(index);
    }
  }
  final legacyNext = <int>[];
  for (var index = 0; index < nextItems.length; index++) {
    if (usedNext.contains(index)) continue;
    final item = nextItems[index];
    if (item is Map<String, dynamic> &&
        _instanceId(item) == null &&
        _legacyPosition(item) != null) {
      legacyNext.add(index);
    }
  }

  final currentNeighbors = <int, _Nearest>{};
  final nextNeighbors = <int, _Nearest>{};
  final nextPositions = {
    for (final index in legacyNext)
      index: _legacyPosition(nextItems[index] as Map<String, dynamic>)!,
  };
  for (final currentIndex in legacyCurrent) {
    final currentItem = currentItems[currentIndex] as Map<String, dynamic>;
    final currentPosition = _legacyPosition(currentItem)!;
    final width = _finiteNumber(currentItem['width'])!;
    final movementLimit = _legacyMovementLimit(width, viewportWidth, gapMs);

    for (final nextIndex in legacyNext) {
      final nextItem = nextItems[nextIndex] as Map<String, dynamic>;
      if (!_sameItemLayout(currentItem, nextItem)) continue;
      final nextPosition = nextPositions[nextIndex]!;
      final distance = _distance(currentPosition, nextPosition);
      if (!distance.isFinite || distance > movementLimit) continue;
      currentNeighbors
          .putIfAbsent(currentIndex, _Nearest.new)
          .consider(nextIndex, distance);
      nextNeighbors
          .putIfAbsent(nextIndex, _Nearest.new)
          .consider(currentIndex, distance);
    }
  }

  for (final entry in currentNeighbors.entries) {
    final nextIndex = entry.value.uniqueIndex;
    if (nextIndex == null) continue;
    final nearestCurrent = nextNeighbors[nextIndex]?.uniqueIndex;
    if (nearestCurrent == entry.key) matches[entry.key] = nextIndex;
  }
  return matches;
}

Map<String, int> _uniqueInstanceIds(List<dynamic> items) {
  final occurrences = <String, List<int>>{};
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    if (item is! Map<String, dynamic>) continue;
    final id = _instanceId(item);
    if (id != null) occurrences.putIfAbsent(id, () => <int>[]).add(index);
  }
  return <String, int>{
    for (final entry in occurrences.entries)
      if (entry.value.length == 1) entry.key: entry.value.single,
  };
}

String? _instanceId(Map<String, dynamic> item) {
  final value = item['instanceId'];
  return value is String && value.isNotEmpty ? value : null;
}

bool _sameItemLayout(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aSpriteId = a['spriteId'];
  if (aSpriteId is! String || aSpriteId.isEmpty || aSpriteId != b['spriteId']) {
    return false;
  }
  return _samePositiveNumber(a['width'], b['width']) &&
      _samePositiveNumber(a['height'], b['height']) &&
      _sameFiniteNumber(
          a['transformOriginX'] ?? 0, b['transformOriginX'] ?? 0) &&
      _sameFiniteNumber(a['transformOriginY'] ?? 0, b['transformOriginY'] ?? 0);
}

bool _samePositiveNumber(dynamic a, dynamic b) {
  final first = _finiteNumber(a);
  final second = _finiteNumber(b);
  return first != null && second != null && first > 0 && first == second;
}

bool _sameFiniteNumber(dynamic a, dynamic b) {
  final first = _finiteNumber(a);
  final second = _finiteNumber(b);
  return first != null && second != null && first == second;
}

({double x, double y})? _legacyPosition(Map<String, dynamic> item) {
  if (!_hasLegacyLayout(item)) return null;
  final x = _finiteNumber(item['x']);
  final y = _finiteNumber(item['y']);
  if (x == null || y == null) return null;
  return (x: x, y: y);
}

bool _hasLegacyLayout(Map<String, dynamic> item) {
  final spriteId = item['spriteId'];
  final width = _finiteNumber(item['width']);
  final height = _finiteNumber(item['height']);
  final originX = _finiteNumber(item['transformOriginX'] ?? 0);
  final originY = _finiteNumber(item['transformOriginY'] ?? 0);
  return spriteId is String &&
      spriteId.isNotEmpty &&
      width != null &&
      width > 0 &&
      height != null &&
      height > 0 &&
      originX != null &&
      originY != null;
}

double _distance(({double x, double y}) a, ({double x, double y}) b) {
  final x = a.x - b.x;
  final y = a.y - b.y;
  return math.sqrt(x * x + y * y);
}

double _legacyMovementLimit(
    double itemWidth, double viewportWidth, double gapMs) {
  final scaledViewportMovement = viewportWidth * gapMs / 250;
  final contentMovement = itemWidth * .45;
  final boundedMovement = contentMovement < scaledViewportMovement
      ? contentMovement
      : scaledViewportMovement;
  return boundedMovement < 8 ? 8 : boundedMovement;
}

List<double>? _matrix(dynamic value) {
  if (value is! List<dynamic> || value.length != 16) return null;
  final result = <double>[];
  for (final entry in value) {
    final number = _finiteNumber(entry);
    if (number == null) return null;
    result.add(number);
  }
  return result;
}

List<double>? _interpolateMatrix(
  List<double> from,
  List<double> to,
  double fraction,
) {
  final result = List<double>.generate(
    16,
    (index) => _lerp(from[index], to[index], fraction),
    growable: false,
  );
  return result.every((value) => value.isFinite) ? result : null;
}

/// Keeps only the nearest candidate, avoiding allocations for every pair.
class _Nearest {
  int? _index;
  double _distance = double.infinity;
  bool _tied = false;

  int? get uniqueIndex => _tied ? null : _index;

  void consider(int index, double distance) {
    if ((distance - _distance).abs() <= 1e-9) {
      _tied = true;
      _distance = math.min(_distance, distance);
    } else if (distance < _distance) {
      _index = index;
      _distance = distance;
      _tied = false;
    }
  }
}
