import 'package:simple_live_app/services/live_link_health_models.dart';

/// 一次待确认的鸿蒙自动重连。
class OhosPendingReconnect {
  const OhosPendingReconnect({
    required this.reason,
    required this.hostChanged,
    required this.startedAt,
    required this.requestedAt,
    required this.playerGeneration,
  });

  final LiveReconnectReason reason;

  /// 是否换了 host。null 表示无法判断，与健康事件的 nullable 语义一致，
  /// 不能压成 false 冒充"没换"。
  final bool? hostChanged;

  /// 重连动作真正开始的时刻（用于算恢复耗时）。为空表示调用方没有提供起点。
  final DateTime? startedAt;

  /// 重开播放器的请求发出的时刻（用于判超时）。
  final DateTime requestedAt;

  /// 本次重连指向的播放器代次。
  final int playerGeneration;
}

/// 已定稿、可写入健康事件的一次自动重连。
class OhosReconnectOutcome {
  const OhosReconnectOutcome({
    required this.reason,
    required this.hostChanged,
    required this.confirmed,
    required this.occurredAt,
    required this.playerGeneration,
    this.recoveryDuration,
  });

  final LiveReconnectReason reason;

  /// 是否换了 host。null 表示无法判断。
  final bool? hostChanged;

  /// 是否等到了原生播放确认（初始化 / 首帧 / 心跳）。
  final bool confirmed;

  final DateTime occurredAt;
  final int playerGeneration;

  /// 恢复耗时。未确认时为 null——宁可缺这一项，也不记一个假的耗时。
  final Duration? recoveryDuration;
}

/// 把鸿蒙的"重开播放器"动作与随后的原生播放确认信号配对。
///
/// 鸿蒙侧 `initPlaylist` 只是同步请求一次 widget 重建，返回时 AVPlayer 还没
/// 接受地址，所以"重开返回成功"不足以当成重连完成。这里先挂起一条待确认记录，
/// 等到同代次的 initialized / 首帧 / 心跳任一到达再定稿，恢复耗时才有意义。
///
/// 超时未确认也必须定稿（[flushIfExpired]），只是不带恢复耗时：重连确实发生过，
/// 丢掉它会让面板显示一个偏低的次数，比缺一项耗时更糟。
class OhosReconnectConfirmation {
  OhosReconnectConfirmation({
    this.confirmationTimeout = const Duration(seconds: 15),
  });

  /// 等待原生确认的上限。取值高于心跳失联判定（10s），
  /// 使"心跳确认"在超时兜底之前有机会到达。
  final Duration confirmationTimeout;

  OhosPendingReconnect? _pending;

  OhosPendingReconnect? get pending => _pending;

  /// 挂起一条待确认重连。
  ///
  /// 若上一条仍未确认，则把它按未确认定稿返回：两次重开就是两次重连，
  /// 合并计数会低报。
  OhosReconnectOutcome? arm({
    required LiveReconnectReason reason,
    required bool? hostChanged,
    required DateTime? startedAt,
    required DateTime now,
    required int playerGeneration,
  }) {
    final displaced = _pending;
    _pending = OhosPendingReconnect(
      reason: reason,
      hostChanged: hostChanged,
      startedAt: startedAt,
      requestedAt: now,
      playerGeneration: playerGeneration,
    );
    if (displaced == null) {
      return null;
    }
    return _unconfirmed(displaced, now);
  }

  /// 收到同代次的原生播放确认，定稿并返回。
  ///
  /// 代次比待确认记录更新时，说明这条记录已经被后来的重开甩下，
  /// 按未确认定稿，避免它永远挂在那里。
  OhosReconnectOutcome? confirm({
    required int playerGeneration,
    required DateTime now,
  }) {
    final pending = _pending;
    if (pending == null) {
      return null;
    }
    if (playerGeneration < pending.playerGeneration) {
      return null;
    }
    _pending = null;
    if (playerGeneration > pending.playerGeneration) {
      return _unconfirmed(pending, now);
    }
    final startedAt = pending.startedAt;
    return OhosReconnectOutcome(
      reason: pending.reason,
      hostChanged: pending.hostChanged,
      confirmed: true,
      occurredAt: now,
      playerGeneration: pending.playerGeneration,
      recoveryDuration:
          startedAt == null ? null : now.difference(startedAt),
    );
  }

  /// 超时未确认则定稿返回，否则返回 null。
  OhosReconnectOutcome? flushIfExpired(DateTime now) {
    final pending = _pending;
    if (pending == null) {
      return null;
    }
    if (now.difference(pending.requestedAt) < confirmationTimeout) {
      return null;
    }
    _pending = null;
    return _unconfirmed(pending, now);
  }

  /// 换房 / 销毁：丢弃待确认记录。
  ///
  /// 这里不定稿——房间已经不在了，往它的健康窗口里补一条重连没有意义。
  void reset() {
    _pending = null;
  }

  OhosReconnectOutcome _unconfirmed(OhosPendingReconnect pending, DateTime now) {
    return OhosReconnectOutcome(
      reason: pending.reason,
      hostChanged: pending.hostChanged,
      confirmed: false,
      occurredAt: now,
      playerGeneration: pending.playerGeneration,
    );
  }
}
