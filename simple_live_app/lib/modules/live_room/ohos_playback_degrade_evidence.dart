/// 鸿蒙线路降级/切换的证据门槛。
///
/// 与 [LiveRoomAutoQualityBufferTracker] 的纯边沿计数不同，这里要求缓冲“确实
/// 影响了观看”才允许触发切线路。原因：鸿蒙 AVPlayer 在 HTTP-FLV 直播下会因为
/// 关键帧对齐、cache 抖动等发出很短的 buffering 脉冲，两次这样的脉冲并不代表
/// 线路有问题；而切线路本身会重建播放器、让用户看到整屏 loading，代价远高于
/// 一次几百毫秒的缓冲。
///
/// 满足以下任一条件才算证据充分：
/// - 窗口内累计缓冲时长达到 [requiredAccumulatedBuffering]；
/// - 单次连续缓冲达到 [requiredContinuousBuffering]；
/// - 窗口内缓冲开始次数达到 [requiredBufferStarts]。
class OhosPlaybackDegradeEvidence {
  OhosPlaybackDegradeEvidence({
    this.window = const Duration(seconds: 30),
    this.requiredAccumulatedBuffering = const Duration(seconds: 6),
    this.requiredContinuousBuffering = const Duration(seconds: 5),
    this.requiredBufferStarts = 4,
    this.warmupDuration = const Duration(seconds: 8),
    this.stableResetAfter = const Duration(seconds: 30),
  });

  /// 统计窗口长度。
  final Duration window;

  /// 窗口内累计缓冲时长阈值。
  final Duration requiredAccumulatedBuffering;

  /// 单次连续缓冲时长阈值。
  final Duration requiredContinuousBuffering;

  /// 窗口内缓冲开始次数阈值。
  final int requiredBufferStarts;

  /// 起播预热窗口，期间的缓冲属于正常起播行为，不计入证据。
  final Duration warmupDuration;

  /// 连续稳定多久后清空既有证据。
  final Duration stableResetAfter;

  final List<_BufferingInterval> _intervals = <_BufferingInterval>[];
  bool _isBuffering = false;
  DateTime? _stableSince;
  DateTime? _warmupUntil;

  /// 开始新流的预热窗口：清空证据并在 [warmupDuration] 内忽略缓冲。
  void beginWarmup(DateTime now) {
    reset();
    _warmupUntil = now.add(warmupDuration);
  }

  /// 清空全部证据与边沿状态（换房/换线路/重开流时调用）。
  void reset() {
    _intervals.clear();
    _isBuffering = false;
    _stableSince = null;
    _warmupUntil = null;
  }

  /// 当前窗口内累计的缓冲时长，用于日志与测试观察。
  Duration accumulatedBuffering(DateTime now) {
    var total = Duration.zero;
    for (final interval in _intervals) {
      total += interval.durationAt(now);
    }
    return total;
  }

  /// 当前窗口内的缓冲开始次数，用于日志与测试观察。
  int bufferStarts(DateTime now) {
    _prune(now);
    return _intervals.length;
  }

  /// 传入一次 buffering 采样，返回证据是否已充分到可以切线路/降画质。
  ///
  /// 返回 true 时内部清空证据，下一轮重新累积，避免同一段抖动反复触发。
  bool update({required bool buffering, required DateTime now}) {
    _prune(now);

    if (!buffering) {
      final wasBuffering = _isBuffering;
      if (wasBuffering) {
        _closeCurrentInterval(now);
        _stableSince = now;
      }
      _isBuffering = false;
      // 长时间稳定播放说明线路已恢复，旧证据不该继续压在下一次抖动上。
      final stableSince = _stableSince;
      if (stableSince != null &&
          now.difference(stableSince) >= stableResetAfter) {
        _intervals.clear();
        _stableSince = now;
        return false;
      }
      // 缓冲刚结束时必须在这里判一次。鸿蒙只在状态变化时喂采样，一段
      // “开始→结束”的缓冲只有两次采样；若只在开始边沿判定，一次很长的
      // 卡顿要等到下一次缓冲开始才被发现。
      if (!wasBuffering || !_hasEnoughEvidence(now)) {
        return false;
      }
      _intervals.clear();
      _stableSince = null;
      return true;
    }

    final warmupUntil = _warmupUntil;
    if (warmupUntil != null && now.isBefore(warmupUntil)) {
      // 预热期内的缓冲不留证据，但仍要记住状态，否则预热结束后的同一段缓冲
      // 会被当成一次新的开始。
      _isBuffering = true;
      return false;
    }

    _stableSince = null;
    if (_isBuffering) {
      // 同一段缓冲的后续采样：延长它，而不是记成新的一次。
      if (_intervals.isNotEmpty) {
        _intervals.last.end = now;
      } else {
        // 预热期开始、预热后才被观察到的缓冲：从此刻起算。
        _intervals.add(_BufferingInterval(start: now));
      }
    } else {
      _isBuffering = true;
      _intervals.add(_BufferingInterval(start: now));
    }

    if (!_hasEnoughEvidence(now)) {
      return false;
    }
    _intervals.clear();
    _stableSince = null;
    return true;
  }

  bool _hasEnoughEvidence(DateTime now) {
    if (_intervals.length >= requiredBufferStarts) {
      return true;
    }
    if (accumulatedBuffering(now) >= requiredAccumulatedBuffering) {
      return true;
    }
    for (final interval in _intervals) {
      if (interval.durationAt(now) >= requiredContinuousBuffering) {
        return true;
      }
    }
    return false;
  }

  void _closeCurrentInterval(DateTime now) {
    if (_intervals.isEmpty) {
      return;
    }
    final last = _intervals.last;
    if (last.end == null || last.end!.isBefore(now)) {
      last.end = now;
    }
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(window);
    _intervals.removeWhere((interval) {
      final end = interval.end;
      // 未结束的缓冲一直有效：它正是当下的问题。
      return end != null && end.isBefore(cutoff);
    });
  }
}

class _BufferingInterval {
  _BufferingInterval({required this.start});

  final DateTime start;
  DateTime? end;

  Duration durationAt(DateTime now) {
    final resolvedEnd = end ?? now;
    final duration = resolvedEnd.difference(start);
    return duration.isNegative ? Duration.zero : duration;
  }
}
