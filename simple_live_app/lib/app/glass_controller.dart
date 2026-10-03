import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/glass_quality_policy.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';

/// Process-wide bridge between app settings and liquid_glass_widgets.
class AppGlassController {
  AppGlassController._();

  static bool _initializationFailed = false;

  static bool get initializationFailed => _initializationFailed;

  static Future<void> initialize() async {
    if (Utils.isOhos) {
      return;
    }
    try {
      await LiquidGlassWidgets.initialize(
        warmUpMode: GlassWarmUpMode.auto,
      );
    } catch (error, stackTrace) {
      _initializationFailed = true;
      Log.e('Liquid Glass 初始化失败，本次运行已回退普通界面: $error', stackTrace);
    }
  }

  static Widget wrap(Widget child) {
    if (Utils.isOhos || _initializationFailed) {
      return child;
    }
    return LiquidGlassWidgets.wrap(
      child: child,
      adaptiveQuality: false,
      respectSystemAccessibility: true,
      brightnessResolver: Theme.maybeBrightnessOf,
    );
  }

  static GlassQuality? qualityOf(
    BuildContext context, {
    required GlassSurfaceRole role,
  }) {
    final selectedMode = AppSettingsController.instance.glassMode.value;
    final capabilities = AppGlassPlatformCapabilities(
      platform: defaultTargetPlatform,
      isWeb: kIsWeb,
      shaderSupported: ImageFilter.isShaderFilterSupported,
    );
    return AppGlassQualityPolicy.resolve(
      mode: selectedMode,
      role: role,
      capabilities: capabilities,
      initializationFailed: _initializationFailed || Utils.isOhos,
      highContrast: MediaQuery.highContrastOf(context),
    );
  }
}
