import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/glass_controller.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';

double liveRoomTabIndicatorPosition(double animationValue, int tabCount) {
  if (tabCount <= 1 || !animationValue.isFinite) return 0;
  return animationValue.clamp(0.0, tabCount - 1).toDouble();
}

int liveRoomTabActiveIndex(double position, int tabCount) {
  if (tabCount <= 1) return 0;
  return position.round().clamp(0, tabCount - 1);
}

class LiveRoomTabBar extends StatefulWidget {
  const LiveRoomTabBar({
    super.key,
    required this.controller,
    required this.labels,
    required this.keys,
    required this.onTabSelected,
    this.onTabChanged,
    required this.iconBuilder,
  });

  final TabController controller;
  final List<String> labels;
  final List<String> keys;
  final ValueChanged<int> onTabSelected;
  final ValueChanged<int>? onTabChanged;
  final IconData Function(String key, bool active) iconBuilder;

  @override
  State<LiveRoomTabBar> createState() => _LiveRoomTabBarState();
}

class _LiveRoomTabBarState extends State<LiveRoomTabBar> {
  int? _lastReportedIndex;

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  @override
  void didUpdateWidget(covariant LiveRoomTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      _lastReportedIndex = null;
      _attachController();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _attachController() {
    widget.controller.addListener(_handleControllerChanged);
    _handleControllerChanged();
  }

  void _handleControllerChanged() {
    final index = widget.controller.index;
    if (_lastReportedIndex == index) return;
    _lastReportedIndex = index;
    widget.onTabChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final tabCount = math.min(
      widget.controller.length,
      math.min(widget.labels.length, widget.keys.length),
    );
    if (tabCount <= 0) return const SizedBox.shrink();

    final listenable = widget.controller.animation ?? widget.controller;
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final position = liveRoomTabIndicatorPosition(
          widget.controller.animation?.value ??
              widget.controller.index.toDouble(),
          tabCount,
        );
        if (!Get.isRegistered<AppSettingsController>()) {
          return _buildFallback(context, tabCount: tabCount, position: position);
        }
        return Obx(() {
          final settings = AppSettingsController.instance;
          final quality = AppGlassController.qualityOf(
            context,
            role: GlassSurfaceRole.navigation,
          );
          if (quality == null) {
            return _buildFallback(
              context,
              tabCount: tabCount,
              position: position,
            );
          }
          final colors = Theme.of(context).colorScheme;
          final appearance = AppGlassAppearancePolicy.resolve(
            settings.glassMode.value,
          );
          final indicatorPosition = !widget.controller.indexIsChanging &&
                  widget.controller.offset.abs() > precisionErrorTolerance
              ? position
              : null;
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: GlassTabBar.inline(
              key: const ValueKey('live-room-glass-tab-bar'),
              tabs: [
                for (var i = 0; i < tabCount; i++)
                  GlassTab(
                    icon: Icon(widget.iconBuilder(widget.keys[i], false)),
                    activeIcon: Icon(widget.iconBuilder(widget.keys[i], true)),
                    label: widget.labels[i],
                    semanticLabel: widget.labels[i],
                  ),
              ],
              selectedIndex: widget.controller.index,
              indicatorPosition: indicatorPosition,
              onTabSelected: widget.onTabSelected,
              backgroundKey: LiquidGlassScope.of(context),
              quality: quality,
              barHeight: 64,
              barBorderRadius: 28,
              iconSize: 22,
              labelFontSize: 11,
              iconLabelSpacing: 2,
              tabPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              indicatorExpansion:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              indicatorBorderRadius: 22,
              indicatorPinchStrength: 0.55,
              magnification: 1.04,
              pressScale: 1.025,
              settings: LiquidGlassSettings(
                glassColor:
                    colors.surface.withAlpha(appearance.navigationTintAlpha),
                thickness: 24,
                blur: 10,
                refractiveIndex: 1.24,
                chromaticAberration: 0.012,
                lightIntensity: 0.62,
                saturation: 1.35,
                ambientRim: 0.16,
              ),
              indicatorColor: colors.primaryContainer
                  .withAlpha(appearance.indicatorTintAlpha),
              indicatorSettings: LiquidGlassSettings(
                glassColor: colors.primaryContainer
                    .withAlpha(appearance.indicatorGlassTintAlpha),
                thickness: 34,
                blur: 7,
                refractiveIndex: 1.38,
                chromaticAberration: 0.018,
                lightIntensity: 0.78,
                saturation: 1.48,
                ambientRim: 0.28,
              ),
              selectedIconColor: colors.onPrimaryContainer,
              selectedLabelColor: colors.onPrimaryContainer,
              unselectedIconColor: colors.onSurfaceVariant,
              unselectedLabelColor: colors.onSurfaceVariant,
              selectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w500),
            ),
          );
        });
      },
    );
  }

  Widget _buildFallback(
    BuildContext context, {
    required int tabCount,
    required double position,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
                      color: colors.primary.withAlpha(
                        theme.brightness == Brightness.dark ? 52 : 24,
                      ),
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
                            label: widget.labels[i],
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => widget.onTabSelected(i),
                                borderRadius: BorderRadius.circular(18),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      widget.iconBuilder(
                                        widget.keys[i],
                                        activeIndex == i,
                                      ),
                                      size: 18,
                                      color: activeIndex == i
                                          ? colors.onPrimaryContainer
                                          : colors.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.labels[i],
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
  }
}
