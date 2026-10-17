import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/kuaishou_playback_recovery_tracker.dart';

void main() {
  group('KuaishouPlaybackRecoveryTracker', () {
    test('ignores buffering during the initial warmup', () {
      final tracker = KuaishouPlaybackRecoveryTracker();
      final start = DateTime(2026);

      tracker.beginWarmup(start);
      tracker.updateBuffering(
        buffering: true,
        now: start.add(const Duration(seconds: 7)),
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

    test('does not recover from repeated short buffering edges', () {
      final tracker = KuaishouPlaybackRecoveryTracker();
      final start = DateTime(2026);

      tracker.updateBuffering(buffering: true, now: start);
      tracker.updateBuffering(
        buffering: true,
        now: start.add(const Duration(seconds: 1)),
      );
      tracker.updateBuffering(
        buffering: false,
        now: start.add(const Duration(seconds: 2)),
      );
      tracker.updateBuffering(
        buffering: true,
        now: start.add(const Duration(seconds: 3)),
      );
      expect(
        tracker.triggerContinuousBufferingRecovery(
          start.add(const Duration(seconds: 7)),
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
      tracker.updateBuffering(
        buffering: true,
        now: start.add(const Duration(seconds: 10)),
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
