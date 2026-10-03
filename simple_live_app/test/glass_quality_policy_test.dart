import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:simple_live_app/app/app_glass_mode.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';

void main() {
  const mobile = AppGlassPlatformCapabilities(
    platform: TargetPlatform.iOS,
    isWeb: false,
    shaderSupported: true,
  );
  const desktop = AppGlassPlatformCapabilities(
    platform: TargetPlatform.windows,
    isWeb: false,
    shaderSupported: true,
  );

  test('off and initialization failure use the Material fallback', () {
    expect(
      AppGlassQualityPolicy.resolve(
        mode: AppGlassMode.off,
        role: GlassSurfaceRole.navigation,
        capabilities: mobile,
      ),
      isNull,
    );
    expect(
      AppGlassQualityPolicy.resolve(
        mode: AppGlassMode.premium,
        role: GlassSurfaceRole.navigation,
        capabilities: mobile,
        initializationFailed: true,
      ),
      isNull,
    );
  });

  test('auto is a static standard-quality policy', () {
    expect(
      AppGlassQualityPolicy.resolve(
        mode: AppGlassMode.auto,
        role: GlassSurfaceRole.navigation,
        capabilities: mobile,
      ),
      GlassQuality.standard,
    );
  });

  test('higher requested modes use progressively clearer glass tints', () {
    final minimal = AppGlassAppearancePolicy.resolve(AppGlassMode.minimal);
    final standard = AppGlassAppearancePolicy.resolve(AppGlassMode.standard);
    final premium = AppGlassAppearancePolicy.resolve(AppGlassMode.premium);

    expect(
      minimal.navigationTintAlpha,
      greaterThan(standard.navigationTintAlpha),
    );
    expect(
      standard.navigationTintAlpha,
      greaterThan(premium.navigationTintAlpha),
    );
    expect(
      minimal.surfaceTintAlpha,
      greaterThan(standard.surfaceTintAlpha),
    );
    expect(
      standard.surfaceTintAlpha,
      greaterThan(premium.surfaceTintAlpha),
    );
    expect(
      AppGlassAppearancePolicy.resolve(AppGlassMode.auto).navigationTintAlpha,
      standard.navigationTintAlpha,
    );
  });

  test('premium is capped on desktop and unsupported shaders', () {
    expect(
      AppGlassQualityPolicy.resolve(
        mode: AppGlassMode.premium,
        role: GlassSurfaceRole.navigation,
        capabilities: desktop,
      ),
      GlassQuality.standard,
    );
    expect(
      AppGlassQualityPolicy.resolve(
        mode: AppGlassMode.premium,
        role: GlassSurfaceRole.navigation,
        capabilities: const AppGlassPlatformCapabilities(
          platform: TargetPlatform.android,
          isWeb: false,
          shaderSupported: false,
        ),
      ),
      GlassQuality.minimal,
    );
  });

  test('scrolling content, platform views and high contrast stay minimal', () {
    for (final role in [
      GlassSurfaceRole.content,
      GlassSurfaceRole.platformViewControl,
    ]) {
      expect(
        AppGlassQualityPolicy.resolve(
          mode: AppGlassMode.premium,
          role: role,
          capabilities: mobile,
        ),
        GlassQuality.minimal,
      );
    }
    expect(
      AppGlassQualityPolicy.resolve(
        mode: AppGlassMode.premium,
        role: GlassSurfaceRole.navigation,
        capabilities: mobile,
        highContrast: true,
      ),
      GlassQuality.minimal,
    );
  });
}
