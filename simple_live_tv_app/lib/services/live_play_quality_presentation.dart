import 'package:simple_live_core/simple_live_core.dart';

/// Keeps the requested quality separate from the quality reported with a URL.
class LivePlayQualityPresentation {
  LivePlayQualityPresentation({
    required LivePlayQuality requestedQuality,
    required LivePlayQuality? actualQuality,
  })  : requested = requestedQuality.quality.trim(),
        actual = actualQuality?.quality.trim().isNotEmpty == true
            ? actualQuality!.quality.trim()
            : null;

  final String requested;
  final String? actual;

  String get display => actual ?? requested;
  bool get isMismatch => actual != null && actual != requested;

  String? get mismatchNotice =>
      isMismatch ? '请求清晰度：$requested，实际：$actual' : null;

  String get comparison => actual == null || actual == requested
      ? display
      : '请求 $requested / 实际 $actual';
}

/// Emits each new mismatch once and rearms after quality matches again.
class LivePlayQualityMismatchTracker {
  String? _lastMismatchNotice;

  String? update(LivePlayQualityPresentation quality) {
    final notice = quality.mismatchNotice;
    if (notice == null) {
      reset();
      return null;
    }
    if (_lastMismatchNotice == notice) return null;
    _lastMismatchNotice = notice;
    return notice;
  }

  void reset() => _lastMismatchNotice = null;
}
