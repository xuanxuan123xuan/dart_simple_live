import 'package:flutter/services.dart';
import 'package:simple_live_app/app/utils.dart';

class OhosDisplayService {
  OhosDisplayService({
    MethodChannel? channel,
    bool Function()? isOhos,
  })  : _channel = channel ?? const MethodChannel('simple_live/ohos_display'),
        _isOhos = isOhos ?? (() => Utils.isOhos);

  static final OhosDisplayService instance = OhosDisplayService();

  final MethodChannel _channel;
  final bool Function() _isOhos;
  bool? _keepScreenOn;

  Future<void> setKeepScreenOn(bool enabled) async {
    if (!_isOhos() || _keepScreenOn == enabled) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'setKeepScreenOn',
        <String, bool>{'enabled': enabled},
      );
      _keepScreenOn = enabled;
    } catch (_) {
      // A detached/recreated ability invalidates the cached window state.
      _keepScreenOn = null;
      rethrow;
    }
  }

  Future<bool> getKeepScreenOn() async {
    if (!_isOhos()) {
      return false;
    }
    final enabled = await _channel.invokeMethod<bool>('getKeepScreenOn');
    _keepScreenOn = enabled ?? false;
    return _keepScreenOn!;
  }
}
