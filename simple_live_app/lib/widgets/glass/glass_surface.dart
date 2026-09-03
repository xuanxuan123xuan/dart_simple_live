import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/glass_controller.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.role = GlassSurfaceRole.control,
    this.radius = 16,
    this.padding,
    this.onTap,
    this.clipBehavior = Clip.antiAlias,
    this.liveBackdrop = false,
    this.disablePlatformViewBackdrop = false,
    super.key,
  });

  final Widget child;
  final GlassSurfaceRole role;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  /// Forces the live BackdropFilter path so content moving behind a pinned
  /// surface is sampled in real time. This is intended for floating app bars
  /// and other chrome that sits above a scrolling Flutter scene.
  final bool liveBackdrop;

  /// Keeps the configured glass material but prevents the live BackdropFilter
  /// path from sampling a native video view. This is useful for video-player
  /// chrome that should follow the app glass setting without mirroring video
  /// content or paying for a per-frame backdrop capture.
  final bool disablePlatformViewBackdrop;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<AppSettingsController>()) {
      return _buildSurface(context, quality: null);
    }
    return Obx(() {
      // Establish the GetX dependency before resolving the effective quality.
      final mode = AppSettingsController.instance.glassMode.value;
      final quality = AppGlassController.qualityOf(context, role: role);
      return _buildSurface(
        context,
        quality: quality,
        glassTintAlpha: AppGlassAppearancePolicy.resolve(mode).surfaceTintAlpha,
      );
    });
  }

  Widget _buildSurface(
    BuildContext context, {
    required GlassQuality? quality,
    int glassTintAlpha = 0,
  }) {
    final colors = Theme.of(context).colorScheme;
    final content = onTap == null
        ? child
        : Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: onTap,
              child: child,
            ),
          );

    if (quality == null) {
      // Video chrome (controls floating over the player) hardcodes a white
      // foreground, so the opaque fallback must stay dark to keep icons and
      // text readable in light theme when glass is disabled.
      final isVideoChrome = role == GlassSurfaceRole.platformViewControl;
      final fallbackColor =
          isVideoChrome ? Colors.black.withAlpha(102) : colors.surface;
      final fallbackBorder =
          isVideoChrome ? Colors.white.withAlpha(46) : colors.outlineVariant;
      return Material(
        color: fallbackColor,
        clipBehavior: clipBehavior,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: fallbackBorder),
        ),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: content,
        ),
      );
    }

    return GlassContainer(
      useOwnLayer: true,
      quality: quality,
      settings: LiquidGlassSettings(
        glassColor: colors.surface.withAlpha(glassTintAlpha),
      ),
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      padding: padding,
      clipBehavior: clipBehavior,
      platformViewBackdrop: liveBackdrop ||
          (role == GlassSurfaceRole.platformViewControl &&
              !disablePlatformViewBackdrop),
      child: content,
    );
  }
}

/// A glass shell for text-heavy dialogs, sheets, drawers, and popup content.
///
/// Plain [GlassSurface] intentionally exposes more of the backdrop and works
/// well for compact controls. Overlay content gets a softer readability tint
/// so the backdrop remains visible without sacrificing text contrast.
class GlassOverlaySurface extends StatelessWidget {
  const GlassOverlaySurface({
    required this.child,
    this.radius = 20,
    this.padding,
    this.liveBackdrop = false,
    super.key,
  });

  static const readabilityLayerKey =
      ValueKey<String>('glass-overlay-readability-layer');

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool liveBackdrop;

  @visibleForTesting
  static Color backgroundColorFor(ThemeData theme) {
    final alpha = theme.brightness == Brightness.dark ? 198 : 184;
    return theme.colorScheme.surfaceContainerHigh.withAlpha(alpha);
  }

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      role: GlassSurfaceRole.content,
      radius: radius,
      padding: padding,
      liveBackdrop: liveBackdrop,
      child: Material(
        key: readabilityLayerKey,
        color: backgroundColorFor(Theme.of(context)),
        child: child,
      ),
    );
  }
}
