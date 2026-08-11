import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/mpv_live_latency_chase_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

MpvLiveLatencyChaseService _service({
  required MpvPlaybackSpeedWriter writeSpeed,
  MpvPlaybackSpeedReader? readSpeed,
  Duration minimumDwell = const Duration(seconds: 10),
  Duration settlingDuration = Duration.zero,
  Duration stableObservationDuration = Duration.zero,
  Duration bufferingCooldown = const Duration(seconds: 15),
  Duration safetyCooldown = const Duration(seconds: 10),
  Duration budgetCooldown = const Duration(seconds: 3),
  Duration maximumStableSampleGap = const Duration(days: 1),
  void Function(Object error)? onWriteError,
}) {
  return MpvLiveLatencyChaseService(
    writeSpeed: writeSpeed,
    readSpeed: readSpeed ?? () async => 1,
    minimumDwell: minimumDwell,
    settlingDuration: settlingDuration,
    stableObservationDuration: stableObservationDuration,
    bufferingCooldown: bufferingCooldown,
    safetyCooldown: safetyCooldown,
    budgetCooldown: budgetCooldown,
    maximumStableSampleGap: maximumStableSampleGap,
    onWriteError: onWriteError,
  );
}

void main() {
  final startedAt = DateTime(2026, 8, 5, 12);

  group('policy profiles', () {
    test('encodes protocol thresholds, speed caps, and hard budgets', () {
      final vectors = <({
        String mode,
        LiveStreamProtocol protocol,
        double stop,
        double resume,
        double floor,
        double maximum,
        int hardSeconds,
      })>[
        (
          mode: 'auto',
          protocol: LiveStreamProtocol.flv,
          stop: 1.2,
          resume: 2,
          floor: 0.6,
          maximum: 1.06,
          hardSeconds: 90,
        ),
        (
          mode: 'aggressive',
          protocol: LiveStreamProtocol.rtmp,
          stop: 0.8,
          resume: 1.4,
          floor: 0.4,
          maximum: 1.08,
          hardSeconds: 120,
        ),
        (
          mode: 'auto',
          protocol: LiveStreamProtocol.hls,
          stop: 1.8,
          resume: 3,
          floor: 1,
          maximum: 1.04,
          hardSeconds: 60,
        ),
        (
          mode: 'aggressive',
          protocol: LiveStreamProtocol.fmp4,
          stop: 1.4,
          resume: 2.4,
          floor: 0.8,
          maximum: 1.06,
          hardSeconds: 90,
        ),
      ];

      for (final vector in vectors) {
        final policy = MpvLiveLatencyChasePolicy.forStream(
          latencyMode: vector.mode,
          protocol: vector.protocol,
        );
        expect(policy.enabled, isTrue);
        expect(policy.stopThresholdSeconds, vector.stop);
        expect(policy.resumeThresholdSeconds, vector.resume);
        expect(policy.hardFloorSeconds, vector.floor);
        expect(policy.maximumCatchUpMultiplier, vector.maximum);
        expect(policy.catchUpHardLimit, Duration(seconds: vector.hardSeconds));
      }
    });

    test('unknown, unreleased modes, and unsupported platforms stay disabled',
        () {
      expect(
        MpvLiveLatencyChasePolicy.forStream(
          latencyMode: 'auto',
          protocol: LiveStreamProtocol.unknown,
        ).enabled,
        isFalse,
      );
      for (final mode in ['off', 'sports', 'ultraLow', '']) {
        expect(
          MpvLiveLatencyChasePolicy.forStream(
            latencyMode: mode,
            protocol: LiveStreamProtocol.flv,
          ).enabled,
          isFalse,
        );
      }
      expect(
        MpvLiveLatencyChasePolicy.forStream(
          latencyMode: 'auto',
          protocol: LiveStreamProtocol.flv,
          platformProfile: MpvLiveLatencyPlatformProfile.unsupported,
        ).enabled,
        isFalse,
      );
    });

    test('resource-constrained profile caps speed, cadence, and hard budget',
        () {
      final policy = MpvLiveLatencyChasePolicy.forStream(
        latencyMode: 'aggressive',
        protocol: LiveStreamProtocol.flv,
        platformProfile: MpvLiveLatencyPlatformProfile.resourceConstrained,
      );

      expect(policy.maximumCatchUpMultiplier, 1.02);
      expect(policy.catchUpHardLimit, const Duration(seconds: 60));
      expect(policy.catchUpSampleInterval, const Duration(seconds: 1));
      expect(policy.nearEdgeSampleInterval, const Duration(seconds: 1));
      expect(policy.stopThresholdSeconds, 1.2);
      expect(policy.resumeThresholdSeconds, 2.0);
      expect(policy.hardFloorSeconds, 0.6);
    });

    test('multi-room roles cap primary at auto and disable secondary chase',
        () {
      final primary = MpvLiveLatencyChasePolicy.forStream(
        latencyMode: 'aggressive',
        protocol: LiveStreamProtocol.flv,
        playbackRole: MpvLiveLatencyPlaybackRole.multiRoomPrimaryVisible,
      );
      final secondary = MpvLiveLatencyChasePolicy.forStream(
        latencyMode: 'aggressive',
        protocol: LiveStreamProtocol.flv,
        playbackRole: MpvLiveLatencyPlaybackRole.multiRoomSecondaryOrInactive,
      );

      expect(primary.enabled, isTrue);
      expect(primary.maximumCatchUpMultiplier, 1.06);
      expect(primary.catchUpHardLimit, const Duration(seconds: 90));
      expect(secondary.enabled, isFalse);
    });
  });

  test('disabled policies preserve the Disabled invariant on protection',
      () async {
    for (final role in [
      MpvLiveLatencyPlaybackRole.singleRoom,
      MpvLiveLatencyPlaybackRole.multiRoomSecondaryOrInactive,
    ]) {
      final service = _service(writeSpeed: (_) async {});
      await service.start(
        latencyMode: role == MpvLiveLatencyPlaybackRole.singleRoom
            ? 'off'
            : 'auto',
        protocol: LiveStreamProtocol.flv,
        playbackRole: role,
        startedAt: startedAt,
      );
      await service.protect(
        sampledAt: startedAt.add(const Duration(seconds: 1)),
        reason: MpvLiveLatencyProtectionReason.lifecycleInterrupted,
      );

      expect(service.state, MpvLiveLatencyChaseState.disabled);
      expect(service.lastProtectionReason, isNull);
    }
  });

  test('moves through settling, catching, protecting, cooldown and monitoring',
      () async {
    final writes = <double>[];
    final service = _service(
      writeSpeed: (speed) async => writes.add(speed),
      settlingDuration: const Duration(seconds: 10),
      stableObservationDuration: const Duration(seconds: 5),
    );

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    expect(service.state, MpvLiveLatencyChaseState.settling);

    await service.observe(cacheDurationSeconds: 6, sampledAt: startedAt);
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 9)),
    );
    expect(service.state, MpvLiveLatencyChaseState.settling);
    expect(writes, isEmpty);

    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 10)),
    );
    expect(service.state, MpvLiveLatencyChaseState.catchingUp);
    expect(writes, [1.06]);

    await service.protect(
      sampledAt: startedAt.add(const Duration(seconds: 11)),
      reason: MpvLiveLatencyProtectionReason.audioUnderrun,
    );
    expect(service.state, MpvLiveLatencyChaseState.cooldown);
    expect(
      service.lastProtectionReason,
      MpvLiveLatencyProtectionReason.audioUnderrun,
    );
    expect(writes, [1.06, 1.0]);

    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 26)),
    );
    expect(service.state, MpvLiveLatencyChaseState.monitoring);
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 30)),
    );
    expect(service.state, MpvLiveLatencyChaseState.monitoring);
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 31)),
    );
    expect(service.state, MpvLiveLatencyChaseState.catchingUp);
  });

  test('publishes conservative dynamic sample recommendations', () async {
    final service = _service(writeSpeed: (_) async {});
    expect(service.recommendedSampleInterval, isNull);

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    expect(
      service.recommendedSampleInterval,
      const Duration(seconds: 2),
    );
    await service.observe(cacheDurationSeconds: 1.6, sampledAt: startedAt);
    expect(
      service.recommendedSampleInterval,
      const Duration(milliseconds: 500),
    );
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 1)),
    );
    expect(service.state, MpvLiveLatencyChaseState.catchingUp);
    expect(
      service.recommendedSampleInterval,
      const Duration(milliseconds: 500),
    );
    await service.protect(
      sampledAt: startedAt.add(const Duration(seconds: 2)),
    );
    expect(
      service.recommendedSampleInterval,
      const Duration(seconds: 1),
    );
  });

  test('safe hysteresis restores baseline immediately without waiting dwell',
      () async {
    final writes = <double>[];
    final service = _service(writeSpeed: (speed) async => writes.add(speed));

    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 2.1, sampledAt: startedAt);
    await service.observe(
      cacheDurationSeconds: 1.2,
      sampledAt: startedAt.add(const Duration(seconds: 20)),
    );

    expect(writes, [1.03, 1.0]);
    expect(service.state, MpvLiveLatencyChaseState.monitoring);
  });

  test('invalid telemetry and hard floor immediately protect and clear trend',
      () async {
    for (final invalid in <double?>[null, double.nan, -1]) {
      final writes = <double>[];
      final service = _service(writeSpeed: (speed) async => writes.add(speed));
      await service.start(
        latencyMode: 'auto',
        protocol: LiveStreamProtocol.flv,
        startedAt: startedAt,
      );
      await service.observe(cacheDurationSeconds: 6, sampledAt: startedAt);
      await service.observe(
        cacheDurationSeconds: invalid,
        sampledAt: startedAt.add(const Duration(seconds: 1)),
      );
      expect(service.state, MpvLiveLatencyChaseState.cooldown);
      expect(
        service.lastProtectionReason,
        MpvLiveLatencyProtectionReason.telemetryUnavailable,
      );
      expect(writes, [1.06, 1.0]);
    }

    final service = _service(writeSpeed: (_) async {});
    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 0.6, sampledAt: startedAt);
    expect(
      service.lastProtectionReason,
      MpvLiveLatencyProtectionReason.hardFloorReached,
    );
  });

  test('three-sample robust trend predicts exhaustion and protects', () async {
    final writes = <double>[];
    final service = _service(writeSpeed: (speed) async => writes.add(speed));
    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 3, sampledAt: startedAt);
    await service.observe(
      cacheDurationSeconds: 2.9,
      sampledAt: startedAt.add(const Duration(seconds: 1)),
    );
    await service.observe(
      cacheDurationSeconds: 2.5,
      sampledAt: startedAt.add(const Duration(seconds: 2)),
    );

    expect(service.state, MpvLiveLatencyChaseState.cooldown);
    expect(
      service.lastProtectionReason,
      anyOf(
        MpvLiveLatencyProtectionReason.predictedCacheExhaustion,
        MpvLiveLatencyProtectionReason.cacheFallingFast,
      ),
    );
    expect(writes.last, 1.0);
  });

  test('dynamic budget only tightens and permits a qualified later round',
      () async {
    final writes = <double>[];
    final service = _service(
      writeSpeed: (speed) async => writes.add(speed),
      minimumDwell: Duration.zero,
      stableObservationDuration: const Duration(seconds: 5),
    );
    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 2, sampledAt: startedAt);
    await service.observe(
      cacheDurationSeconds: 2,
      sampledAt: startedAt.add(const Duration(seconds: 5)),
    );
    await service.observe(
      cacheDurationSeconds: 2,
      sampledAt: startedAt.add(const Duration(seconds: 15)),
    );
    await service.observe(
      cacheDurationSeconds: 2,
      sampledAt: startedAt.add(const Duration(seconds: 21)),
    );

    expect(service.state, MpvLiveLatencyChaseState.cooldown);
    expect(
      service.lastProtectionReason,
      MpvLiveLatencyProtectionReason.catchUpBudgetExhausted,
    );
    expect(writes, [1.03, 1.0]);

    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 24)),
    );
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 28)),
    );
    expect(service.state, MpvLiveLatencyChaseState.monitoring);
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 29)),
    );
    expect(service.state, MpvLiveLatencyChaseState.catchingUp);
    expect(writes, [1.03, 1.0, 1.06]);
  });

  test('aggressive FLV catch-up obeys its hard 120 second budget', () async {
    final writes = <double>[];
    final service = _service(writeSpeed: (speed) async => writes.add(speed));
    await service.start(
      latencyMode: 'aggressive',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 100, sampledAt: startedAt);
    await service.observe(
      cacheDurationSeconds: 100,
      sampledAt: startedAt.add(const Duration(seconds: 120)),
    );

    expect(
      service.lastProtectionReason,
      MpvLiveLatencyProtectionReason.catchUpBudgetExhausted,
    );
    expect(writes, [1.08, 1.0]);
  });

  test('stale generation samples are ignored inside the serial queue',
      () async {
    final writes = <double>[];
    final service = _service(writeSpeed: (speed) async => writes.add(speed));
    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    final staleGeneration = service.generation;

    final restart = service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.hls,
      startedAt: startedAt.add(const Duration(seconds: 1)),
    );
    final staleSample = service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt.add(const Duration(seconds: 2)),
      generation: staleGeneration,
    );
    await Future.wait([restart, staleSample]);
    expect(writes, [1.0]);

    await service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt.add(const Duration(seconds: 3)),
      generation: service.generation,
    );
    expect(writes, [1.0, 1.04]);
  });

  test('an in-flight baseline read cannot commit after a newer start',
      () async {
    final readStarted = Completer<void>();
    final readGate = Completer<double?>();
    final service = MpvLiveLatencyChaseService(
      writeSpeed: (_) async {},
      readSpeed: () {
        readStarted.complete();
        return readGate.future;
      },
      settlingDuration: Duration.zero,
      stableObservationDuration: Duration.zero,
    );

    final staleStart = service.start(
      latencyMode: 'aggressive',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await readStarted.future;
    final currentStart = service.start(
      latencyMode: 'off',
      protocol: LiveStreamProtocol.hls,
      baselineSpeed: 1,
      startedAt: startedAt.add(const Duration(seconds: 1)),
    );
    readGate.complete(1);
    await Future.wait([staleStart, currentStart]);

    expect(service.state, MpvLiveLatencyChaseState.disabled);
    expect(service.policy.enabled, isFalse);
    expect(service.baselineSpeed, 1);
  });

  test('an in-flight stale speed write cannot commit into a newer generation',
      () async {
    final writeStarted = Completer<void>();
    final writeGate = Completer<void>();
    final writes = <double>[];
    final service = _service(
      writeSpeed: (speed) async {
        writes.add(speed);
        if (speed > 1 && !writeStarted.isCompleted) {
          writeStarted.complete();
          await writeGate.future;
        }
      },
    );
    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );

    final staleObserve = service.observe(
      cacheDurationSeconds: 10,
      sampledAt: startedAt,
      generation: service.generation,
    );
    await writeStarted.future;
    final currentStart = service.start(
      latencyMode: 'off',
      protocol: LiveStreamProtocol.hls,
      baselineSpeed: 1,
      startedAt: startedAt.add(const Duration(seconds: 1)),
    );
    writeGate.complete();
    await Future.wait([staleObserve, currentStart]);

    expect(writes, [1.06, 1.0]);
    expect(service.state, MpvLiveLatencyChaseState.disabled);
    expect(service.currentSpeed, 1);
    expect(service.isBaselineRestorePending, isFalse);
  });

  test('an in-flight protection restore cannot publish stale cooldown state',
      () async {
    final restoreStarted = Completer<void>();
    final restoreGate = Completer<void>();
    var hasCaughtUp = false;
    final writes = <double>[];
    final service = _service(
      writeSpeed: (speed) async {
        writes.add(speed);
        if (speed > 1) {
          hasCaughtUp = true;
          return;
        }
        if (hasCaughtUp && !restoreStarted.isCompleted) {
          restoreStarted.complete();
          await restoreGate.future;
        }
      },
    );
    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 10, sampledAt: startedAt);

    final staleProtect = service.protect(
      sampledAt: startedAt.add(const Duration(seconds: 1)),
    );
    await restoreStarted.future;
    final stop = service.stop(
      stoppedAt: startedAt.add(const Duration(seconds: 2)),
    );
    restoreGate.complete();
    await Future.wait([staleProtect, stop]);

    expect(service.state, MpvLiveLatencyChaseState.disabled);
    expect(service.lastProtectionReason, isNull);
    expect(service.currentSpeed, 1);
    expect(writes, [1.06, 1.0, 1.0]);
  });

  test('custom baseline uses absolute speed cap and reset restores baseline',
      () async {
    final writes = <double>[];
    final service = _service(writeSpeed: (speed) async => writes.add(speed));
    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      baselineSpeed: 1.05,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 10, sampledAt: startedAt);
    await service.reset(sampledAt: startedAt.add(const Duration(seconds: 1)));

    expect(writes, [1.06, 1.05]);
    expect(service.currentSpeed, 1.05);
    expect(service.state, MpvLiveLatencyChaseState.settling);
  });

  test('baseline at or above policy cap remains Monitoring without a budget',
      () async {
    for (final vector in [
      (
        protocol: LiveStreamProtocol.hls,
        profile: MpvLiveLatencyPlatformProfile.conservative,
      ),
      (
        protocol: LiveStreamProtocol.flv,
        profile: MpvLiveLatencyPlatformProfile.resourceConstrained,
      ),
    ]) {
      final writes = <double>[];
      final service = _service(writeSpeed: (speed) async => writes.add(speed));
      await service.start(
        latencyMode: 'auto',
        protocol: vector.protocol,
        platformProfile: vector.profile,
        baselineSpeed: 1.05,
        startedAt: startedAt,
      );
      await service.observe(cacheDurationSeconds: 10, sampledAt: startedAt);

      expect(service.state, MpvLiveLatencyChaseState.monitoring);
      expect(service.currentSpeed, 1.05);
      expect(service.lastProtectionReason, isNull);
      expect(writes, isEmpty);
    }
  });

  test('out-of-range user speed disables chasing but preserves baseline',
      () async {
    final writes = <double>[];
    final service = _service(
      writeSpeed: (speed) async => writes.add(speed),
      readSpeed: () async => 1.25,
    );
    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 10, sampledAt: startedAt);

    expect(service.isEnabled, isFalse);
    expect(service.baselineSpeed, 1.25);
    expect(writes, isEmpty);
  });

  test('does not guess a baseline when no reader or explicit value exists',
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

    expect(service.isEnabled, isFalse);
    expect(service.state, MpvLiveLatencyChaseState.disabled);
    expect(writes, isEmpty);
  });

  test('write failure disables chase and attempts baseline recovery', () async {
    final writes = <double>[];
    final service = _service(
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
    await service.observe(cacheDurationSeconds: 10, sampledAt: startedAt);

    expect(service.isEnabled, isFalse);
    expect(service.state, MpvLiveLatencyChaseState.disabled);
    expect(service.currentSpeed, 1.0);
    expect(service.isBaselineRestorePending, isFalse);
    expect(writes, [1.06, 1.0]);
  });

  test('failed baseline recovery is reported as well as catch-up failure',
      () async {
    final errors = <Object>[];
    final service = _service(
      writeSpeed: (speed) async {
        throw StateError(speed > 1 ? 'catch-up failed' : 'restore failed');
      },
      onWriteError: errors.add,
    );
    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 10, sampledAt: startedAt);

    expect(errors, hasLength(2));
    expect(errors[0].toString(), contains('catch-up failed'));
    expect(errors[1].toString(), contains('restore failed'));
    expect(service.isBaselineRestorePending, isTrue);
    expect(service.state, MpvLiveLatencyChaseState.disabled);
  });

  test('stop retries a failed baseline recovery and then clears baseline',
      () async {
    final writes = <double>[];
    var baselineWriteCount = 0;
    final service = _service(
      writeSpeed: (speed) async {
        writes.add(speed);
        if (speed > 1) {
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
    await service.observe(cacheDurationSeconds: 10, sampledAt: startedAt);
    expect(service.isBaselineRestorePending, isTrue);

    await service.stop(stoppedAt: startedAt.add(const Duration(seconds: 1)));
    expect(writes, [1.06, 1.0, 1.0]);
    expect(service.isBaselineRestorePending, isFalse);
    expect(service.state, MpvLiveLatencyChaseState.disabled);
  });

  test('a long telemetry gap resets stability and trend qualification',
      () async {
    final writes = <double>[];
    final service = _service(
      writeSpeed: (speed) async => writes.add(speed),
      stableObservationDuration: const Duration(seconds: 5),
      maximumStableSampleGap: const Duration(seconds: 3),
    );
    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    await service.observe(cacheDurationSeconds: 6, sampledAt: startedAt);
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 6)),
    );
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 8)),
    );
    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 10)),
    );

    expect(service.state, MpvLiveLatencyChaseState.monitoring);
    expect(writes, isEmpty);

    await service.observe(
      cacheDurationSeconds: 6,
      sampledAt: startedAt.add(const Duration(seconds: 11)),
    );
    expect(service.state, MpvLiveLatencyChaseState.catchingUp);
    expect(writes, [1.06]);
  });

  test('historical jitter replay keeps speeds bounded and never reopens',
      () async {
    final writes = <double>[];
    final service = _service(
      writeSpeed: (speed) async => writes.add(speed),
      minimumDwell: Duration.zero,
    );
    await service.start(
      latencyMode: 'auto',
      protocol: LiveStreamProtocol.flv,
      startedAt: startedAt,
    );
    final replay = [6.0, 5.98, 6.02, 4.2, 4.18, 3.4, 3.39, 2.5, 2.49];
    for (var index = 0; index < replay.length; index += 1) {
      await service.observe(
        cacheDurationSeconds: replay[index],
        sampledAt: startedAt.add(Duration(seconds: index * 10)),
      );
    }

    expect(writes, isNotEmpty);
    expect(writes.every((speed) => speed >= 1 && speed <= 1.06), isTrue);
    expect(service.isEnabled, isTrue);
  });
}
