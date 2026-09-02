import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  const gestureRegionKey = ValueKey<String>('glass_tab_bar_gesture_region');

  for (final placement in _TestPlacement.values) {
    testWidgets(
      '${placement.name} bar does not skip a tab after dragging to its center',
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
                  child: placement.buildBar(selections.add),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final bar = find.byKey(gestureRegionKey);
        final rect = tester.getRect(bar);
        final firstTabCenter =
            Offset(rect.left + rect.width / 8, rect.center.dy);
        final oneTabDistance = rect.width / 4;

        await tester.flingFrom(
          firstTabCenter,
          Offset(oneTabDistance, 0),
          1000,
        );
        await tester.pumpAndSettle();

        expect(selections, isNotEmpty);
        expect(selections.last, 1);
      },
    );
  }
}

enum _TestPlacement {
  inline,
  bottom;

  Widget buildBar(ValueChanged<int> onSelected) {
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
          selectedIndex: 0,
          onTabSelected: onSelected,
          quality: GlassQuality.minimal,
          horizontalPadding: 0,
          verticalPadding: 0,
        );
      case _TestPlacement.bottom:
        return GlassTabBar.bottom(
          tabs: tabs,
          selectedIndex: 0,
          onTabSelected: onSelected,
          quality: GlassQuality.minimal,
          horizontalPadding: 0,
          verticalPadding: 0,
        );
    }
  }
}
