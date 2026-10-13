import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/modules/live_room/player/playback_stall_tracker.dart';

void main() {
  group('PlaybackStallTracker', () {
    test('recovers after non-buffering timeout but not before it', () {
      final tracker = PlaybackStallTracker();
      final start = DateTime(2026, 1, 1);

      expect(_observe(tracker, start), isFalse);
      expect(
          _observe(tracker, start.add(const Duration(seconds: 14))), isFalse);
      expect(_observe(tracker, start.add(const Duration(seconds: 15))), isTrue);
      expect(tracker.recoveryAttempts, 1);
    });

    test('buffering uses the longer timeout', () {
      final tracker = PlaybackStallTracker();
      final start = DateTime(2026, 1, 1);

      expect(_observe(tracker, start, buffering: true), isFalse);
      expect(
        _observe(
          tracker,
          start.add(const Duration(seconds: 29)),
          buffering: true,
        ),
        isFalse,
      );
      expect(
        _observe(
          tracker,
          start.add(const Duration(seconds: 30)),
          buffering: true,
        ),
        isTrue,
      );
    });

    test('pause completion and source change never inherit a stall', () {
      final tracker = PlaybackStallTracker();
      final start = DateTime(2026, 1, 1);
      _observe(tracker, start);

      expect(
        _observe(
          tracker,
          start.add(const Duration(seconds: 20)),
          playing: false,
        ),
        isFalse,
      );
      expect(
        _observe(
          tracker,
          start.add(const Duration(seconds: 40)),
          source: 'https://other/live.flv',
        ),
        isFalse,
      );
      expect(
        _observe(
          tracker,
          start.add(const Duration(seconds: 60)),
          completed: true,
        ),
        isFalse,
      );
    });

    test('reopening the same logical source keeps its recovery budget', () {
      final tracker = PlaybackStallTracker();
      final start = DateTime(2026, 1, 1);
      _observe(tracker, start);
      expect(
        _observe(tracker, start.add(const Duration(seconds: 15))),
        isTrue,
      );

      expect(
        _observe(
          tracker,
          start.add(const Duration(seconds: 16)),
          generation: 2,
        ),
        isFalse,
      );
      expect(tracker.recoveryAttempts, 1);
    });

    test('limits retries and resets after stable progress', () {
      final tracker = PlaybackStallTracker();
      final start = DateTime(2026, 1, 1);
      _observe(tracker, start);
      for (var attempt = 1; attempt <= 3; attempt++) {
        expect(
          _observe(
            tracker,
            start.add(Duration(seconds: attempt * 15)),
          ),
          isTrue,
        );
      }
      expect(
        _observe(tracker, start.add(const Duration(seconds: 60))),
        isFalse,
      );

      _observe(
        tracker,
        start.add(const Duration(seconds: 61)),
        position: const Duration(seconds: 1),
      );
      _observe(
        tracker,
        start.add(const Duration(seconds: 92)),
        position: const Duration(seconds: 2),
      );
      expect(tracker.recoveryAttempts, 0);
    });

    test(
        'direct player recovery clears after 30 seconds without using stall budget',
        () {
      final tracker = PlaybackStallTracker();
      final start = DateTime(2026, 1, 1);
      _observe(tracker, start, recoveryPending: true);
      _observe(
        tracker,
        start.add(const Duration(seconds: 1)),
        position: const Duration(seconds: 1),
        recoveryPending: true,
      );
      _observe(
        tracker,
        start.add(const Duration(seconds: 30)),
        position: const Duration(seconds: 30),
        recoveryPending: true,
      );
      expect(tracker.stableRecoveryCompleted, isFalse);
      expect(tracker.recoveryAttempts, 0);
      _observe(
        tracker,
        start.add(const Duration(seconds: 31)),
        position: const Duration(seconds: 31),
        recoveryPending: true,
      );
      expect(tracker.stableRecoveryCompleted, isTrue);
      expect(tracker.recoveryAttempts, 0);
    });

    test('blocked recovery watches stable progress without spending retries',
        () {
      final tracker = PlaybackStallTracker();
      final start = DateTime(2026, 1, 1);
      _observe(tracker, start, recoveryPending: true, allowRecovery: false);
      expect(
        _observe(
          tracker,
          start.add(const Duration(seconds: 20)),
          recoveryPending: true,
          allowRecovery: false,
        ),
        isFalse,
      );
      expect(tracker.recoveryAttempts, 0);
      _observe(
        tracker,
        start.add(const Duration(seconds: 21)),
        position: const Duration(seconds: 1),
        recoveryPending: true,
        allowRecovery: false,
      );
      _observe(
        tracker,
        start.add(const Duration(seconds: 51)),
        position: const Duration(seconds: 2),
        recoveryPending: true,
        allowRecovery: false,
      );
      expect(tracker.stableRecoveryCompleted, isTrue);
      expect(tracker.recoveryAttempts, 0);
    });
  });
}

bool _observe(
  PlaybackStallTracker tracker,
  DateTime now, {
  String source = 'https://example.com/live.flv',
  Duration position = Duration.zero,
  bool playing = true,
  bool buffering = false,
  int generation = 1,
  bool completed = false,
  bool recoveryPending = false,
  bool allowRecovery = true,
}) {
  return tracker.observe(
    now: now,
    generation: generation,
    source: source,
    position: position,
    playing: playing,
    buffering: buffering,
    completed: completed,
    recoveryPending: recoveryPending,
    allowRecovery: allowRecovery,
  );
}
