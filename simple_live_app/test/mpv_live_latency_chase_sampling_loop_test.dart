import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/mpv_live_latency_chase_sampling_loop.dart';

class _ScheduledCall {
  _ScheduledCall(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  bool cancelled = false;

  void fire() {
    if (!cancelled) callback();
  }
}

void main() {
  test('one cadence selects chase ticks without passing the health deadline',
      () {
    final now = DateTime(2026, 8, 9, 12);
    expect(
      MpvLiveLatencyChaseSamplingLoop.nextDelay(
        chaseInterval: const Duration(milliseconds: 500),
        healthDueAt: now.add(const Duration(seconds: 1)),
        now: now,
      ),
      const Duration(milliseconds: 500),
    );
    expect(
      MpvLiveLatencyChaseSamplingLoop.nextDelay(
        chaseInterval: const Duration(seconds: 2),
        healthDueAt: now.add(const Duration(milliseconds: 300)),
        now: now,
      ),
      const Duration(milliseconds: 300),
    );
    expect(
      MpvLiveLatencyChaseSamplingLoop.nextDelay(
        chaseInterval: null,
        healthDueAt: now.add(const Duration(seconds: 5)),
        now: now,
      ),
      const Duration(seconds: 5),
    );
  });

  test('waits for each sample before using the latest dynamic interval',
      () async {
    final scheduled = <_ScheduledCall>[];
    final firstSample = Completer<void>();
    var sampleCount = 0;
    var interval = const Duration(seconds: 2);
    final loop = MpvLiveLatencyChaseSamplingLoop(
      sample: () {
        sampleCount += 1;
        return sampleCount == 1 ? firstSample.future : Future<void>.value();
      },
      nextInterval: () => interval,
      schedule: (delay, callback) {
        final call = _ScheduledCall(delay, callback);
        scheduled.add(call);
        return () => call.cancelled = true;
      },
    );

    loop.start();
    expect(sampleCount, 1);
    expect(loop.isSampleInFlight, isTrue);
    expect(scheduled, isEmpty);

    interval = const Duration(milliseconds: 500);
    firstSample.complete();
    await Future<void>.delayed(Duration.zero);
    expect(loop.isSampleInFlight, isFalse);
    expect(scheduled.single.delay, const Duration(milliseconds: 500));

    scheduled.single.fire();
    await Future<void>.delayed(Duration.zero);
    expect(sampleCount, 2);
    expect(scheduled.last.delay, const Duration(milliseconds: 500));
  });

  test('stop invalidates an in-flight sample and prevents rescheduling',
      () async {
    final scheduled = <_ScheduledCall>[];
    final sampleGate = Completer<void>();
    final loop = MpvLiveLatencyChaseSamplingLoop(
      sample: () => sampleGate.future,
      nextInterval: () => const Duration(seconds: 1),
      schedule: (delay, callback) {
        final call = _ScheduledCall(delay, callback);
        scheduled.add(call);
        return () => call.cancelled = true;
      },
    );

    loop.start();
    loop.stop();
    sampleGate.complete();
    await Future<void>.delayed(Duration.zero);

    expect(loop.isActive, isFalse);
    expect(loop.isSampleInFlight, isFalse);
    expect(scheduled, isEmpty);
  });

  test('restart during an in-flight sample hands off without overlap',
      () async {
    final firstSample = Completer<void>();
    var inFlight = 0;
    var maximumInFlight = 0;
    var sampleCount = 0;
    final loop = MpvLiveLatencyChaseSamplingLoop(
      sample: () async {
        sampleCount += 1;
        inFlight += 1;
        if (inFlight > maximumInFlight) maximumInFlight = inFlight;
        if (sampleCount == 1) await firstSample.future;
        inFlight -= 1;
      },
      nextInterval: () => const Duration(seconds: 1),
      schedule: (_, __) => () {},
    );

    loop.start();
    expect(sampleCount, 1);
    loop.start();
    expect(sampleCount, 1);

    firstSample.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(sampleCount, 2);
    expect(maximumInFlight, 1);
    expect(loop.isActive, isTrue);
  });

  test('a null recommendation ends the loop without installing a timer',
      () async {
    var scheduled = false;
    final loop = MpvLiveLatencyChaseSamplingLoop(
      sample: () async {},
      nextInterval: () => null,
      schedule: (_, __) {
        scheduled = true;
        return () {};
      },
    );

    loop.start();
    await Future<void>.delayed(Duration.zero);

    expect(loop.isActive, isFalse);
    expect(scheduled, isFalse);
  });
}
