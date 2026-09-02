import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/glass_controller.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/app/platform_utils.dart';
import 'package:simple_live_app/app/sites.dart';

/// Site selector with the same focused glass indicator used by the bottom
/// navigation bar. It stays synchronized with horizontal [TabBarView] swipes.
class SiteGlassTabBar extends StatelessWidget {
  const SiteGlassTabBar({
    required this.controller,
    this.iconOnly,
    super.key,
  });

  final TabController controller;
  final bool? iconOnly;

  bool _iconOnlyFor(BuildContext context) =>
      iconOnly ??
      (PlatformUtils.isMobileApp &&
          MediaQuery.sizeOf(context).shortestSide < 600);

  @override
  Widget build(BuildContext context) {
    final compact = _iconOnlyFor(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!Get.isRegistered<AppSettingsController>()) {
          return _buildFallback(context, iconOnly: compact);
        }
        return Obx(() {
          final mode = AppSettingsController.instance.glassMode.value;
          final quality = AppGlassController.qualityOf(
            context,
            role: GlassSurfaceRole.navigation,
          );
          if (quality == null) {
            return _buildFallback(context, iconOnly: compact);
          }
          return _buildGlass(
            context,
            quality,
            AppGlassAppearancePolicy.resolve(mode),
            compact,
          );
        });
      },
    );
  }

  Widget _buildGlass(
    BuildContext context,
    GlassQuality quality,
    AppGlassAppearanceProfile appearance,
    bool iconOnly,
  ) {
    final colors = Theme.of(context).colorScheme;
    return GlassTabBar.inline(
      key: const ValueKey<String>('site-glass-tab-bar'),
      tabs: [
        for (final site in Sites.supportSites)
          GlassTab(
            icon: Image.asset(site.logo, width: 21, height: 21),
            label: iconOnly ? null : site.name,
            semanticLabel: site.name,
          ),
      ],
      selectedIndex: controller.index,
      onTabSelected: controller.animateTo,
      backgroundKey: LiquidGlassScope.of(context),
      quality: quality,
      barHeight: iconOnly ? 56 : 48,
      barBorderRadius: iconOnly ? 28 : 24,
      tabWidth: iconOnly ? 56 : 112,
      iconSize: iconOnly ? 24 : 21,
      labelFontSize: 13,
      iconLabelSpacing: iconOnly ? 0 : 6,
      tabPadding: iconOnly
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      indicatorExpansion: iconOnly
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      indicatorBorderRadius: iconOnly ? 26 : 20,
      indicatorPinchStrength: 0.55,
      magnification: iconOnly ? 1.02 : 1.04,
      pressScale: 1.025,
      settings: LiquidGlassSettings(
        glassColor: colors.surface.withAlpha(appearance.navigationTintAlpha),
        thickness: 24,
        blur: 10,
        refractiveIndex: 1.24,
        chromaticAberration: 0.012,
        lightIntensity: 0.62,
        saturation: 1.35,
        ambientRim: 0.16,
      ),
      indicatorColor:
          colors.primaryContainer.withAlpha(appearance.indicatorTintAlpha),
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
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
    );
  }

  Widget _buildFallback(BuildContext context, {required bool iconOnly}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final neutralBorder =
        (theme.brightness == Brightness.dark ? Colors.white : Colors.black)
            .withAlpha(theme.brightness == Brightness.dark ? 42 : 28);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : Sites.supportSites.length * (iconOnly ? 56.0 : 112.0);
        final maxTabWidth = iconOnly ? 56.0 : 112.0;
        final tabWidth = (availableWidth / Sites.supportSites.length)
            .clamp(0.0, maxTabWidth);
        final barWidth = tabWidth * Sites.supportSites.length;
        return Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: barWidth,
            child: Material(
              key: const ValueKey<String>('site-tab-bar-fallback'),
              color: colors.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(iconOnly ? 28 : 24),
                side: BorderSide(
                  color: neutralBorder,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: iconOnly ? 56 : 48,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < Sites.supportSites.length; i++)
                      SizedBox(
                        width: tabWidth,
                        height: double.infinity,
                        child: Semantics(
                          button: true,
                          selected: controller.index == i,
                          label: Sites.supportSites[i].name,
                          child: InkWell(
                            onTap: () => controller.animateTo(i),
                            borderRadius:
                                BorderRadius.circular(iconOnly ? 26 : 20),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  iconOnly ? 26 : 20,
                                ),
                                border: Border.all(
                                  color: controller.index == i
                                      ? colors.primary
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    Sites.supportSites[i].logo,
                                    width: 21,
                                    height: 21,
                                  ),
                                  if (!iconOnly) ...[
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        Sites.supportSites[i].name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: controller.index == i
                                              ? colors.primary
                                              : colors.onSurfaceVariant,
                                          fontWeight: controller.index == i
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
