import 'package:flutter/foundation.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:simple_live_app/app/app_glass_mode.dart';

/// Semantic roles keep expensive glass out of scrolling and platform-view
/// surfaces even when the user explicitly selects the premium tier.
enum GlassSurfaceRole {
  navigation,
  control,
  content,
  platformViewControl,
}

/// Visual tint levels remain tied to the user's requested mode, even when the
/// renderer has to cap the effective shader quality on a platform.
class AppGlassAppearanceProfile {
  const AppGlassAppearanceProfile({
    required this.surfaceTintAlpha,
    required this.navigationTintAlpha,
    required this.indicatorTintAlpha,
    required this.indicatorGlassTintAlpha,
  });

  final int surfaceTintAlpha;
  final int navigationTintAlpha;
  final int indicatorTintAlpha;
  final int indicatorGlassTintAlpha;
}

class AppGlassAppearancePolicy {
  const AppGlassAppearancePolicy._();

  static const _minimal = AppGlassAppearanceProfile(
    surfaceTintAlpha: 32,
    navigationTintAlpha: 32,
    indicatorTintAlpha: 68,
    indicatorGlassTintAlpha: 34,
  );
  static const _standard = AppGlassAppearanceProfile(
    surfaceTintAlpha: 14,
    navigationTintAlpha: 18,
    indicatorTintAlpha: 52,
    indicatorGlassTintAlpha: 24,
  );
  static const _premium = AppGlassAppearanceProfile(
    surfaceTintAlpha: 6,
    navigationTintAlpha: 8,
    indicatorTintAlpha: 34,
    indicatorGlassTintAlpha: 12,
  );

  static AppGlassAppearanceProfile resolve(AppGlassMode mode) {
    switch (mode) {
      case AppGlassMode.off:
      case AppGlassMode.minimal:
        return _minimal;
      case AppGlassMode.auto:
      case AppGlassMode.standard:
        return _standard;
      case AppGlassMode.premium:
        return _premium;
    }
  }
}

class AppGlassPlatformCapabilities {
  const AppGlassPlatformCapabilities({
    required this.platform,
    required this.isWeb,
    required this.shaderSupported,
  });

  factory AppGlassPlatformCapabilities.current() {
    return AppGlassPlatformCapabilities(
      platform: defaultTargetPlatform,
      isWeb: kIsWeb,
      shaderSupported: true,
    );
  }

  final TargetPlatform platform;
  final bool isWeb;
  final bool shaderSupported;

  bool get supportsPremium =>
      !isWeb &&
      shaderSupported &&
      (platform == TargetPlatform.android ||
          platform == TargetPlatform.iOS ||
          platform == TargetPlatform.macOS);
}

class AppGlassQualityPolicy {
  const AppGlassQualityPolicy._();

  static GlassQuality? resolve({
    required AppGlassMode mode,
    required GlassSurfaceRole role,
    required AppGlassPlatformCapabilities capabilities,
    bool initializationFailed = false,
    bool highContrast = false,
  }) {
    if (mode == AppGlassMode.off || initializationFailed) {
      return null;
    }

    if (!capabilities.shaderSupported || highContrast) {
      return GlassQuality.minimal;
    }

    if (role == GlassSurfaceRole.content ||
        role == GlassSurfaceRole.platformViewControl) {
      return GlassQuality.minimal;
    }

    switch (mode) {
      case AppGlassMode.off:
        return null;
      case AppGlassMode.minimal:
        return GlassQuality.minimal;
      case AppGlassMode.auto:
      case AppGlassMode.standard:
        return GlassQuality.standard;
      case AppGlassMode.premium:
        return capabilities.supportsPremium
            ? GlassQuality.premium
            : GlassQuality.standard;
    }
  }
}
