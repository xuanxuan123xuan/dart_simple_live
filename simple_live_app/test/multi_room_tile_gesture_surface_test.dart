import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_tile_gesture_surface.dart';

void main() {
  Widget buildSurface({
    required VoidCallback onTogglePageOverlay,
    required VoidCallback onToggleTileControls,
    required VoidCallback onDoubleTap,
    Widget? child,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.square(
            dimension: 240,
            child: MultiRoomTileGestureSurface(
              onTogglePageOverlay: onTogglePageOverlay,
              onToggleTileControls: onToggleTileControls,
              onDoubleTap: onDoubleTap,
              child: child ??
                  const ColoredBox(
                    key: Key('tile-surface'),
                    color: Colors.black,
                  ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('single tap toggles both page and tile controls', (tester) async {
    var pageToggleCount = 0;
    var tileToggleCount = 0;
    var focusCount = 0;

    await tester.pumpWidget(
      buildSurface(
        onTogglePageOverlay: () => pageToggleCount += 1,
        onToggleTileControls: () => tileToggleCount += 1,
        onDoubleTap: () => focusCount += 1,
      ),
    );

    await tester.tap(find.byKey(const Key('tile-surface')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(pageToggleCount, 1);
    expect(tileToggleCount, 1);
    expect(focusCount, 0);
  });

  testWidgets('double tap focuses without toggling controls', (tester) async {
    var pageToggleCount = 0;
    var tileToggleCount = 0;
    var focusCount = 0;

    await tester.pumpWidget(
      buildSurface(
        onTogglePageOverlay: () => pageToggleCount += 1,
        onToggleTileControls: () => tileToggleCount += 1,
        onDoubleTap: () => focusCount += 1,
      ),
    );

    await tester.tap(find.byKey(const Key('tile-surface')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('tile-surface')));
    await tester.pumpAndSettle();

    expect(pageToggleCount, 0);
    expect(tileToggleCount, 0);
    expect(focusCount, 1);
  });

  testWidgets('a tile button does not toggle page or tile controls',
      (tester) async {
    var pageToggleCount = 0;
    var tileToggleCount = 0;
    var focusCount = 0;
    var buttonCount = 0;

    await tester.pumpWidget(
      buildSurface(
        onTogglePageOverlay: () => pageToggleCount += 1,
        onToggleTileControls: () => tileToggleCount += 1,
        onDoubleTap: () => focusCount += 1,
        child: Center(
          child: IconButton(
            onPressed: () => buttonCount += 1,
            icon: const Icon(Icons.refresh),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(buttonCount, 1);
    expect(pageToggleCount, 0);
    expect(tileToggleCount, 0);
    expect(focusCount, 0);
  });

  testWidgets('long press drag does not toggle controls or focus',
      (tester) async {
    var pageToggleCount = 0;
    var tileToggleCount = 0;
    var focusCount = 0;
    var dragStarted = false;

    await tester.pumpWidget(
      buildSurface(
        onTogglePageOverlay: () => pageToggleCount += 1,
        onToggleTileControls: () => tileToggleCount += 1,
        onDoubleTap: () => focusCount += 1,
        child: LongPressDraggable<int>(
          data: 0,
          delay: const Duration(milliseconds: 300),
          onDragStarted: () => dragStarted = true,
          feedback: const SizedBox.square(dimension: 40),
          child: const ColoredBox(color: Colors.black),
        ),
      ),
    );

    final gesture = await tester.startGesture(tester.getCenter(
      find.byType(LongPressDraggable<int>),
    ));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dragStarted, isTrue);
    expect(pageToggleCount, 0);
    expect(tileToggleCount, 0);
    expect(focusCount, 0);
  });
}
