import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_page.dart';

void main() {
  group('LiveRoomShortcut', () {
    test('maps the remote menu key to multi-room playback', () {
      expect(
        resolveLiveRoomShortcut(LogicalKeyboardKey.contextMenu),
        LiveRoomShortcut.multiRoom,
      );
    });

    test('keeps the right key as the player settings shortcut', () {
      expect(
        resolveLiveRoomShortcut(LogicalKeyboardKey.arrowRight),
        LiveRoomShortcut.settings,
      );
    });

    test('leaves unrelated keys unmapped', () {
      expect(
        resolveLiveRoomShortcut(LogicalKeyboardKey.arrowLeft),
        LiveRoomShortcut.none,
      );
    });
  });
}
