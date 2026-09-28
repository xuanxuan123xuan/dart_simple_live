import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Opens the Android settings screens that commonly affect background playback.
///
/// Every method is best effort. A device may not expose a particular screen,
/// so callers must keep the manual instructions visible as a fallback.
class BackgroundPlaybackGuideService {
  BackgroundPlaybackGuideService._({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('simple_live/background_playback_guide');

  static final BackgroundPlaybackGuideService instance =
      BackgroundPlaybackGuideService._();

  @visibleForTesting
  BackgroundPlaybackGuideService.test({required MethodChannel channel})
      : _channel = channel;

  final MethodChannel _channel;

  Future<bool> openBatteryOptimization() => _open('openBatteryOptimization');

  Future<bool> openAppBatteryManagement() =>
      _open('openAppBatteryManagement');

  Future<bool> openAutostart() => _open('openAutostart');

  Future<bool> openNotifications() => _open('openNotifications');

  Future<bool> _open(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
