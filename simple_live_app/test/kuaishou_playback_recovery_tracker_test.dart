import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/kuaishou_playback_recovery_tracker.dart';

void main() {
  group('KuaishouPlaybackRecoveryTracker', () {
    test('ignores buffering during the initial warmup', () {
      final tracker = KuaishouPlaybackRecoveryTracker();
      final start = DateTime(2026);

      tracker.beginWarmup(start);
      expect(
        tracker.updateBuffering(
          buffering: true,
          now: start.add(const Duration(seconds: 7)),
        ),
        isFalse,
      );
      expect(
        tracker.triggerContinuousBufferingRecovery(
          start.add(const Duration(seconds: 7, milliseconds: 500)),
        ),
        isFalse,
      );
    });

    test('a warmup buffer can recover after warmup when it remains active', () {
      final tracker = KuaishouPlaybackRecoveryTracker();
      final start = DateTime(2026);

      tracker.beginWarmup(start);
      tracker.updateBuffering(
        buffering: true,
        now: start,
      );
      expect(
        tracker.continuousRecoveryDelay(start),
        const Duration(seconds: 8),
      );
      expect(
        tracker.triggerContinuousBufferingRecovery(
          start.add(const Duration(seconds: 5)),
        ),
        isFalse,
      );
      expect(
        tracker.triggerContinuousBufferingRecovery(
          start.add(const Duration(seconds: 8)),
        ),
        isTrue,
      );
    });

    test('recovers on the second independent buffering edge in 30 seconds', () {
      final tracker = KuaishouPlaybackRecoveryTracker();
      final start = DateTime(2026);

      expect(tracker.updateBuffering(buffering: true, now: start), isFalse);
      expect(
        tracker.updateBuffering(
          buffering: true,
          now: start.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      tracker.updateBuffering(
        buffering: false,
        now: start.add(const Duration(seconds: 2)),
      );
      expect(
        tracker.updateBuffering(
          buffering: true,
          now: start.add(const Duration(seconds: 3)),
        ),
        isTrue,
      );
    });

    test('continuous buffering recovery is single-flight and cooled down', () {
      final tracker = KuaishouPlaybackRecoveryTracker();
      final start = DateTime(2026);

      tracker.updateBuffering(buffering: true, now: start);
      expect(
        tracker.triggerContinuousBufferingRecovery(
          start.add(const Duration(seconds: 5)),
        ),
        isTrue,
      );
      expect(
        tracker.triggerContinuousBufferingRecovery(
          start.add(const Duration(seconds: 6)),
        ),
        isFalse,
      );
      tracker.finishRecovery();
      tracker.updateBuffering(
        buffering: false,
        now: start.add(const Duration(seconds: 7)),
      );
      expect(
        tracker.updateBuffering(
          buffering: true,
          now: start.add(const Duration(seconds: 10)),
        ),
        isFalse,
      );
      expect(
        tracker.triggerContinuousBufferingRecovery(
          start.add(const Duration(seconds: 35)),
        ),
        isTrue,
      );
    });
  });
}
