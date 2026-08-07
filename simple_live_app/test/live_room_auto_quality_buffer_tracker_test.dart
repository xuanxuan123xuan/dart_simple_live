import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/live_room_auto_quality_buffer_tracker.dart';

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
  });
}
