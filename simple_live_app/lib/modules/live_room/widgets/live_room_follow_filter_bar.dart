import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/glass_controller.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';

class LiveRoomFollowFilterBar extends StatelessWidget {
  const LiveRoomFollowFilterBar({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  static const labels = <String>['全部', '直播中', '未开播'];

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  int get _activeIndex =>
      selectedIndex.clamp(0, labels.length - 1).toInt();

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<AppSettingsController>()) {
      return _buildFallback(context);
    }
    return Obx(() {
      final settings = AppSettingsController.instance;
      final quality = AppGlassController.qualityOf(
        context,
        role: GlassSurfaceRole.navigation,
      );
      if (quality == null) {
        return _buildFallback(context);
      }

      final colors = Theme.of(context).colorScheme;
      final appearance = AppGlassAppearancePolicy.resolve(
        settings.glassMode.value,
      );
      return SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GlassTabBar.inline(
            key: const ValueKey('live-room-follow-filter-glass-tab-bar'),
            tabs: [
              for (final label in labels)
                GlassTab(label: label, semanticLabel: label),
            ],
            selectedIndex: _activeIndex,
            onTabSelected: onSelected,
            backgroundKey: LiquidGlassScope.of(context),
            quality: quality,
            barHeight: 48,
            barBorderRadius: 24,
            labelFontSize: 13,
            tabPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            indicatorExpansion:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            indicatorBorderRadius: 20,
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
            selectedLabelColor: colors.onPrimaryContainer,
            unselectedLabelColor: colors.onSurfaceVariant,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      );
    });
  }

  Widget _buildFallback(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final neutralBorder =
        (theme.brightness == Brightness.dark ? Colors.white : Colors.black)
            .withAlpha(theme.brightness == Brightness.dark ? 42 : 28);

    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          key: const ValueKey('live-room-follow-filter-fallback'),
          color: colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: neutralBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 48,
            child: LayoutBuilder(
              builder: (context, constraints) {
              final slotWidth = constraints.maxWidth / labels.length;
              final indicatorLeft = slotWidth * _activeIndex + 2;
              final indicatorWidth = math.max(0.0, slotWidth - 4).toDouble();
              return Stack(
                children: [
                  AnimatedPositioned(
                    key: const ValueKey(
                      'live-room-follow-filter-fallback-indicator',
                    ),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    left: indicatorLeft,
                    top: 2,
                    bottom: 2,
                    width: indicatorWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primary.withAlpha(
                          theme.brightness == Brightness.dark ? 52 : 24,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colors.primary.withAlpha(150),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      children: [
                        for (var i = 0; i < labels.length; i++)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: _activeIndex == i,
                              label: labels[i],
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => onSelected(i),
                                  child: Center(
                                    child: Text(
                                      labels[i],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: _activeIndex == i
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: _activeIndex == i
                                            ? colors.onPrimaryContainer
                                            : colors.onSurfaceVariant,
                                      ),
                                    ),
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
        ),
      ),
    );
  }
}
