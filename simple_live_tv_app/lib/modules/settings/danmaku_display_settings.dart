/// Shared values and normalization for TV danmaku layout preferences.
class DanmakuDisplaySettings {
  static const String areaMode = 'area';
  static const String linesMode = 'lines';

  static const String defaultMode = areaMode;
  static const int defaultMaxLines = 3;
  static const int minLines = 1;
  static const int maxLines = 6;

  static const Map<String, String> modeItems = {
    areaMode: '按区域',
    linesMode: '按行数',
  };

  static final Map<double, String> areaItems = Map.unmodifiable({
    0.25: '1/4',
    0.5: '1/2',
    0.75: '3/4',
    1.0: '全屏',
  });

  static const Map<int, String> maxLinesItems = {
    1: '1行',
    2: '2行',
    3: '3行',
    4: '4行',
    5: '5行',
    6: '6行',
  };

  static String normalizeMode(Object? value) =>
      value == linesMode ? linesMode : areaMode;

  static int normalizeMaxLines(Object? value) {
    if (value is int && value >= minLines && value <= maxLines) {
      return value;
    }
    return defaultMaxLines;
  }

  /// Returns zero when area mode is active; the danmaku engine uses zero to
  /// select its area-based track limit.
  static int effectiveMaxLines({
    required Object? mode,
    required Object? maxLines,
  }) {
    if (normalizeMode(mode) != linesMode) return 0;
    return normalizeMaxLines(maxLines);
  }
}
