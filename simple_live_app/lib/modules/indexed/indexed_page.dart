import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/glass_controller.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/services/app_update_service.dart';
import 'package:simple_live_app/widgets/glass/glass_surface.dart';

import 'indexed_controller.dart';

class IndexedPage extends GetView<IndexedController> {
  const IndexedPage({Key? key, this.glassEnabled = true}) : super(key: key);

  /// Allows the app-level glass policy to turn the navigation surface off
  /// without changing navigation behavior. The plain Material surface is
  /// intentionally kept as a first-class fallback for unsupported renderers,
  /// accessibility modes, and shader initialization failures.
  final bool glassEnabled;

  @override
  Widget build(BuildContext context) {
    final stack = _IndexedPageStack(controller: controller);
    return LiquidGlassScope(
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          // All window sizes use the same floating bottom navigation. The
          // indexed pages already reserve 96 px at the end of their scroll
          // views, so initial content stays clear while scrolled content can
          // travel behind the glass surface.
          extendBody: true,
          body: GlassBackgroundSource(
            enabled: glassEnabled,
            child: ColoredBox(
              key: const ValueKey('root-page-background'),
              color: Theme.of(context).scaffoldBackgroundColor,
              child: stack,
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width =
                    constraints.maxWidth > 600 ? 600.0 : constraints.maxWidth;
                return Center(
                  heightFactor: 1,
                  child: SizedBox(
                    width: width,
                    child: _BottomNavigationBar(
                      items: controller.items,
                      selectedIndex: controller.index,
                      onDestinationSelected: controller.setIndex,
                      glassEnabled: glassEnabled,
                      backgroundKey: LiquidGlassScope.of(context),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps page instances alive and delegates page creation to
/// [IndexedController], preserving the existing lazy-loading and repeat-tap
/// event behavior.
class _IndexedPageStack extends StatelessWidget {
  const _IndexedPageStack({required this.controller});

  final IndexedController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => IndexedStack(
        index: controller.index.value,
        children: controller.pages,
      ),
    );
  }
}

class _BottomNavigationBar extends StatelessWidget {
  const _BottomNavigationBar({
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.glassEnabled,
    required this.backgroundKey,
  });

  final RxList<HomePageItem> items;
  final RxInt selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool glassEnabled;
  final GlobalKey? backgroundKey;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('root-bottom-navigation'),
      child: Obx(
        () => _buildNavigation(context),
      ),
    );
  }

  Widget _buildNavigation(BuildContext context) {
    GlassQuality? quality;
    if (glassEnabled && Get.isRegistered<AppSettingsController>()) {
      AppSettingsController.instance.glassMode.value;
      quality = AppGlassController.qualityOf(
        context,
        role: GlassSurfaceRole.navigation,
      );
    }

    if (quality == null) {
      return _IndexedGlassSurface(
        enabled: false,
        borderRadius: BorderRadius.circular(28),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: _buildFallbackDestinations(),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final appearance = AppGlassAppearancePolicy.resolve(
      AppSettingsController.instance.glassMode.value,
    );
    return GlassTabBar.inline(
      tabs: [
        for (final item in items)
          GlassTab(
            icon: _glassNavigationIcon(item),
            activeIcon: _glassNavigationIcon(item),
            label: item.title,
            semanticLabel: item.title,
          ),
      ],
      selectedIndex: selectedIndex.value,
      onTabSelected: onDestinationSelected,
      backgroundKey: backgroundKey,
      quality: quality,
      barHeight: 64,
      barBorderRadius: 28,
      iconSize: 22,
      labelFontSize: 11,
      iconLabelSpacing: 2,
      tabPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      indicatorExpansion:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      indicatorBorderRadius: 22,
      indicatorPinchStrength: 0.55,
      magnification: 1.04,
      pressScale: 1.025,
      settings: LiquidGlassSettings(
        glassColor:
            colorScheme.surface.withAlpha(appearance.navigationTintAlpha),
        thickness: 24,
        blur: 10,
        refractiveIndex: 1.24,
        chromaticAberration: 0.012,
        lightIntensity: 0.62,
        saturation: 1.35,
        ambientRim: 0.16,
      ),
      indicatorColor:
          colorScheme.primaryContainer.withAlpha(appearance.indicatorTintAlpha),
      indicatorSettings: LiquidGlassSettings(
        glassColor: colorScheme.primaryContainer
            .withAlpha(appearance.indicatorGlassTintAlpha),
        thickness: 34,
        blur: 7,
        refractiveIndex: 1.38,
        chromaticAberration: 0.018,
        lightIntensity: 0.78,
        saturation: 1.48,
        ambientRim: 0.28,
      ),
      selectedIconColor: colorScheme.onPrimaryContainer,
      selectedLabelColor: colorScheme.onPrimaryContainer,
      unselectedIconColor: colorScheme.onSurfaceVariant,
      unselectedLabelColor: colorScheme.onSurfaceVariant,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
    );
  }

  Widget _buildFallbackDestinations() {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: _NavigationDestination(
              item: items[i],
              selected: selectedIndex.value == i,
              onTap: () => onDestinationSelected(i),
            ),
          ),
      ],
    );
  }

  Widget _glassNavigationIcon(HomePageItem item) {
    final icon = Icon(item.iconData);
    if (item.index != 3) {
      return icon;
    }
    return Obx(
      () => _BadgeIcon(
        showBadge: AppUpdateService.instance.updateAvailable.value,
        child: icon,
      ),
    );
  }
}

class _NavigationDestination extends StatelessWidget {
  const _NavigationDestination({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final HomePageItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor =
        selected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: item.title,
      child: Tooltip(
        message: item.title,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected ? colorScheme.primary : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _navigationIcon(item, color: foregroundColor),
                  const SizedBox(height: 2),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: foregroundColor,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navigationIcon(HomePageItem item, {required Color color}) {
    final icon = Icon(item.iconData, color: color, size: 22);
    if (item.index != 3) {
      return icon;
    }
    return Obx(
      () => _BadgeIcon(
        showBadge: AppUpdateService.instance.updateAvailable.value,
        child: icon,
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({
    required this.showBadge,
    required this.child,
  });

  final bool showBadge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (showBadge)
          Positioned(
            right: -2,
            top: -2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const SizedBox(width: 8, height: 8),
            ),
          ),
      ],
    );
  }
}

/// Navigation-specific adapter around the app-level glass surface. Keeping an
/// explicit [enabled] fallback makes the widget independently testable.
class _IndexedGlassSurface extends StatelessWidget {
  const _IndexedGlassSurface({
    required this.child,
    required this.enabled,
    required this.borderRadius,
    required this.padding,
  });

  final Widget child;
  final bool enabled;
  final BorderRadius borderRadius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (!enabled) {
      final neutralBorder =
          (theme.brightness == Brightness.dark ? Colors.white : Colors.black)
              .withAlpha(theme.brightness == Brightness.dark ? 42 : 28);
      return Material(
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(color: neutralBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
    }
    return GlassSurface(
      role: GlassSurfaceRole.navigation,
      radius: borderRadius.topLeft.x,
      padding: padding,
      child: child,
    );
  }
}
