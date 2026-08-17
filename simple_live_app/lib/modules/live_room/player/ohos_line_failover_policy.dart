/// Selects the next untried HarmonyOS CDN line in circular display order.
///
/// A line is tried at most once per playback-health session. Returning null
/// lets the caller fall back to quality degradation (when user policy allows
/// it) instead of cycling forever between the same unhealthy endpoints.
int? selectNextOhosFailoverLine({
  required int currentLineIndex,
  required int lineCount,
  required Set<int> failedLineIndices,
}) {
  if (lineCount <= 1 || currentLineIndex < 0 || currentLineIndex >= lineCount) {
    return null;
  }
  for (var offset = 1; offset < lineCount; offset += 1) {
    final candidate = (currentLineIndex + offset) % lineCount;
    if (!failedLineIndices.contains(candidate)) {
      return candidate;
    }
  }
  return null;
}
