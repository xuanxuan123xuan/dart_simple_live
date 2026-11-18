import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/live_room_auto_quality_buffer_tracker.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';

void main() {
  group('LiveRoomAutoQualityBufferTracker', () {
    test('warmup ignores starts before the deadline and counts at it', () {
      final tracker = LiveRoomAutoQualityBufferTracker(
        requiredBufferStarts: 1,
        warmupDuration: const Duration(seconds: 8),
      );
      final start = DateTime(2026);

      tracker.beginWarmup(start);
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 7)),
        ),
        isFalse,
      );
      tracker.update(
        buffering: false,
        now: start.add(const Duration(seconds: 7, milliseconds: 500)),
      );
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 8)),
        ),
        isTrue,
      );
    });

    test('reset clears an active warmup window', () {
      final tracker = LiveRoomAutoQualityBufferTracker(
        requiredBufferStarts: 1,
        warmupDuration: const Duration(seconds: 8),
      );
      final start = DateTime(2026);

      tracker.beginWarmup(start);
      tracker.reset();

      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('counts only false-to-true buffering edges', () {
      final tracker = LiveRoomAutoQualityBufferTracker(
        requiredBufferStarts: 2,
      );
      final start = DateTime(2026);

      expect(tracker.update(buffering: true, now: start), isFalse);
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      tracker.update(
        buffering: false,
        now: start.add(const Duration(seconds: 2)),
      );
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 3)),
        ),
        isTrue,
      );
    });

    test('default threshold triggers for buffering starts 10 seconds apart',
        () {
      final tracker = LiveRoomAutoQualityBufferTracker();
      final start = DateTime(2026);

      expect(tracker.update(buffering: true, now: start), isFalse);
      expect(
        tracker.update(
          buffering: false,
          now: start.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 10)),
        ),
        isTrue,
      );
      tracker.update(
        buffering: false,
        now: start.add(const Duration(seconds: 11)),
      );
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 20)),
        ),
        isFalse,
      );
    });

    test('starts outside the buffering window do not trigger', () {
      final tracker = LiveRoomAutoQualityBufferTracker();
      final start = DateTime(2026);

      expect(tracker.update(buffering: true, now: start), isFalse);
      tracker.update(
        buffering: false,
        now: start.add(const Duration(seconds: 1)),
      );
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 31)),
        ),
        isFalse,
      );
    });

    test('a repeated true does not trigger a second action', () {
      final tracker = LiveRoomAutoQualityBufferTracker();
      final start = DateTime(2026);

      expect(tracker.update(buffering: true, now: start), isFalse);
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(
        tracker.update(
          buffering: false,
          now: start.add(const Duration(seconds: 2)),
        ),
        isFalse,
      );
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 3)),
        ),
        isTrue,
      );
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 4)),
        ),
        isFalse,
      );
    });

    test('reset clears the current buffering edge', () {
      final tracker = LiveRoomAutoQualityBufferTracker(
        requiredBufferStarts: 1,
      );
      final start = DateTime(2026);

      expect(tracker.update(buffering: true, now: start), isTrue);
      tracker.reset();

      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test(
        'stream opening warmup starts once per session and resets with session',
        () {
      final controller = PlayerController();
      final start = DateTime(2026);

      expect(controller.markStreamOpening(now: start), isTrue);
      expect(
        controller.markStreamOpening(
          now: start.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );

      controller.resetAutoNetworkDiagnosisSession();
      expect(
        controller.markStreamOpening(
          now: start.add(const Duration(seconds: 2)),
        ),
        isTrue,
      );
    });
  });
}
