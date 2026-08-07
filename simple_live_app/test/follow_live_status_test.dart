import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  test('unknown follow refresh preserves the previous status', () {
    expect(followStatusForLiveState(LiveStatusState.live), 2);
    expect(followStatusForLiveState(LiveStatusState.offline), 1);
    expect(followStatusForLiveState(LiveStatusState.unknown), isNull);
  });

  group('KuaishouFollowRefreshLimiter', () {
    test('fixed single-flight: initialConcurrency is 1', () {
      final limiter = KuaishouFollowRefreshLimiter.forTargetCount(50);
      expect(limiter.initialConcurrency, 1);
      expect(limiter.initialInterval, greaterThan(Duration.zero));
    });

    test('serializes concurrent requests with a minimum interval', () async {
      final limiter = KuaishouFollowRefreshLimiter.forTargetCount(3);
      final timestamps = <DateTime>[];
      Future<void> acquire(int workerIndex) async {
        await limiter.beforeRequest(workerIndex);
        timestamps.add(DateTime.now());
      }

      await Future.wait([acquire(0), acquire(1), acquire(2)]);
      expect(timestamps.length, 3);
      final interval = limiter.initialInterval;
      const schedulingTolerance = Duration(milliseconds: 10);
      final observedMinimum = interval - schedulingTolerance;
      for (var i = 1; i < timestamps.length; i++) {
        final diff = timestamps[i].difference(timestamps[i - 1]);
        expect(
          diff,
          greaterThanOrEqualTo(observedMinimum),
          reason: '第 $i 个快手状态请求未串行发出: $diff',
        );
      }
    });

    test('onLimited grows the interval up to the clamp ceiling', () {
      final limiter = KuaishouFollowRefreshLimiter.forTargetCount(2);
      for (var i = 0; i < 5; i++) {
        limiter.onLimited();
      }
      final summary = limiter.finish(2);
      expect(summary.limitedCount, 5);
      expect(summary.cooledDown, isTrue);
      expect(summary.finalInterval,
          lessThanOrEqualTo(const Duration(milliseconds: 2600)));
      expect(summary.finalInterval, greaterThan(summary.initialInterval));
    });
  });
}
