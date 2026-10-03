import 'dart:io';

import 'package:flutter/services.dart';

/// Calls the app-owned Win32 fullscreen controller.
///
/// Keeping this channel here prevents the player controller from depending on
/// window_manager's Win32 fullscreen implementation.
class WindowsFullscreenService {
  WindowsFullscreenService._();

  static const MethodChannel _channel =
      MethodChannel('simple_live/windows_fullscreen');

  static Future<bool> setFullScreen(bool value) async {
    if (!Platform.isWindows) {
      return value;
    }
    final result = await _channel.invokeMethod<bool>(value ? 'enter' : 'exit');
    return result ?? false;
  }

  static Future<bool> isFullScreen() async {
    if (!Platform.isWindows) {
      return false;
    }
    return await _channel.invokeMethod<bool>('isActive') ?? false;
  }
}
