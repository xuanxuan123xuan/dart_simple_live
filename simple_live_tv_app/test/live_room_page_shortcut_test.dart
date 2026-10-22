import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_page.dart';

void main() {
  group('LiveRoomShortcut', () {
    test('leaves the remote menu key for press-duration handling', () {
      expect(
        resolveLiveRoomShortcut(LogicalKeyboardKey.contextMenu),
        LiveRoomShortcut.none,
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

  testWidgets('short menu press refreshes once', (tester) async {
    var refreshes = 0;
    var multiRoomOpens = 0;
    final gesture = TvMenuKeyGesture(
      onShortPress: () => refreshes++,
      onLongPress: () => multiRoomOpens++,
    );
    addTearDown(gesture.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: (_, event) => gesture.handle(event),
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump(const Duration(milliseconds: 599));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.contextMenu);

    expect(refreshes, 1);
    expect(multiRoomOpens, 0);
  });

  testWidgets('long menu press opens multi-room once and does not refresh',
      (tester) async {
    var refreshes = 0;
    var multiRoomOpens = 0;
    final gesture = TvMenuKeyGesture(
      onShortPress: () => refreshes++,
      onLongPress: () => multiRoomOpens++,
    );
    addTearDown(gesture.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: (_, event) => gesture.handle(event),
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.contextMenu);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.contextMenu);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.contextMenu);

    expect(refreshes, 0);
    expect(multiRoomOpens, 1);
  });

  testWidgets('cancelled menu press does not fire after the timer expires',
      (tester) async {
    var refreshes = 0;
    var multiRoomOpens = 0;
    final gesture = TvMenuKeyGesture(
      onShortPress: () => refreshes++,
      onLongPress: () => multiRoomOpens++,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: (_, event) => gesture.handle(event),
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.contextMenu);
    gesture.cancel();
    await tester.pump(const Duration(milliseconds: 600));

    expect(refreshes, 0);
    expect(multiRoomOpens, 0);
    gesture.dispose();
  });
}
