import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/services/follow_service.dart';

void main() {
  group('FollowStatusSnapshot', () {
    test('encode/decode round-trips statuses and completion time', () {
      final completedAt = DateTime.parse('2026-09-04T12:00:00.000');
      final snapshot = FollowStatusSnapshot(
        completedAt: completedAt,
        statuses: {
          'bilibili_1': 2,
          'douyin_2': 1,
          'huya_3': 0,
        },
      );

      final decoded = FollowStatusSnapshot.decode(snapshot.encode());

      expect(decoded, isNotNull);
      expect(decoded!.completedAt, completedAt);
      expect(decoded.statuses, {
        'bilibili_1': 2,
        'douyin_2': 1,
        'huya_3': 0,
      });
    });

    test('decode returns null for empty or malformed payloads', () {
      expect(FollowStatusSnapshot.decode(null), isNull);
      expect(FollowStatusSnapshot.decode(''), isNull);
      expect(FollowStatusSnapshot.decode('   '), isNull);
      expect(FollowStatusSnapshot.decode('not json'), isNull);
      expect(FollowStatusSnapshot.decode('[]'), isNull);
      expect(
        FollowStatusSnapshot.decode('{"statuses": {"a": 2}}'),
        isNull,
      );
      expect(
        FollowStatusSnapshot.decode('{"completedAt": "oops"}'),
        isNull,
      );
    });

    test('decode skips invalid status entries', () {
      final decoded = FollowStatusSnapshot.decode(
        '{"completedAt": "2026-09-04T12:00:00.000", '
        '"statuses": {"bilibili_1": 2, "douyin_2": "x", "3": 1.5}}',
      );

      expect(decoded, isNotNull);
      expect(decoded!.statuses, {'bilibili_1': 2});
    });

    test('isFreshWithin only accepts completedAt inside the window', () {
      final now = DateTime.parse('2026-09-04T12:02:00.000');
      FollowStatusSnapshot snapshotAt(DateTime completedAt) =>
          FollowStatusSnapshot(completedAt: completedAt, statuses: {});

      expect(
        snapshotAt(now.subtract(const Duration(seconds: 1)))
            .isFreshWithin(FollowService.enterRefreshReuseWindow, now: now),
        isTrue,
      );
      expect(
        snapshotAt(now.subtract(FollowService.enterRefreshReuseWindow))
            .isFreshWithin(FollowService.enterRefreshReuseWindow, now: now),
        isFalse,
      );
      expect(
        snapshotAt(now.add(const Duration(minutes: 1)))
            .isFreshWithin(FollowService.enterRefreshReuseWindow, now: now),
        isFalse,
      );
    });

    test('coversAll fails when a follow is missing from the snapshot', () {
      final followA = FollowUser(
        id: 'bilibili_1',
        roomId: '1',
        siteId: 'bilibili',
        userName: 'a',
        face: '',
        addTime: DateTime.now(),
      );
      final followB = FollowUser(
        id: 'douyin_2',
        roomId: '2',
        siteId: 'douyin',
        userName: 'b',
        face: '',
        addTime: DateTime.now(),
      );

      final full = FollowStatusSnapshot(
        completedAt: DateTime.now(),
        statuses: {'bilibili_1': 2, 'douyin_2': 1},
      );
      final partial = FollowStatusSnapshot(
        completedAt: DateTime.now(),
        statuses: {'bilibili_1': 2},
      );

      expect(full.coversAll([followA, followB]), isTrue);
      expect(partial.coversAll([followA, followB]), isFalse);
    });
  });
}
