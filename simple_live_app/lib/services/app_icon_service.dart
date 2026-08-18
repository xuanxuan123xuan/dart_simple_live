import 'dart:io';

import 'package:flutter/services.dart';

enum AppIconVariant {
  classic('classic'),
  modern('modern');

  const AppIconVariant(this.storageValue);

  final String storageValue;

  static AppIconVariant fromStorage(String value) {
    // Keep installations that stored the pre-release name working.
    if (value == 'simplelive') {
      return AppIconVariant.modern;
    }
    return AppIconVariant.values.firstWhere(
      (variant) => variant.storageValue == value,
      orElse: () => AppIconVariant.classic,
    );
  }
}

class AppIconService {
  AppIconService._();

  static const MethodChannel _channel = MethodChannel('simple_live/app_icon');

  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  static Future<void> setIcon(AppIconVariant variant) async {
    if (!isSupported) {
      throw UnsupportedError(
          'The current platform cannot change its app icon.');
    }
    await _channel.invokeMethod<void>(
      'setIcon',
      <String, String>{'icon': variant.storageValue},
    );
  }
}
