import 'package:flutter/services.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

/// Plugin for changing screen brightness
class ScreenBrightness {
  /// ScreenBrightness designed as static method collection class
  /// So constructor should not provide to user.
  ScreenBrightness._();

  /// Plugin singleton
  static final ScreenBrightness _instance = ScreenBrightness._();

  /// Returns a singleton instance of [ScreenBrightness].
  ///
  /// [ScreenBrightness] is designed to work as a singleton.
  factory ScreenBrightness() => instance;

  /// Returns a singleton instance of [ScreenBrightness].
  ///
  /// [ScreenBrightness] is designed to work as a singleton.
  static ScreenBrightness get instance => _instance;

  /// Private platform prevent direct access or overriding
  static ScreenBrightnessPlatform get _platform {
    return ScreenBrightnessPlatform.instance;
  }

  /// Returns system screen brightness.
  ///
  /// The value should be within 0.0 - 1.0. Otherwise, [RangeError.range] will
  /// be throw.
  ///
  /// This parameter is useful for user to get system screen brightness value
  /// after calling [setSystemScreenBrightness]
  ///
  /// This parameter is useful for user to get system screen brightness value
  /// after calling [resetApplicationScreenBrightness]
  ///
  /// Platform difference:
  /// (iOS)(macOS)(Windows): return initial brightness
  ///
  /// When [_channel.invokeMethod] fails to get system screen brightness, it
  /// throws [PlatformException] with code and message:
  ///
  /// Code: -9, Message: value returns null
  Future<double> get system => _platform.system;

  /// Set system screen brightness with double value.
  ///
  /// The value should be within 0.0 - 1.0. Otherwise, [RangeError.range] will
  /// be throw.
  ///
  /// This method is useful for user to change system screen brightness.
  ///
  /// When [_channel.invokeMethod] fails to set system screen brightness, it
  /// throws [PlatformException] with code and message:
  ///
  /// Code: -1, Message: Unable to change system screen brightness
  /// Failed to set system brightness
  ///
  /// Code: -2, Message: Unexpected error on null brightness
  /// Cannot read parameter from method channel map, or parameter is null
  ///
  /// (Android only) Code: -10, Message: Unexpected error on activity binding
  /// Unexpected error when getting activity, activity may be null
  Future<void> setSystemScreenBrightness(double brightness) =>
      _platform.setSystemScreenBrightness(brightness);

  /// Returns stream with system screen brightness changes including
  /// [ScreenBrightness.setSystemScreenBrightness], system control center or
  /// system setting.
  ///
  /// This stream is useful for user to listen to system brightness changes.
  Stream<double> get onSystemScreenBrightnessChanged =>
      _platform.onSystemScreenBrightnessChanged;

  /// Returns application screen brightness value.
  ///
  /// The value should be within 0.0 - 1.0. Otherwise, [RangeError.range] will
  /// be throw.
  ///
  /// This parameter is useful for user to get application screen brightness
  /// value after calling [setApplicationScreenBrightness]
  ///
  /// Calling this method after calling [resetApplicationScreenBrightness] may return wrong
  /// value in iOS because UIScreen.main.brightness returns old brightness value
  ///
  /// When [_channel.invokeMethod] fails to get application screen brightness,
  /// it throws [PlatformException] with code and message:
  ///
  /// Code: -9, Message: value returns null
  ///
  /// (Android only) Code: -10, Message: Unexpected error on activity binding
  /// Unexpected error when getting activity, activity may be null
  ///
  /// (Android only) (macOS only) Code: -11, Message: Could not found system
  /// screen brightness value
  /// Unexpected error when getting brightness from Setting using
  /// (Android) Settings.System.SCREEN_BRIGHTNESS
  @Deprecated('refactored to application (will be remove after version 2.1.0)')
  Future<double> get current => application;

  /// Returns application screen brightness value.
  ///
  /// The value should be within 0.0 - 1.0. Otherwise, [RangeError.range] will
  /// be throw.
  ///
  /// This parameter is useful for user to get application screen brightness
  /// value after calling [setApplicationScreenBrightness]
  ///
  /// Calling this method after calling [resetApplicationScreenBrightness] may return wrong
  /// value in iOS because UIScreen.main.brightness returns old brightness value
  ///
  /// When [_channel.invokeMethod] fails to get application screen brightness,
  /// it throws [PlatformException] with code and message:
  ///
  /// Code: -9, Message: value returns null
  ///
  /// (Android only) Code: -10, Message: Unexpected error on activity binding
  /// Unexpected error when getting activity, activity may be null
  ///
  /// (Android only) (macOS only) Code: -11, Message: Could not found system
  /// screen brightness value
  /// Unexpected error when getting brightness from Setting using
  /// (Android) Settings.System.SCREEN_BRIGHTNESS
  Future<double> get application => _platform.application;

  /// Set application screen brightness with double value.
  ///
  /// The value should be within 0.0 - 1.0. Otherwise, [RangeError.range] will
  /// be throw.
  ///
  /// This method is useful for user to change application screen brightness.
  ///
  /// When [_channel.invokeMethod] fails to set application screen brightness,
  /// it throws [PlatformException] with code and message:
  ///
  /// Code: -1, Message: Unable to change application screen brightness
  /// Failed to set brightness
  ///
  /// Code: -2, Message: Unexpected error on null brightness
  /// Cannot read parameter from method channel map, or parameter is null
  ///
  /// (Android only) Code: -10, Message: Unexpected error on activity binding
  /// Unexpected error when getting activity, activity may be null
  @Deprecated(
      'refactored to setApplicationScreenBrightness (will be remove after version 2.1.0)')
  Future<void> setScreenBrightness(double brightness) =>
      setApplicationScreenBrightness(brightness);

  /// Set application screen brightness with double value.
  ///
  /// The value should be within 0.0 - 1.0. Otherwise, [RangeError.range] will
  /// be throw.
  ///
  /// This method is useful for user to change application screen brightness.
  ///
  /// When [_channel.invokeMethod] fails to set application screen brightness,
  /// it throws [PlatformException] with code and message:
  ///
  /// Code: -1, Message: Unable to change application screen brightness
  /// Failed to set brightness
  ///
  /// Code: -2, Message: Unexpected error on null brightness
  /// Cannot read parameter from method channel map, or parameter is null
  ///
  /// (Android only) Code: -10, Message: Unexpected error on activity binding
  /// Unexpected error when getting activity, activity may be null
  Future<void> setApplicationScreenBrightness(double brightness) =>
      _platform.setApplicationScreenBrightness(brightness);

  /// Reset application screen brightness with (Android) -1 or (iOS)system
  /// brightness value.
  ///
  /// This method is useful for user to reset application screen brightness
  /// when user leave the page which has change the application screen
  /// brightness value.
  ///
  /// When [_channel.invokeMethod] fails to get application screen brightness,
  /// it throws [PlatformException] with code and message:
  ///
  /// Code: -1, Message: Unable to reset application screen brightness
  /// Failed to reset application screen brightness
  ///
  /// Code: -2, Message: Unexpected error on null brightness
  /// System brightness in plugin is null
  ///
  /// (Android only) Code: -10, Message: Unexpected error on activity binding
  /// Unexpected error when getting activity, activity may be null
  @Deprecated(
      'refactored to resetApplicationScreenBrightness (will be remove after version 2.1.0)')
  Future<void> resetScreenBrightness() => resetApplicationScreenBrightness();

  /// Reset application screen brightness with (Android) -1 or (iOS)system
  /// brightness value.
  ///
  /// This method is useful for user to reset application screen brightness
  /// when user leave the page which has change the application screen
  /// brightness value.
  ///
  /// When [_channel.invokeMethod] fails to get application screen brightness,
  /// it throws [PlatformException] with code and message:
  ///
  /// Code: -1, Message: Unable to reset application screen brightness
  /// Failed to reset application screen brightness
  ///
  /// Code: -2, Message: Unexpected error on null brightness
  /// System brightness in plugin is null
  ///
  /// (Android only) Code: -10, Message: Unexpected error on activity binding
  /// Unexpected error when getting activity, activity may be null
  Future<void> resetApplicationScreenBrightness() =>
      _platform.resetApplicationScreenBrightness();

  /// Returns stream with application screen brightness changes including
  /// [ScreenBrightness.setApplicationScreenBrightness],
  /// [ScreenBrightness.resetApplicationScreenBrightness], system control center
  /// or system setting.
  ///
  /// This stream is useful for user to listen to application brightness changes.
  @Deprecated(
      'refactored to onApplicationScreenBrightnessChanged (will be remove after version 2.1.0)')
  Stream<double> get onCurrentBrightnessChanged =>
      onApplicationScreenBrightnessChanged;

  /// Returns stream with application screen brightness changes including
  /// [ScreenBrightness.setApplicationScreenBrightness],
  /// [ScreenBrightness.resetApplicationScreenBrightness], system control center
  /// or system setting.
  ///
  /// This stream is useful for user to listen to application brightness changes.
  Stream<double> get onApplicationScreenBrightnessChanged =>
      _platform.onApplicationScreenBrightnessChanged;

  /// Returns boolean to identify application screen brightness has changed by
  /// this plugin.
  ///
  /// e.g
  /// [ScreenBrightness.setApplicationScreenBrightness] will make this true
  /// [ScreenBrightness.resetApplicationScreenBrightness] will make this false
  @Deprecated(
      'refactored to hasApplicationScreenBrightnessChanged (will be remove after version 2.1.0)')
  Future<bool> get hasChanged => hasApplicationScreenBrightnessChanged;

  /// Returns boolean to identify application screen brightness has changed by
  /// this plugin.
  ///
  /// e.g
  /// [ScreenBrightness.setApplicationScreenBrightness] will make this true
  /// [ScreenBrightness.resetApplicationScreenBrightness] will make this false
  Future<bool> get hasApplicationScreenBrightnessChanged =>
      _platform.hasApplicationScreenBrightnessChanged;

  /// Returns boolean to identify will auto reset to system brightness when
  /// application lifecycle changed.
  ///
  /// This parameter is useful for user to determinate current state of auto reset.
  ///
  /// (iOS only) implemented in iOS only because only iOS native side does not
  /// having reset method.
  Future<bool> get isAutoReset => _platform.isAutoReset;

  /// Set auto reset when application lifecycle changed
  ///
  /// This method is useful for user change whether this plugin should auto reset
  /// to system brightness when application lifecycle changed.
  ///
  /// (iOS only) implemented in iOS only because only iOS native side does not
  /// having reset method.
  Future<void> setAutoReset(bool isAutoReset) =>
      _platform.setAutoReset(isAutoReset);

  /// Returns boolean to identify will animate when application screen brightness
  /// changed.
  ///
  /// This parameter is useful for user to determinate will there be animation
  /// transition when application screen brightness changed.
  ///
  /// (iOS only) implemented in iOS only because only iOS native side does not
  /// having reset method.
  Future<bool> get isAnimate => _platform.isAnimate;

  /// Set will animate when application screen brightness changed.
  ///
  /// This method is useful for user change whether this plugin should animate
  /// when application screen brightness changed.
  ///
  /// (iOS only) implemented in iOS only because only iOS native side does not
  /// having reset method.
  Future<void> setAnimate(bool isAnimate) => _platform.setAnimate(isAnimate);

  /// Return can change system screen brightness
  ///
  /// This parameter is useful for user to determinate user can change system
  /// brightness.
  ///
  /// (Android only) implemented in Android only because only Android needs
  /// permission to change the screen brightness
  Future<bool> get canChangeSystemBrightness =>
      _platform.canChangeSystemBrightness;
}
