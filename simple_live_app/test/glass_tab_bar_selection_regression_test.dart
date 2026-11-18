import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:liquid_glass_widgets/src/widgets/surfaces/tab_bar_bottom_internal.dart';

void main() {
  const gestureRegionKey = ValueKey<String>('glass_tab_bar_gesture_region');

  for (final placement in _TestPlacement.values) {
    testWidgets(
      '${placement.name} bar commits a tap selection on tap-up',
      (tester) async {
        final selections = <int>[];
        await tester.binding.setSurfaceSize(const Size(400, 200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: LiquidGlassScope(
              child: Center(
                child: SizedBox(
                  width: 400,
                  child: _SelectionHarness(
                    placement: placement,
                    selections: selections,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rect = tester.getRect(find.byKey(gestureRegionKey));
        final secondTabCenter =
            Offset(rect.left + rect.width * 3 / 8, rect.center.dy);
        final indicator = tester.state<TabIndicatorState>(
          find.byType(TabIndicator),
        );

        // A press only activates the indicator interaction. The host selection
        // must remain unchanged until the tap is released.
        indicator.onBarPointerDown(secondTabCenter);
        indicator.onBarTapDown(
          TapDownDetails(globalPosition: secondTabCenter),
        );
        await tester.pump();
        expect(selections, isEmpty);

        indicator.onBarTapUp(
          TapUpDetails(
            globalPosition: secondTabCenter,
            kind: PointerDeviceKind.touch,
          ),
        );
        await tester.pump();

        expect(selections, [1]);
      },
    );

    testWidgets(
      '${placement.name} bar does not fling past a tab selected during drag',
      (tester) async {
        final selections = <int>[];
        await tester.binding.setSurfaceSize(const Size(400, 200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: LiquidGlassScope(
              child: Center(
                child: SizedBox(
                  width: 400,
                  child: _SelectionHarness(
                    placement: placement,
                    selections: selections,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rect = tester.getRect(find.byKey(gestureRegionKey));
        final secondTabCenter =
            Offset(rect.left + rect.width * 3 / 8, rect.center.dy);
        final indicator = tester.state<TabIndicatorState>(
          find.byType(TabIndicator),
        );

        // A small movement wins the horizontal drag recognizer after the
        // pointer-down callback. The canceled tap must not submit its pending
        // target; drag-end remains the only selection callback.
        indicator.onBarPointerDown(secondTabCenter);
        indicator.onBarTapDown(
          TapDownDetails(globalPosition: secondTabCenter),
        );
        await tester.pump();
        expect(selections, isEmpty);

        indicator.onBarDragStart(
          DragStartDetails(globalPosition: secondTabCenter),
        );
        indicator.onBarTapCancel();
        indicator.onBarDragUpdate(
          DragUpdateDetails(
            globalPosition: secondTabCenter + const Offset(32, 0),
            delta: const Offset(32, 0),
            primaryDelta: 32,
          ),
        );
        indicator.onBarDragEnd(
          DragEndDetails(
            velocity: const Velocity(pixelsPerSecond: Offset(1000, 0)),
            primaryVelocity: 1000,
          ),
        );
        await tester.pumpAndSettle();

        expect(selections.last, 1);
      },
    );

    testWidgets(
      '${placement.name} bar drops a canceled pending tap',
      (tester) async {
        final selections = <int>[];
        await tester.binding.setSurfaceSize(const Size(400, 200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: LiquidGlassScope(
              child: Center(
                child: SizedBox(
                  width: 400,
                  child: _SelectionHarness(
                    placement: placement,
                    selections: selections,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rect = tester.getRect(find.byKey(gestureRegionKey));
        final secondTabCenter =
            Offset(rect.left + rect.width * 3 / 8, rect.center.dy);
        final indicator = tester.state<TabIndicatorState>(
          find.byType(TabIndicator),
        );

        indicator.onBarPointerDown(secondTabCenter);
        indicator.onBarTapDown(
          TapDownDetails(globalPosition: secondTabCenter),
        );
        indicator.onBarTapCancel();
        await tester.pump();

        expect(selections, isEmpty);
      },
    );

    testWidgets(
      '${placement.name} fixed-width pill stays centered in its parent',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: LiquidGlassScope(
              child: Center(
                child: SizedBox(
                  width: 400,
                  child: placement.buildBar(
                    selectedIndex: 0,
                    onSelected: (_) {},
                    quality: GlassQuality.standard,
                    tabWidth: 56,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final gestureRegion = tester.getRect(find.byKey(gestureRegionKey));
        expect(gestureRegion.width, closeTo(400, 0.5));
        expect(gestureRegion.center.dx, closeTo(200, 0.5));

        final indicator = tester.getRect(find.byType(TabIndicator));
        expect(indicator.width, closeTo(224, 0.5));
        expect(indicator.center.dx, closeTo(200, 0.5));
      },
    );
  }
}

class _SelectionHarness extends StatefulWidget {
  const _SelectionHarness({
    required this.placement,
    required this.selections,
  });

  final _TestPlacement placement;
  final List<int> selections;

  @override
  State<_SelectionHarness> createState() => _SelectionHarnessState();
}

class _SelectionHarnessState extends State<_SelectionHarness> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    void onSelected(int index) {
      widget.selections.add(index);
      setState(() => selectedIndex = index);
    }

    return widget.placement.buildBar(
      selectedIndex: selectedIndex,
      onSelected: onSelected,
    );
  }
}

enum _TestPlacement {
  inline,
  bottom;

  Widget buildBar({
    required int selectedIndex,
    required ValueChanged<int> onSelected,
    GlassQuality quality = GlassQuality.minimal,
    double? tabWidth,
  }) {
    const tabs = [
      GlassTab(icon: Icon(Icons.home), label: 'Home'),
      GlassTab(icon: Icon(Icons.favorite), label: 'Following'),
      GlassTab(icon: Icon(Icons.grid_view), label: 'Categories'),
      GlassTab(icon: Icon(Icons.person), label: 'Profile'),
    ];

    switch (this) {
      case _TestPlacement.inline:
        return GlassTabBar.inline(
          tabs: tabs,
          selectedIndex: selectedIndex,
          onTabSelected: onSelected,
          quality: quality,
          tabWidth: tabWidth,
          horizontalPadding: 0,
          verticalPadding: 0,
        );
      case _TestPlacement.bottom:
        return GlassTabBar.bottom(
          tabs: tabs,
          selectedIndex: selectedIndex,
          onTabSelected: onSelected,
          quality: quality,
          tabWidth: tabWidth,
          horizontalPadding: 0,
          verticalPadding: 0,
        );
    }
  }
}
