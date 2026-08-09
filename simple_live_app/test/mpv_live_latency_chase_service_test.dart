import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/mpv_live_latency_chase_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  final startedAt = DateTime(2026, 8, 5, 12);

  test('uses safe hysteresis and returns to normal without waiting for dwell',
      () async {
    final writes = <double>[];
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async => writes.add(speed),
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 1.9,
      sampledAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 2.1,
      sampledAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 1.2,
      sampledAt: startedAt.add(const Duration(seconds: 1)),
    );

    expect(writes, hasLength(2));
    expect(writes[0], 1.03);
    expect(writes[1], MpvLiveLatencyChaseService.normalSpeed);
  });

  test('low cache and buffering immediately restore normal speed', () async {
    final writes = <double>[];
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async => writes.add(speed),
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.hls,
      startedAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 0.5,
      sampledAt: startedAt.add(const Duration(seconds: 1)),
    );
    await service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt.add(const Duration(seconds: 11)),
    );
    await service.protect(
      sampledAt: startedAt.add(const Duration(seconds: 12)),
    );

    expect(writes, [1.04, 1.0, 1.04, 1.0]);
  });

  test('off mode never applies a catch-up speed', () async {
    final writes = <double>[];
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async => writes.add(speed),
    );

    await service.start(
      latencyMode: 'off',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt,
    );

    expect(service.policy.enabled, isFalse);
    expect(service.isEnabled, isFalse);
    expect(writes, isEmpty);
  });

  test(
      'a native write failure disables the loop and falls back to normal speed',
      () async {
    final writes = <double>[];
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async {
        writes.add(speed);
        if (speed > 1) {
          throw StateError('native player unavailable');
        }
      },
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt,
    );

    expect(service.isEnabled, isFalse);
    expect(service.currentSpeed, 1.0);
    expect(service.isBaselineRestorePending, isFalse);
    expect(writes, [1.06, 1.0]);
  });

  test('custom user speed disables chasing without discarding the baseline',
      () async {
    final writes = <double>[];
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async => writes.add(speed),
      readSpeed: () async => 1.25,
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt,
    );

    expect(service.policy.enabled, isFalse);
    expect(service.isEnabled, isFalse);
    expect(service.baselineSpeed, 1.25);
    expect(service.currentSpeed, 1.25);
    expect(writes, isEmpty);

    await service.stop(stoppedAt: startedAt.add(const Duration(seconds: 1)));

    expect(service.baselineSpeed, MpvLiveLatencyChaseService.normalSpeed);
  });

  test('reset restores the custom baseline without forcing one speed',
      () async {
    final writes = <double>[];
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async => writes.add(speed),
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      baselineSpeed: 1.05,
      startedAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt,
    );
    await service.reset(sampledAt: startedAt.add(const Duration(seconds: 1)));

    expect(writes[0], closeTo(1.113, 0.000001));
    expect(writes[1], 1.05);
    expect(service.currentSpeed, 1.05);
  });

  test('a catch-up write failure restores the custom baseline speed', () async {
    const baselineSpeed = 1.05;
    final writes = <double>[];
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async {
        writes.add(speed);
        if (speed > baselineSpeed) {
          throw StateError('native player unavailable');
        }
      },
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      baselineSpeed: baselineSpeed,
      startedAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt,
    );

    expect(service.isEnabled, isFalse);
    expect(service.currentSpeed, baselineSpeed);
    expect(service.isBaselineRestorePending, isFalse);
    expect(writes[0], closeTo(1.113, 0.000001));
    expect(writes[1], baselineSpeed);
  });

  test('stop retries baseline recovery after catch-up and recovery writes fail',
      () async {
    final writes = <double>[];
    var baselineWriteCount = 0;
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async {
        writes.add(speed);
        if (speed > MpvLiveLatencyChaseService.normalSpeed) {
          throw StateError('native player unavailable');
        }
        baselineWriteCount++;
        if (baselineWriteCount == 1) {
          throw StateError('baseline recovery unavailable');
        }
      },
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt,
    );

    expect(service.currentSpeed, MpvLiveLatencyChaseService.normalSpeed);
    expect(service.isBaselineRestorePending, isTrue);

    await service.stop(stoppedAt: startedAt.add(const Duration(seconds: 1)));

    expect(writes, [1.06, 1.0, 1.0]);
    expect(service.currentSpeed, MpvLiveLatencyChaseService.normalSpeed);
    expect(service.isBaselineRestorePending, isFalse);
  });

  test('stop retries a failed first baseline restore after catch-up', () async {
    const baselineSpeed = 1.05;
    final writes = <double>[];
    var baselineWriteCount = 0;
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async {
        writes.add(speed);
        if (speed > baselineSpeed) {
          return;
        }
        baselineWriteCount++;
        if (baselineWriteCount == 1) {
          throw StateError('baseline recovery unavailable');
        }
      },
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      baselineSpeed: baselineSpeed,
      startedAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 0.2,
      sampledAt: startedAt.add(const Duration(seconds: 1)),
    );

    expect(service.isEnabled, isFalse);
    expect(service.currentSpeed, closeTo(1.113, 0.000001));
    expect(service.isBaselineRestorePending, isTrue);
    expect(writes, hasLength(2));
    expect(writes[0], closeTo(1.113, 0.000001));
    expect(writes[1], baselineSpeed);

    await service.stop(stoppedAt: startedAt.add(const Duration(seconds: 2)));

    expect(writes, hasLength(3));
    expect(writes[0], closeTo(1.113, 0.000001));
    expect(writes[1], baselineSpeed);
    expect(writes[2], baselineSpeed);
    expect(service.currentSpeed, MpvLiveLatencyChaseService.normalSpeed);
    expect(service.isBaselineRestorePending, isFalse);
  });

  test('does not write a guessed speed when the baseline is unavailable',
      () async {
    final writes = <double>[];
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async => writes.add(speed),
      readSpeed: () async => null,
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt,
    );
    await service.stop(stoppedAt: startedAt.add(const Duration(seconds: 1)));

    expect(service.isEnabled, isFalse);
    expect(writes, isEmpty);
  });

  test('unknown protocol disables automatic chasing', () async {
    final writes = <double>[];
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async => writes.add(speed),
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.unknown,
      startedAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt,
    );

    expect(service.policy.enabled, isFalse);
    expect(service.isEnabled, isFalse);
    expect(writes, isEmpty);
  });

  test('reduces catch-up speed immediately while increases respect dwell',
      () async {
    final writes = <double>[];
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async => writes.add(speed),
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 5.04, sampledAt: startedAt);
    await service.observe(
      cacheDurationSeconds: 4.98,
      sampledAt: startedAt.add(const Duration(seconds: 1)),
    );
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 2)),
    );

    expect(writes, [1.06, 1.04]);
  });

  test('predicts cache exhaustion and enters a safety cooldown', () async {
    final writes = <double>[];
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async => writes.add(speed),
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 2.1, sampledAt: startedAt);
    await service.observe(
      cacheDurationSeconds: 0.8,
      sampledAt: startedAt.add(const Duration(seconds: 15)),
    );
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 24)),
    );
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 25)),
    );

    expect(writes, [1.03, 1.0, 1.06]);
  });

  test('buffering cooldown blocks catch-up until cache is stable again',
      () async {
    final writes = <double>[];
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async => writes.add(speed),
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 6, sampledAt: startedAt);
    await service.protect(
      sampledAt: startedAt.add(const Duration(seconds: 1)),
    );
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 15)),
    );
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 16)),
    );

    expect(writes, [1.06, 1.0, 1.06]);
  });

  test('automatic FLV catch-up uses conservative speed bands', () async {
    final writes = <double>[];
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (speed) async => writes.add(speed),
      minimumDwell: Duration.zero,
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 6, sampledAt: startedAt);
    await service.observe(
      cacheDurationSeconds: 4,
      sampledAt: startedAt.add(const Duration(seconds: 200)),
    );
    await service.observe(
      cacheDurationSeconds: 2.5,
      sampledAt: startedAt.add(const Duration(seconds: 400)),
    );
    await service.observe(
      cacheDurationSeconds: 1.8,
      sampledAt: startedAt.add(const Duration(seconds: 600)),
    );
    await service.observe(
      cacheDurationSeconds: 1.2,
      sampledAt: startedAt.add(const Duration(seconds: 800)),
    );

    expect(writes, [1.06, 1.05, 1.03, 1.02, 1.0]);
  });
}
