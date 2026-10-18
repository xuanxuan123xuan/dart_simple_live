/// 独立缓冲开始次数的统计器（false->true 边沿计数）。
///
/// 供自动降画质与自动网络诊断各自持有独立实例复用同一套算法：
/// - 只按 `false -> true` 边沿计数，重复广播的 `true` 不重复计；
/// - 起播 warmup 内的缓冲不计入故障；
/// - 连续稳定或超出统计窗口后自动清零；
/// - 达到 [requiredBufferStarts] 后返回 true 并清零计数（触发一次动作）。
class LiveRoomAutoQualityBufferTracker {
  LiveRoomAutoQualityBufferTracker({
    this.requiredBufferStarts = 2,
    this.bufferingWindow = const Duration(seconds: 30),
    this.stableResetAfter = const Duration(seconds: 30),
    this.warmupDuration = const Duration(seconds: 8),
  });

  final int requiredBufferStarts;
  final Duration bufferingWindow;
  final Duration stableResetAfter;
  final Duration warmupDuration;

  int _bufferingStarts = 0;
  bool _isBuffering = false;
  DateTime? _lastBufferingStartedAt;
  DateTime? _stableSince;
  DateTime? _warmupUntil;

  /// 开始新流的 warmup 窗口：清零计数并在 [warmupDuration] 内忽略缓冲。
  void beginWarmup(DateTime now) {
    reset();
    _warmupUntil = now.add(warmupDuration);
  }

  /// 清零全部计数与边沿状态（换房/重开流时调用）。
  void reset() {
    _bufferingStarts = 0;
    _isBuffering = false;
    _lastBufferingStartedAt = null;
    _stableSince = null;
    _warmupUntil = null;
  }

  /// 传入一次 buffering 事件，返回是否达到触发阈值。
  /// 达到阈值时内部清零，下一次统计从零重新开始。
  bool update({required bool buffering, required DateTime now}) {
    if (!buffering) {
      if (_isBuffering) {
        _stableSince = now;
      }
      _isBuffering = false;
      return false;
    }
    // A stream may emit the same buffering value more than once. Count only
    // transitions into buffering.
    if (_isBuffering) {
      return false;
    }
    _isBuffering = true;

    final warmupUntil = _warmupUntil;
    if (warmupUntil != null && now.isBefore(warmupUntil)) {
      return false;
    }

    final stableSince = _stableSince;
    final lastStartedAt = _lastBufferingStartedAt;
    if ((stableSince != null &&
            now.difference(stableSince) >= stableResetAfter) ||
        (lastStartedAt != null &&
            now.difference(lastStartedAt) > bufferingWindow)) {
      _bufferingStarts = 0;
      _lastBufferingStartedAt = null;
    }

    _stableSince = null;
    _lastBufferingStartedAt = now;
    _bufferingStarts += 1;
    if (_bufferingStarts < requiredBufferStarts) {
      return false;
    }

    _bufferingStarts = 0;
    _lastBufferingStartedAt = null;
    return true;
  }
}
