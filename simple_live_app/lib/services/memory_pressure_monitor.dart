import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:simple_live_app/app/log.dart';

/// 多开低内存降级的监控器。
///
/// 周期采样当前进程 RSS（`ProcessInfo.currentRss`），超过阈值时回调触发
/// 降级（暂停非活跃格子弹幕 / 降画质），内存回落且持续时间足够后再恢复。
///
/// Dart 没有跨平台的物理内存总量 API，这里用绝对 RSS 阈值：
/// iPad 常见 4-8GB，4 路 mpv 的 RSS 到 1.2GB 已明显吃紧。
class MemoryPressureMonitor {
  MemoryPressureMonitor._();

  static final MemoryPressureMonitor instance = MemoryPressureMonitor._();

  /// 触发降级的 RSS 阈值（默认 1.2GB）。
  static const double _highRssBytes = 1.2 * 1024 * 1024 * 1024;

  /// 回落到该值以下且稳定多次才恢复（默认 0.9GB）。
  static const double _recoverRssBytes = 0.9 * 1024 * 1024 * 1024;

  static const int _recoverStableSamples = 5;

  static const Duration _sampleInterval = Duration(seconds: 5);

  Timer? _timer;
  bool _running = false;

  /// 当前是否处于降级状态。
  bool get isDegraded => _isDegraded;
  bool _isDegraded = false;

  /// 最近一次进程 RSS（字节），供调试/UI 展示。
  double get lastRssBytes => _lastRssBytes;
  double _lastRssBytes = 0;

  /// 触发降级（进入压力态）。
  VoidCallback? onDegrade;

  /// 内存回落，恢复（退出压力态）。
  VoidCallback? onRecover;

  int _recoverCount = 0;

  void start() {
    if (_running) return;
    _running = true;
    _timer?.cancel();
    _timer = Timer.periodic(_sampleInterval, (_) => _sample());
    _sample();
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  void _sample() {
    _lastRssBytes = ProcessInfo.currentRss.toDouble();

    if (_isDegraded) {
      if (_lastRssBytes < _recoverRssBytes) {
        _recoverCount += 1;
        if (_recoverCount >= _recoverStableSamples) {
          _isDegraded = false;
          _recoverCount = 0;
          Log.d("多开内存已回落 (${(_lastRssBytes / 1024 / 1024).toStringAsFixed(0)}MB)，恢复");
          onRecover?.call();
        }
      } else {
        _recoverCount = 0;
      }
      return;
    }

    if (_lastRssBytes >= _highRssBytes) {
      _isDegraded = true;
      _recoverCount = 0;
      Log.d("多开内存压力大 (${(_lastRssBytes / 1024 / 1024).toStringAsFixed(0)}MB)，触发降级");
      onDegrade?.call();
    }
  }
}
