import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/mpv_live_latency_chase_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  final startedAt = DateTime(2026, 8, 5, 12);

  test('uses hysteresis and a minimum dwell before returning to normal',
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
      cacheDurationSeconds: 0.8,
      sampledAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 0.9,
      sampledAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 0.6,
      sampledAt: startedAt.add(const Duration(seconds: 1)),
    );
    await service.observe(
      cacheDurationSeconds: 0.6,
      sampledAt: startedAt.add(const Duration(seconds: 10)),
    );

    expect(writes, hasLength(2));
    expect(writes[0], greaterThanOrEqualTo(1.05));
    expect(writes[0], lessThanOrEqualTo(1.08));
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

    expect(writes, [1.08, 1.0, 1.08, 1.0]);
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
    expect(writes, [1.08, 1.0]);
  });

  test('chases relative to and restores a custom baseline speed', () async {
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
    await service.stop(stoppedAt: startedAt.add(const Duration(seconds: 1)));

    expect(writes[0], closeTo(1.35, 0.000001));
    expect(writes[1], 1.25);
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
      baselineSpeed: 0.8,
      startedAt: startedAt,
    );
    await service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt,
    );
    await service.reset(sampledAt: startedAt.add(const Duration(seconds: 1)));

    expect(writes[0], closeTo(0.864, 0.000001));
    expect(writes[1], 0.8);
    expect(service.currentSpeed, 0.8);
  });

  test('a catch-up write failure restores the custom baseline speed', () async {
    const baselineSpeed = 1.25;
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
    expect(writes[0], closeTo(1.35, 0.000001));
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

    expect(writes, [1.08, 1.0, 1.0]);
    expect(service.currentSpeed, MpvLiveLatencyChaseService.normalSpeed);
    expect(service.isBaselineRestorePending, isFalse);
  });

  test('stop retries a failed first baseline restore after catch-up', () async {
    const baselineSpeed = 1.25;
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
    expect(service.currentSpeed, closeTo(1.35, 0.000001));
    expect(service.isBaselineRestorePending, isTrue);
    expect(writes, hasLength(2));
    expect(writes[0], closeTo(1.35, 0.000001));
    expect(writes[1], baselineSpeed);

    await service.stop(stoppedAt: startedAt.add(const Duration(seconds: 2)));

    expect(writes, hasLength(3));
    expect(writes[0], closeTo(1.35, 0.000001));
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
}
