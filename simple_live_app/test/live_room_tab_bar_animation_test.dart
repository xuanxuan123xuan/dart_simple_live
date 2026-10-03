import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/widgets/live_room_tab_bar.dart';

void main() {
  test('indicator position clamps controller animation values', () {
    expect(liveRoomTabIndicatorPosition(-1, 3), 0);
    expect(liveRoomTabIndicatorPosition(1.25, 3), 1.25);
    expect(liveRoomTabIndicatorPosition(5, 3), 2);
    expect(liveRoomTabIndicatorPosition(1, 1), 0);
  });

  test('active index rounds to the nearest tab', () {
    expect(liveRoomTabActiveIndex(0.0, 3), 0);
    expect(liveRoomTabActiveIndex(1.4, 3), 1);
    expect(liveRoomTabActiveIndex(1.6, 3), 2);
    expect(liveRoomTabActiveIndex(3, 3), 2);
    expect(liveRoomTabActiveIndex(-0.5, 3), 0);
  });

  testWidgets(
    'indicator follows a fractional page position before index changes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      TabController? controller;
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 3,
            child: Builder(
              builder: (context) {
                controller = DefaultTabController.of(context);
                return Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 300,
                    child: LiveRoomTabBar(
                      controller: controller!,
                      labels: const ['聊天', 'SC', '设置'],
                      keys: const ['chat', 'super_chat', 'settings'],
                      onTabSelected: (_) {},
                      iconBuilder: (_, active) =>
                          active ? Icons.circle : Icons.circle_outlined,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      final indicator = find.byKey(const ValueKey('live-room-tab-indicator'));
      final initialRect = tester.getRect(indicator);
      expect(controller!.index, 0);

      controller!.offset = 0.25;
      await tester.pump();

      final draggedRect = tester.getRect(indicator);
      // The selection index does not change yet — this is a mid-drag frame.
      expect(controller!.index, 0);
      // The indicator tracks the drag, sliding right by a fraction of a slot.
      expect(draggedRect.left, greaterThan(initialRect.left));
      // The indicator keeps the same size while tracking the drag.
      expect(draggedRect.width, closeTo(initialRect.width, 0.01));
    },
  );

  testWidgets('single tab keeps the indicator inside its slot', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    TabController? controller;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 1,
          child: Builder(
            builder: (context) {
              controller = DefaultTabController.of(context);
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 120,
                  child: LiveRoomTabBar(
                    controller: controller!,
                    labels: const ['聊天'],
                    keys: const ['chat'],
                    onTabSelected: (_) {},
                    iconBuilder: (_, active) =>
                        active ? Icons.circle : Icons.circle_outlined,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final indicatorRect = tester.getRect(
      find.byKey(const ValueKey('live-room-tab-indicator')),
    );
    // The horizontal padding (8+8) leaves a 104px slot; two 2px insets remain.
    expect(indicatorRect.width, closeTo((120 - 16) - 4, 0.01));
    expect(indicatorRect.left, closeTo(10, 0.01));
  });
}
