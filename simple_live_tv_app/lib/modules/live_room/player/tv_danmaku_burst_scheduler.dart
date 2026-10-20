import 'dart:async';
import 'dart:collection';

import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:flutter/scheduler.dart';

/// Controls the amount of synchronous danmaku layout work performed by one
/// Flutter frame while a TV room is starting.
class TvDanmakuBurstScheduler {
  TvDanmakuBurstScheduler({
    required this.onBatch,
    required bool realtime,
    this.startupDelay = const Duration(milliseconds: 100),
    this.maxItemsPerFrame = 4,
    this.maxPendingItems = 120,
  })  : assert(maxItemsPerFrame > 0),
        assert(maxPendingItems > 0),
        _realtime = realtime;

  final void Function(List<DanmakuContentItem> items) onBatch;
  final Duration startupDelay;
  final int maxItemsPerFrame;
  final int maxPendingItems;

  final Queue<DanmakuContentItem> _pending = Queue<DanmakuContentItem>();
  Timer? _startupTimer;
  int? _frameCallbackId;
  bool _realtime;
  int _generation = 0;

  bool get realtime => _realtime;
  int get pendingCount => _pending.length;
  int get generation => _generation;

  set realtime(bool value) {
    if (_realtime == value) return;
    _realtime = value;
    if (value) {
      _startupTimer?.cancel();
      _startupTimer = null;
      _drainAllImmediately();
    }
  }

  /// Starts a new room/playback generation and delays the initial burst.
  void beginGeneration(int generation) {
    _generation = generation;
    _pending.clear();
    _startupTimer?.cancel();
    _startupTimer = null;
    if (!_realtime) {
      _startupTimer = Timer(startupDelay, () {
        _startupTimer = null;
        _scheduleFrame();
      });
    }
  }

  void add(DanmakuContentItem item, {int? generation}) {
    if (generation != null && generation != _generation) return;
    if (_realtime) {
      onBatch(<DanmakuContentItem>[item]);
      return;
    }

    if (_pending.length >= maxPendingItems) {
      _pending.removeFirst();
    }
    _pending.addLast(item);
    if (_startupTimer == null) _scheduleFrame();
  }

  void clear() {
    _pending.clear();
    _startupTimer?.cancel();
    _startupTimer = null;
    final callbackId = _frameCallbackId;
    if (callbackId != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(callbackId);
      _frameCallbackId = null;
    }
  }

  void dispose() {
    clear();
  }

  void _scheduleFrame() {
    if (_realtime || _frameCallbackId != null || _pending.isEmpty) return;
    _frameCallbackId = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameCallbackId = null;
      _drainFrame();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  void _drainFrame() {
    if (_realtime || _startupTimer != null || _pending.isEmpty) return;
    final count =
        _pending.length < maxItemsPerFrame ? _pending.length : maxItemsPerFrame;
    final batch = <DanmakuContentItem>[];
    for (var i = 0; i < count; i++) {
      batch.add(_pending.removeFirst());
    }
    onBatch(batch);
    if (_pending.isNotEmpty) _scheduleFrame();
  }

  void _drainAllImmediately() {
    if (_pending.isEmpty) return;
    final batch = _pending.toList(growable: false);
    _pending.clear();
    onBatch(batch);
  }
}
