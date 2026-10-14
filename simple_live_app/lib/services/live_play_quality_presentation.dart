import 'package:simple_live_core/simple_live_core.dart';

/// Separates the quality requested from the quality reported by the platform.
/// A null report preserves the existing requested-quality presentation.
class LivePlayQualityPresentation {
  factory LivePlayQualityPresentation({
    required String requestedQuality,
    required LivePlayQuality? actualQuality,
  }) {
    final requested = requestedQuality.trim();
    final actualName = actualQuality?.quality.trim();
    return LivePlayQualityPresentation._(
      requestedQuality: requested,
      actualQuality: actualQuality,
      actualQualityName: actualName?.isNotEmpty == true ? actualName : null,
      displayQuality: actualName?.isNotEmpty == true ? actualName! : requested,
    );
  }

  const LivePlayQualityPresentation._({
    required this.requestedQuality,
    required this.actualQuality,
    required this.actualQualityName,
    required this.displayQuality,
  });

  final String requestedQuality;
  final LivePlayQuality? actualQuality;
  final String? actualQualityName;
  final String displayQuality;

  bool get isMismatch =>
      actualQualityName != null && actualQualityName != requestedQuality;

  /// Only platforms that report actual quality need the extra menu annotation.
  String? get comparisonLabel {
    final actual = actualQualityName;
    if (actual == null) return null;
    return '请求：$requestedQuality · 实际：$actual';
  }

  String? get mismatchNotice {
    if (!isMismatch) return null;
    final actual = actualQualityName!;
    if (actual == '清晰度未确认') {
      return '请求$requestedQuality，实际清晰度未确认';
    }
    return '请求$requestedQuality，实际为$actual';
  }
}

/// Emits one notice per mismatch state and forgets it when playback recovers.
class LivePlayQualityMismatchTracker {
  String? _lastMismatchNotice;

  String? update(LivePlayQualityPresentation presentation) {
    final notice = presentation.mismatchNotice;
    if (notice == null) {
      reset();
      return null;
    }
    if (notice == _lastMismatchNotice) return null;
    _lastMismatchNotice = notice;
    return notice;
  }

  void reset() {
    _lastMismatchNotice = null;
  }
}

bool isCurrentMultiRoomQualityOperation({
  required int operationRevision,
  required int currentOperationRevision,
  required bool operationCancelled,
}) {
  return !operationCancelled && operationRevision == currentOperationRevision;
}

/// Resolve a queued selection against qualities refreshed while it waited.
/// Keep the named quality when possible, then use the nearest available level.
int? resolveMultiRoomQualityIndex({
  required LivePlayQuality requestedQuality,
  required int requestedIndex,
  required List<LivePlayQuality> availableQualities,
}) {
  if (availableQualities.isEmpty) return null;
  if (requestedIndex >= 0 &&
      requestedIndex < availableQualities.length &&
      availableQualities[requestedIndex].quality == requestedQuality.quality) {
    return requestedIndex;
  }
  final matchingIndex = availableQualities.indexWhere(
    (quality) => quality.quality == requestedQuality.quality,
  );
  if (matchingIndex >= 0) return matchingIndex;
  return requestedIndex.clamp(0, availableQualities.length - 1).toInt();
}
