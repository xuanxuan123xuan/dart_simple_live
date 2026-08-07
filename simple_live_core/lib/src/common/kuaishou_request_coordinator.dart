import 'dart:async';
import 'dart:math' as math;

import 'core_log.dart';

/// 快手请求优先级（数值越小越先执行）。
///
/// 依据《快手直播请求频率限制设计》9.2：
/// 用户主动进房 > 播放恢复 > 弹幕凭证 > 当前房间状态 > 关注后台刷新。
enum KuaishouRequestPriority {
  /// 用户主动进房（点击房间卡片、手动解析）。
  userEnter(0),

  /// 播放恢复 / 播放链路内的凭证补齐。
  playbackRecovery(1),

  /// 弹幕凭证解析。
  danmakuCredential(2),

  /// 当前房间状态轮询 / 复核。
  roomStatus(3),

  /// 关注列表后台状态刷新。
  followRefresh(4);

  const KuaishouRequestPriority(this.order);

  /// 数值越小优先级越高。
  final int order;
}

/// 快手进程级请求协调器。
///
/// 解决三份设计共同指出的问题：快手风控敏感请求没有全局调度与预算。
/// 本协调器为房间详情、websocketinfo 等敏感请求提供：
///
/// 1. **优先级队列**：后台关注刷新让路，用户主动进房优先；
/// 2. **最小间隔 + 抖动**：避免多开格子和关注刷新背靠背形成固定节奏；
/// 3. **同 key pending 合并**：同一 roomId 的排队/在途请求复用同一个 Future，
///    同房多入口只产生一条网络链路；
/// 4. **短 TTL 成功缓存**：短窗口内复用成功结果，失败结果不缓存；
/// 5. **冷却状态**：识别限流后暂停后台任务（阶段 2 接入，本类提供状态位）。
///
/// 保持纯 core 逻辑：可注入 [nowProvider] 与 [random] 便于测试。
class KuaishouRequestCoordinator {
  KuaishouRequestCoordinator({
    DateTime Function()? nowProvider,
    math.Random? random,
    this.minInterval = const Duration(milliseconds: 300),
    this.maxJitter = const Duration(milliseconds: 150),
  })  : _now = nowProvider ?? DateTime.now,
        _random = random ?? math.Random();

  /// 相邻两次敏感请求之间的最小间隔。
  final Duration minInterval;

  /// 最小间隔上的随机抖动上界，打破固定节奏。
  final Duration maxJitter;

  final DateTime Function() _now;
  final math.Random _random;

  final List<_QueuedRequest> _queue = [];
  final Map<String, _QueuedRequest> _pending = {};
  final Map<String, Future<Object?>> _inFlight = {};
  final Set<_QueuedRequest> _running = {};
  final Map<String, _CacheEntry> _cache = {};

  bool _pumping = false;
  DateTime? _lastRequestAt;

  /// 会话代次：reset 时递增，用于丢弃旧代次请求的结果与缓存写入。
  int _epoch = 0;

  /// 全局冷却：为 true 时后台请求直接失败，仅用户主动请求可放行。
  bool _cooldownActive = false;
  DateTime? _cooldownUntil;
  bool _cooldownProbeClaimed = false;

  /// 当前队列长度（观测用）。
  int get queuedCount => _queue.length;

  /// 当前在途请求数（观测用）。
  int get inFlightCount => _inFlight.length;

  /// 是否有生效中的冷却（观测用）。
  bool get inCooldown =>
      _cooldownActive &&
      (_cooldownUntil == null || _cooldownUntil!.isAfter(_now()));

  /// 开始全局冷却。冷却期内除 [KuaishouRequestPriority.userEnter] 外的
  /// 请求直接以 [KuaishouCooldownError] 失败；用户主动进房仍可放行单探针。
  ///
  /// 已处于冷却时取更长剩余时长，避免较短的冷却（如 403→2min）覆盖
  /// 较长的冷却（如 429→5min）。
  void beginCooldown(Duration duration) {
    final now = _now();
    final currentUntil = _cooldownUntil;
    if (currentUntil != null && currentUntil.isAfter(now)) {
      final remaining = currentUntil.difference(now);
      if (remaining >= duration) {
        CoreLog.i(
          '[ks-coordinator] cooldown kept (existing longer) '
          'remaining=${remaining.inSeconds}s',
        );
        return;
      }
    }
    final startsNewCooldown =
        currentUntil == null || !currentUntil.isAfter(now);
    _cooldownActive = true;
    _cooldownUntil = now.add(duration);
    if (startsNewCooldown) {
      // If the request that triggered the cooldown was a user-enter request,
      // it already consumed the sole probe for this cooldown window.
      _cooldownProbeClaimed = _running.any(
        (request) => request.priority == KuaishouRequestPriority.userEnter,
      );
    }
    CoreLog.i(
      '[ks-coordinator] cooldown begin duration=${duration.inSeconds}s '
      'until=$_cooldownUntil',
    );
  }

  /// 立即结束冷却。
  void endCooldown() {
    _cooldownActive = false;
    _cooldownUntil = null;
    _cooldownProbeClaimed = false;
    CoreLog.i('[ks-coordinator] cooldown ended');
  }

  /// 清空队列、在途 Future 与缓存。账号切换 / 站点重置时调用。
  void reset() {
    _epoch += 1;
    for (final pending in _pending.values.toList(growable: false)) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          KuaishouCooldownError('协调器已重置'),
        );
      }
    }
    _queue.clear();
    _pending.clear();
    _inFlight.clear();
    _running.clear();
    _cache.clear();
    _cooldownActive = false;
    _cooldownUntil = null;
    _cooldownProbeClaimed = false;
    // 已知取舍：此处无条件释放 pumping，使 reset 后的新请求能立即启动新循环；
    // 旧 _pumpLoop 恢复时会因 while 条件 epoch 不匹配而停止消费，但其 await 中的
    // 在途请求无法撤销——该请求完成时会被 epoch 检查丢弃（不交付、不写缓存），
    // 只存在"串行窗口内多发出一个将被丢弃的请求"的短暂并发，可接受。
    _pumping = false;
    _lastRequestAt = null;
  }

  /// 调度一个快手敏感请求。
  ///
  /// [key] 为合并与缓存的键（如 `room_detail:$roomId`）；同 key 的在途请求
  /// 会合并到同一个 Future。成功结果按 [cacheTtl] 缓存（失败不缓存）。
  /// [bypassInterval] 为 true 时不受最小间隔约束（仅限用户主动进房）。
  /// [logLabel] 为日志脱敏标签（如房间哈希），严禁传入原始 roomId。
  Future<T> schedule<T>({
    required KuaishouRequestPriority priority,
    required String key,
    Duration? cacheTtl,
    bool bypassInterval = false,
    String? logLabel,
    required Future<T> Function() task,
  }) {
    // 1. Pending 合并：从入队开始占位，覆盖排队、节流等待和实际执行。
    final pending = _pending[key];
    if (pending != null) {
      final mergeEpoch = _epoch;
      return pending.completer.future.then((value) {
        // 会话已重置（账号切换）：丢弃旧会话结果，等待者失败而非拿到旧数据。
        if (mergeEpoch != _epoch) {
          throw KuaishouCooldownError('协调器已重置');
        }
        return value as T;
      });
    }

    // 2. 短 TTL 缓存命中。
    if (cacheTtl != null) {
      final cached = _cache[key];
      if (cached != null && cached.expiresAt.isAfter(_now())) {
        CoreLog.i('[ks-coordinator] cache hit key=${logLabel ?? '<key>'}');
        return Future.value(cached.value as T);
      }
      if (cached != null) {
        _cache.remove(key);
      }
    }

    // 3. 冷却检查：后台请求让路；整个冷却窗口只允许一个主动探针。
    var cooldownProbe = false;
    if (inCooldown) {
      if (priority != KuaishouRequestPriority.userEnter ||
          _cooldownProbeClaimed) {
        CoreLog.i(
          '[ks-coordinator] rejected by cooldown '
          'key=${logLabel ?? '<key>'}',
        );
        return Future.error(KuaishouCooldownError('快手请求处于冷却期'));
      }
      _cooldownProbeClaimed = true;
      cooldownProbe = true;
    }

    final mayBypassInterval = bypassInterval && _pending.isEmpty;
    final completer = Completer<Object?>();
    final queued = _QueuedRequest(
      epoch: _epoch,
      priority: priority,
      key: key,
      task: () async => await task(),
      completer: completer,
      // bypass 仅由调用方显式声明（用户单房间进房）；userEnter 优先级
      // 本身不自动绕过最小间隔，避免多开批量开格时 N 路请求背靠背突发。
      bypassInterval: mayBypassInterval,
      cooldownProbe: cooldownProbe,
      cacheTtl: cacheTtl,
    );
    _queue.add(queued);
    _pending[key] = queued;
    _pump();
    return completer.future.then((value) => value as T);
  }

  void _pump() {
    if (_pumping) {
      return;
    }
    _pumping = true;
    unawaited(_pumpLoop());
  }

  /// 串行处理队列：每轮取最高优先级请求，执行完成后再取下一个。
  /// 这样最小间隔对队列中所有请求都生效（不会因各自 Timer 同时触发而失效）。
  Future<void> _pumpLoop() async {
    final epoch = _epoch;
    try {
      // epoch 变化（reset）后停止消费队列，避免旧循环与新循环并发执行请求。
      while (_queue.isNotEmpty && epoch == _epoch) {
        var bestIndex = 0;
        for (var i = 1; i < _queue.length; i++) {
          if (_queue[i].priority.order < _queue[bestIndex].priority.order) {
            bestIndex = i;
          }
        }
        final next = _queue.removeAt(bestIndex);

        if (_rejectForCooldown(next)) {
          continue;
        }

        // 最小间隔 + 抖动：执行前等待，避免背靠背突发。
        if (!next.bypassInterval) {
          final lastAt = _lastRequestAt;
          if (lastAt != null) {
            final elapsed = _now().difference(lastAt);
            if (elapsed < minInterval) {
              final jitter = _random.nextInt(maxJitter.inMilliseconds + 1);
              final wait =
                  minInterval - elapsed + Duration(milliseconds: jitter);
              await _waitUninterruptible(wait);
            }
          }
        }
        // reset/cooldown may happen while the request is sleeping outside the
        // queue. Re-check both boundaries before invoking any network task.
        if (next.epoch != _epoch || epoch != _epoch) {
          _completeReset(next);
          break;
        }
        if (_rejectForCooldown(next)) {
          continue;
        }
        await _runNext(next, epoch);
      }
    } finally {
      // 仅在未被 reset 打断时释放 pumping 标志，避免旧循环清除新循环状态。
      if (epoch == _epoch) {
        _pumping = false;
      }
    }
  }

  bool _rejectForCooldown(_QueuedRequest request) {
    if (!inCooldown) {
      return false;
    }
    if (request.priority == KuaishouRequestPriority.userEnter) {
      if (request.cooldownProbe) {
        return false;
      }
      if (!_cooldownProbeClaimed) {
        _cooldownProbeClaimed = true;
        request.cooldownProbe = true;
        return false;
      }
    }
    _completeError(request, KuaishouCooldownError('快手请求处于冷却期'));
    return true;
  }

  Future<void> _runNext(_QueuedRequest next, int epoch) async {
    _lastRequestAt = _now();
    final future = Future<Object?>.sync(next.task);
    _inFlight[next.key] = future;
    _running.add(next);
    try {
      final value = await future;
      // 会话已被 reset（账号切换）时丢弃结果与缓存，避免污染新会话；
      // 同时让等待者失败返回，避免永久挂起。
      if (epoch != _epoch) {
        if (!next.completer.isCompleted) {
          next.completer.completeError(
            KuaishouCooldownError('协调器已重置'),
          );
        }
        return;
      }
      // 成功结果按 TTL 写入缓存，供短窗口复用；失败不缓存。
      final ttl = next.cacheTtl;
      if (ttl != null) {
        _cache[next.key] = _CacheEntry(
          value: value,
          expiresAt: _now().add(ttl),
        );
      }
      if (!next.completer.isCompleted) {
        next.completer.complete(value);
      }
    } catch (e, stackTrace) {
      if (epoch != _epoch) {
        _completeReset(next);
      } else if (!next.completer.isCompleted) {
        next.completer.completeError(e, stackTrace);
      }
    } finally {
      // 仅当在途项仍属于本次执行时移除，避免旧代次请求误删新请求的合并项。
      if (identical(_inFlight[next.key], future)) {
        _inFlight.remove(next.key);
      }
      _running.remove(next);
      _removePending(next);
    }
  }

  void _completeReset(_QueuedRequest request) {
    _completeError(request, KuaishouCooldownError('协调器已重置'));
  }

  void _completeError(_QueuedRequest request, Object error) {
    if (!request.completer.isCompleted) {
      request.completer.completeError(error);
    }
    _removePending(request);
  }

  void _removePending(_QueuedRequest request) {
    if (identical(_pending[request.key], request)) {
      _pending.remove(request.key);
    }
  }

  Future<void> _waitUninterruptible(Duration duration) {
    final completer = Completer<void>();
    Timer(duration, completer.complete);
    return completer.future;
  }

  /// 缓存一个成功结果（供后续短窗口复用）。
  void cacheValue<T>(String key, T value, Duration ttl) {
    _cache[key] = _CacheEntry(value: value, expiresAt: _now().add(ttl));
  }
}

/// 协调器冷却期内后台请求被拒绝时抛出的错误。
class KuaishouCooldownError extends Error {
  KuaishouCooldownError(this.message);

  final String message;

  @override
  String toString() => 'KuaishouCooldownError: $message';
}

class _QueuedRequest {
  _QueuedRequest({
    required this.epoch,
    required this.priority,
    required this.key,
    required this.task,
    required this.completer,
    required this.bypassInterval,
    required this.cooldownProbe,
    this.cacheTtl,
  });

  final int epoch;
  final KuaishouRequestPriority priority;
  final String key;
  final Future<Object?> Function() task;
  final Completer<Object?> completer;
  final bool bypassInterval;
  bool cooldownProbe;
  final Duration? cacheTtl;
}

class _CacheEntry {
  const _CacheEntry({required this.value, required this.expiresAt});

  final Object? value;
  final DateTime expiresAt;
}
