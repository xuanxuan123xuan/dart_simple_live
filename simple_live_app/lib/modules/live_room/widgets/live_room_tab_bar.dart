import 'dart:math' as math;

import 'package:flutter/material.dart';

double liveRoomTabIndicatorPosition(double animationValue, int tabCount) {
  if (tabCount <= 1 || !animationValue.isFinite) return 0;
  return animationValue.clamp(0.0, tabCount - 1).toDouble();
}

int liveRoomTabActiveIndex(double position, int tabCount) {
  if (tabCount <= 1) return 0;
  return position.round().clamp(0, tabCount - 1);
}

class LiveRoomTabBar extends StatelessWidget {
  const LiveRoomTabBar({
    super.key,
    required this.controller,
    required this.labels,
    required this.keys,
    required this.onTabSelected,
    required this.iconBuilder,
  });

  final TabController controller;
  final List<String> labels;
  final List<String> keys;
  final ValueChanged<int> onTabSelected;
  final IconData Function(String key, bool active) iconBuilder;

  @override
  Widget build(BuildContext context) {
    final tabCount = math.min(
      controller.length,
      math.min(labels.length, keys.length),
    );
    if (tabCount <= 0) return const SizedBox.shrink();

    final listenable = controller.animation ?? controller;
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final position = liveRoomTabIndicatorPosition(
          controller.animation?.value ?? controller.index.toDouble(),
          tabCount,
        );
        final activeIndex = liveRoomTabActiveIndex(position, tabCount);

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: SizedBox(
            height: 48,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final slotWidth = constraints.maxWidth / tabCount;
                final indicatorLeft = slotWidth * position + 2;
                final indicatorWidth = math.max(0.0, slotWidth - 4).toDouble();
                return Stack(
                  children: [
                    Positioned(
                      key: const ValueKey('live-room-tab-indicator-position'),
                      left: indicatorLeft,
                      top: 0,
                      bottom: 0,
                      width: indicatorWidth,
                      child: DecoratedBox(
                        key: const ValueKey('live-room-tab-indicator'),
                        decoration: BoxDecoration(
                          color: colors.primary.withAlpha(isDark ? 52 : 24),
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Row(
                        children: [
                          for (var i = 0; i < tabCount; i++)
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: activeIndex == i,
                                label: labels[i],
                                child: Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(18),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () => onTabSelected(i),
                                    borderRadius: BorderRadius.circular(18),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          iconBuilder(keys[i], activeIndex == i),
                                          size: 18,
                                          color: activeIndex == i
                                              ? colors.onPrimaryContainer
                                              : colors.onSurfaceVariant,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          labels[i],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: activeIndex == i
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: activeIndex == i
                                                ? colors.onPrimaryContainer
                                                : colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
