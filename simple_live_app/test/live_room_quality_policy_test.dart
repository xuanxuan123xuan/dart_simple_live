import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';

void main() {
  group('live room quality preference', () {
    test('restores a persisted manual quality selection', () {
      final preference = LiveRoomQualityPreference.fromStoredValue(const {
        'quality': 2,
        'line': 1,
        'qualityLocked': true,
      });

      expect(preference.qualityLocked, isTrue);
      expect(preference.lineIndex, 1);
      expect(
        resolveInitialLiveRoomQualityIndex(
          qualityCount: 4,
          qualityLevel: 2,
          preference: preference,
        ),
        2,
      );
    });

    test('automatic mode ignores a stale quality index', () {
      final preference = LiveRoomQualityPreference.fromStoredValue(const {
        'quality': 0,
        'qualityLocked': false,
      });

      expect(preference.qualityLocked, isFalse);
      expect(
        resolveInitialLiveRoomQualityIndex(
          qualityCount: 4,
          qualityLevel: 1,
          preference: preference,
        ),
        2,
      );
    });

    test('migrates a legacy remembered quality as manual', () {
      final preference = LiveRoomQualityPreference.fromStoredValue(const {
        'quality': 1,
      });

      expect(preference.qualityLocked, isTrue);
      expect(preference.qualityIndex, 1);
    });

    test('invalid manual index falls back to the automatic setting', () {
      final preference = LiveRoomQualityPreference.fromStoredValue(const {
        'quality': 8,
        'qualityLocked': true,
      });

      expect(
        resolveInitialLiveRoomQualityIndex(
          qualityCount: 3,
          qualityLevel: 0,
          preference: preference,
        ),
        2,
      );
    });

    test('restores a line by host and latency tier after URL reordering', () {
      const preference = LiveRoomQualityPreference(
        qualityIndex: null,
        lineIndex: 0,
        lineSignature: 'preferred.example.com|0',
        qualityLocked: false,
      );
      final urls = [
        'https://other.example.com/live.m3u8',
        'https://fallback.example.com/live.flv',
        'https://preferred.example.com/live.flv',
      ];

      expect(
        resolveRememberedLiveRoomLineIndex(
          urls: urls,
          preference: preference,
        ),
        2,
      );
    });

    test('legacy line index remains usable until a manual migration', () {
      final preference = LiveRoomQualityPreference.fromStoredValue(const {
        'line': 2,
      });
      final urls = [
        'https://high.example.com/live.m3u8',
        'https://first.example.com/live.flv',
        'https://second.example.com/live.flv',
      ];

      expect(
        resolveRememberedLiveRoomLineIndex(
          urls: urls,
          preference: preference,
        ),
        2,
      );
    });

    test('a stale signature does not fall back to its old list index', () {
      const preference = LiveRoomQualityPreference(
        qualityIndex: null,
        lineIndex: 1,
        lineSignature: 'removed.example.com|0',
        qualityLocked: false,
      );

      expect(
        resolveRememberedLiveRoomLineIndex(
          urls: const [
            'https://first.example.com/live.flv',
            'https://second.example.com/live.flv',
          ],
          preference: preference,
        ),
        isNull,
      );
    });

    test('line signature normalizes the host and uses the protocol tier', () {
      expect(
        liveRoomLineMemorySignature('https://CDN.example.com/live.flv'),
        'cdn.example.com|0',
      );
      expect(
        liveRoomLineProtocolLabel('https://cdn.example.com/live.m3u8'),
        'HLS',
      );
    });
  });

  group('single room automatic quality buffering', () {
    test('ignores startup buffering and counts distinct later starts', () {
      final tracker = LiveRoomAutoQualityBufferTracker();
      final start = DateTime(2026);
      tracker.beginWarmup(start);

      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 2)),
        ),
        isFalse,
      );
      tracker.update(
        buffering: false,
        now: start.add(const Duration(seconds: 3)),
      );

      for (var seconds in const [9, 11]) {
        expect(
          tracker.update(
            buffering: true,
            now: start.add(Duration(seconds: seconds)),
          ),
          isFalse,
        );
        tracker.update(
          buffering: false,
          now: start.add(Duration(seconds: seconds + 1)),
        );
      }
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 13)),
        ),
        isTrue,
      );
    });

    test('stable playback breaks a buffering sequence', () {
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
          now: start.add(const Duration(seconds: 3)),
        ),
        isFalse,
      );
      tracker.update(
        buffering: false,
        now: start.add(const Duration(seconds: 4)),
      );

      // Eight stable seconds reset the previous two starts.
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 12)),
        ),
        isFalse,
      );
      tracker.update(
        buffering: false,
        now: start.add(const Duration(seconds: 13)),
      );
      expect(
        tracker.update(
          buffering: true,
          now: start.add(const Duration(seconds: 14)),
        ),
        isFalse,
      );
    });

    test('buffering starts outside the time window do not accumulate', () {
      final tracker = LiveRoomAutoQualityBufferTracker(
        stableResetAfter: const Duration(minutes: 1),
      );
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
  });

  group('live room playback request revision', () {
    test('accepts only the latest request in the current room generation', () {
      expect(
        isCurrentLiveRoomPlaybackRequest(
          roomGeneration: 4,
          expectedRoomGeneration: 4,
          requestRevision: 7,
          latestRequestRevision: 7,
        ),
        isTrue,
      );
      expect(
        isCurrentLiveRoomPlaybackRequest(
          roomGeneration: 4,
          expectedRoomGeneration: 4,
          requestRevision: 6,
          latestRequestRevision: 7,
        ),
        isFalse,
      );
    });

    test('rejects a request after switching rooms', () {
      expect(
        isCurrentLiveRoomPlaybackRequest(
          roomGeneration: 5,
          expectedRoomGeneration: 4,
          requestRevision: 7,
          latestRequestRevision: 7,
        ),
        isFalse,
      );
    });
  });
}
