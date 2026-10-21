import 'package:flutter/gestures.dart';
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

    for (final quality in [GlassQuality.minimal, GlassQuality.standard]) {
      testWidgets(
        '${placement.name} ${quality.name} indicator follows a slow mouse drag',
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
                    child: _ExternalPositionHarness(
                      placement: placement,
                      selections: selections,
                      quality: quality,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final alignmentFinder = find.byType(VelocitySpringBuilder);
          expect(alignmentFinder, findsOneWidget);

          final indicatorRect = tester.getRect(alignmentFinder);
          final firstTabCenter = Offset(
            indicatorRect.left + indicatorRect.width / 8,
            indicatorRect.center.dy,
          );
          final thirdTabCenter = Offset(
            indicatorRect.left + indicatorRect.width * 5 / 8,
            indicatorRect.center.dy,
          );
          expect(_renderedAlignment(tester), closeTo(-1, 0.001));

          final mouse = await tester.startGesture(
            firstTabCenter,
            kind: PointerDeviceKind.mouse,
          );
          const steps = 20;
          for (var step = 1; step <= steps; step++) {
            final progress = step / steps;
            await mouse.moveTo(
              Offset.lerp(firstTabCenter, thirdTabCenter, progress)!,
            );
            await tester.pump(const Duration(milliseconds: 50));

            if (step % 4 == 0) {
              final expectedAlignment = -1 + (4 / 3) * progress;
              expect(
                _renderedAlignment(tester),
                closeTo(expectedAlignment, 0.12),
                reason:
                    'The indicator should follow the pointer at step $step.',
              );
            }
          }

          expect(selections, isEmpty);
          await mouse.up();
          await tester.pumpAndSettle();

          expect(selections, [2]);
        },
      );
    }
  }

  testWidgets(
      'external indicator handoff starts from the last rendered position',
      (tester) async {
    var selectedIndex = 0;
    double? indicatorPosition = 0.75;
    StateSetter? rebuild;

    await tester.binding.setSurfaceSize(const Size(400, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: LiquidGlassScope(
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Center(
                child: SizedBox(
                  width: 400,
                  child: GlassTabBar.inline(
                    tabs: const [
                      GlassTab(icon: Icon(Icons.home)),
                      GlassTab(icon: Icon(Icons.favorite)),
                      GlassTab(icon: Icon(Icons.grid_view)),
                      GlassTab(icon: Icon(Icons.person)),
                    ],
                    selectedIndex: selectedIndex,
                    onTabSelected: (_) {},
                    indicatorPosition: indicatorPosition,
                    quality: GlassQuality.standard,
                    horizontalPadding: 0,
                    verticalPadding: 0,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    rebuild!(() {
      selectedIndex = 2;
      indicatorPosition = null;
    });
    await tester.pump();

    final firstFrame = _animatedAlignment(tester);
    expect(
      firstFrame,
      closeTo(-1 + 2 * 0.75 / 3, 0.05),
      reason: 'Handoff must start from the externally rendered position.',
    );

    await tester.pumpAndSettle();
    expect(_animatedAlignment(tester), closeTo(1 / 3, 0.001));
  });

  testWidgets('discrete retargeting drops obsolete spring velocity',
      (tester) async {
    var target = -1.0;
    var rendered = target;
    StateSetter? rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return VelocitySpringBuilder(
              value: target,
              springWhenActive: GlassSpring.interactive(),
              springWhenReleased: GlassSpring.smooth(
                duration: const Duration(milliseconds: 350),
              ),
              active: false,
              builder: (context, value, velocity, child) {
                rendered = value;
                return const SizedBox.shrink();
              },
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    rebuild!(() => target = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final beforeRetarget = rendered;

    rebuild!(() => target = -1 / 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final afterRetarget = rendered;

    expect(beforeRetarget, greaterThan(-1));
    expect(
      afterRetarget,
      lessThan(beforeRetarget),
      reason: 'A new discrete target must cancel the old target momentum.',
    );
    await tester.pumpAndSettle();
    expect(rendered, closeTo(-1 / 3, 0.001));
  });
}

double _renderedAlignment(WidgetTester tester) => tester
    .widget<VelocitySpringBuilder>(find.byType(VelocitySpringBuilder))
    .value;

double _animatedAlignment(WidgetTester tester) => tester
    .widget<AnimatedGlassIndicator>(find.byType(AnimatedGlassIndicator).last)
    .alignment
    .resolve(TextDirection.ltr)
    .x;

class _ExternalPositionHarness extends StatefulWidget {
  const _ExternalPositionHarness({
    required this.placement,
    required this.selections,
    required this.quality,
  });

  final _TestPlacement placement;
  final List<int> selections;
  final GlassQuality quality;

  @override
  State<_ExternalPositionHarness> createState() =>
      _ExternalPositionHarnessState();
}

class _ExternalPositionHarnessState extends State<_ExternalPositionHarness> {
  int selectedIndex = 0;
  double indicatorPosition = 0;

  @override
  Widget build(BuildContext context) {
    void onSelected(int index) {
      widget.selections.add(index);
      setState(() {
        selectedIndex = index;
        indicatorPosition = index.toDouble();
      });
    }

    return widget.placement.buildBar(
      onSelected,
      selectedIndex: selectedIndex,
      indicatorPosition: indicatorPosition,
      quality: widget.quality,
    );
  }
}

enum _TestPlacement {
  inline,
  bottom;

  Widget buildBar(
    ValueChanged<int> onSelected, {
    int selectedIndex = 0,
    double? indicatorPosition,
    GlassQuality quality = GlassQuality.minimal,
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
          indicatorPosition: indicatorPosition,
          quality: quality,
          horizontalPadding: 0,
          verticalPadding: 0,
        );
      case _TestPlacement.bottom:
        return GlassTabBar.bottom(
          tabs: tabs,
          selectedIndex: selectedIndex,
          onTabSelected: onSelected,
          quality: quality,
          horizontalPadding: 0,
          verticalPadding: 0,
        );
    }
  }
}
