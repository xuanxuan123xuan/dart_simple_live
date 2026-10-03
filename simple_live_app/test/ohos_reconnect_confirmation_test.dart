import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/ohos_reconnect_confirmation.dart';
import 'package:simple_live_app/services/live_link_health_models.dart';

void main() {
  final base = DateTime(2026, 8, 21, 12, 0, 0);

  OhosReconnectConfirmation build() => OhosReconnectConfirmation(
        confirmationTimeout: const Duration(seconds: 15),
      );

  test('arming alone records nothing until native playback confirms', () {
    final confirmation = build();

    final displaced = confirmation.arm(
      reason: LiveReconnectReason.mediaError,
      hostChanged: false,
      startedAt: base,
      now: base.add(const Duration(milliseconds: 200)),
      playerGeneration: 4,
    );

    expect(displaced, isNull);
    expect(confirmation.pending, isNotNull);
  });

  test('confirmation carries recovery duration measured from the start', () {
    final confirmation = build();
    confirmation.arm(
      reason: LiveReconnectReason.mediaError,
      hostChanged: true,
      startedAt: base,
      now: base.add(const Duration(milliseconds: 200)),
      playerGeneration: 4,
    );

    final outcome = confirmation.confirm(
      playerGeneration: 4,
      now: base.add(const Duration(milliseconds: 1800)),
    );

    expect(outcome, isNotNull);
    expect(outcome!.confirmed, isTrue);
    expect(outcome.reason, LiveReconnectReason.mediaError);
    expect(outcome.hostChanged, isTrue);
    expect(outcome.recoveryDuration, const Duration(milliseconds: 1800));
    expect(confirmation.pending, isNull);
  });

  test('a second confirmation for the same reconnect records nothing', () {
    final confirmation = build();
    confirmation.arm(
      reason: LiveReconnectReason.mediaEnd,
      hostChanged: false,
      startedAt: base,
      now: base,
      playerGeneration: 2,
    );

    expect(
      confirmation.confirm(playerGeneration: 2, now: base),
      isNotNull,
    );
    // 首帧与心跳可能都到，只能记一次。
    expect(
      confirmation.confirm(
        playerGeneration: 2,
        now: base.add(const Duration(seconds: 1)),
      ),
      isNull,
    );
  });

  test('timeout records the attempt without a fabricated recovery duration',
      () {
    final confirmation = build();
    confirmation.arm(
      reason: LiveReconnectReason.sustainedBuffering,
      hostChanged: false,
      startedAt: base,
      now: base,
      playerGeneration: 7,
    );

    expect(
      confirmation.flushIfExpired(base.add(const Duration(seconds: 14))),
      isNull,
    );

    final expired = confirmation.flushIfExpired(
      base.add(const Duration(seconds: 15)),
    );

    expect(expired, isNotNull);
    expect(expired!.confirmed, isFalse);
    // 重连确实发生过，次数不能丢；但耗时未知，不能编。
    expect(expired.reason, LiveReconnectReason.sustainedBuffering);
    expect(expired.recoveryDuration, isNull);
    expect(confirmation.pending, isNull);
  });

  test('re-arming flushes the previous attempt so two reopens count twice', () {
    final confirmation = build();
    confirmation.arm(
      reason: LiveReconnectReason.mediaError,
      hostChanged: false,
      startedAt: base,
      now: base,
      playerGeneration: 3,
    );

    final displaced = confirmation.arm(
      reason: LiveReconnectReason.automaticLineFailover,
      hostChanged: true,
      startedAt: base.add(const Duration(seconds: 2)),
      now: base.add(const Duration(seconds: 2)),
      playerGeneration: 4,
    );

    expect(displaced, isNotNull);
    expect(displaced!.confirmed, isFalse);
    expect(displaced.reason, LiveReconnectReason.mediaError);
    expect(displaced.recoveryDuration, isNull);

    final outcome = confirmation.confirm(
      playerGeneration: 4,
      now: base.add(const Duration(seconds: 3)),
    );
    expect(outcome, isNotNull);
    expect(outcome!.confirmed, isTrue);
    expect(outcome.reason, LiveReconnectReason.automaticLineFailover);
  });

  test('an older generation confirmation cannot settle a newer reconnect', () {
    final confirmation = build();
    confirmation.arm(
      reason: LiveReconnectReason.playbackUrlRefresh,
      hostChanged: false,
      startedAt: base,
      now: base,
      playerGeneration: 9,
    );

    // 上一代播放器的迟到信号不得给新一代重连定稿。
    expect(
      confirmation.confirm(playerGeneration: 8, now: base),
      isNull,
    );
    expect(confirmation.pending, isNotNull);
  });

  test('a newer generation flushes a stranded reconnect as unconfirmed', () {
    final confirmation = build();
    confirmation.arm(
      reason: LiveReconnectReason.mediaError,
      hostChanged: false,
      startedAt: base,
      now: base,
      playerGeneration: 5,
    );

    // 手动切线路/改画质会推进代次而不经过 arm，挂起记录必须被冲掉，
    // 否则它会一直挂着，直到超时才补记。
    final outcome = confirmation.confirm(
      playerGeneration: 6,
      now: base.add(const Duration(seconds: 1)),
    );

    expect(outcome, isNotNull);
    expect(outcome!.confirmed, isFalse);
    expect(outcome.recoveryDuration, isNull);
    expect(confirmation.pending, isNull);
  });

  test('reset drops the pending attempt without recording it', () {
    final confirmation = build();
    confirmation.arm(
      reason: LiveReconnectReason.mediaError,
      hostChanged: false,
      startedAt: base,
      now: base,
      playerGeneration: 1,
    );

    confirmation.reset();

    // 换房后往旧房间的健康窗口补一条重连没有意义。
    expect(confirmation.pending, isNull);
    expect(
      confirmation.flushIfExpired(base.add(const Duration(minutes: 1))),
      isNull,
    );
  });

  test('unknown host change stays null instead of collapsing to false', () {
    final confirmation = build();
    confirmation.arm(
      reason: LiveReconnectReason.mediaError,
      hostChanged: null,
      startedAt: base,
      now: base,
      playerGeneration: 1,
    );

    final outcome = confirmation.confirm(playerGeneration: 1, now: base);

    expect(outcome!.hostChanged, isNull);
  });

  test('a missing start time yields a confirmed attempt with unknown recovery',
      () {
    final confirmation = build();
    confirmation.arm(
      reason: LiveReconnectReason.playbackUrlRefresh,
      hostChanged: false,
      startedAt: null,
      now: base,
      playerGeneration: 1,
    );

    final outcome = confirmation.confirm(
      playerGeneration: 1,
      now: base.add(const Duration(seconds: 2)),
    );

    expect(outcome!.confirmed, isTrue);
    expect(outcome.recoveryDuration, isNull);
  });
}
