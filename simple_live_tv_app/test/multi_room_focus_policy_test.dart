import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_focus_policy.dart';

void main() {
  group('MultiRoomFocusPolicy', () {
    test('moves through a two-column four-room grid by its visible neighbors',
        () {
      expect(
        MultiRoomFocusPolicy.nextGridIndex(
          currentIndex: 0,
          roomCount: 4,
          columnCount: 2,
          key: LogicalKeyboardKey.arrowRight,
        ),
        1,
      );
      expect(
        MultiRoomFocusPolicy.nextGridIndex(
          currentIndex: 0,
          roomCount: 4,
          columnCount: 2,
          key: LogicalKeyboardKey.arrowDown,
        ),
        2,
      );
      expect(
        MultiRoomFocusPolicy.nextGridIndex(
          currentIndex: 3,
          roomCount: 4,
          columnCount: 2,
          key: LogicalKeyboardKey.arrowUp,
        ),
        1,
      );
    });

    test('keeps focus within the room grid when an edge has no neighbor', () {
      expect(
        MultiRoomFocusPolicy.nextGridIndex(
          currentIndex: 1,
          roomCount: 3,
          columnCount: 2,
          key: LogicalKeyboardKey.arrowRight,
        ),
        isNull,
      );
      expect(
        MultiRoomFocusPolicy.nextGridIndex(
          currentIndex: 2,
          roomCount: 3,
          columnCount: 2,
          key: LogicalKeyboardKey.arrowDown,
        ),
        isNull,
      );
      expect(
        MultiRoomFocusPolicy.nextGridIndex(
          currentIndex: 4,
          roomCount: 3,
          columnCount: 2,
          key: LogicalKeyboardKey.arrowLeft,
        ),
        isNull,
      );
    });

    test('clearing expanded focus resumes all rooms', () {
      expect(
        isRoomSuspendedByFocus(roomKey: 'a', activeRoomKey: null),
        isFalse,
      );
      expect(
        isRoomSuspendedByFocus(roomKey: 'b', activeRoomKey: null),
        isFalse,
      );
    });

    test('expanded focus suspends only other rooms', () {
      expect(
        isRoomSuspendedByFocus(roomKey: 'a', activeRoomKey: 'a'),
        isFalse,
      );
      expect(
        isRoomSuspendedByFocus(roomKey: 'b', activeRoomKey: 'a'),
        isTrue,
      );
    });
  });
}
