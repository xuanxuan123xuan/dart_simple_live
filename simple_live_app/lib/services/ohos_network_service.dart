import 'package:flutter/services.dart';

enum OhosNetworkType {
  cellular,
  wifi,
  ethernet,
  other,
}

class OhosNetworkService {
  static const MethodChannel _channel =
      MethodChannel('simple_live/ohos_network');

  static Future<OhosNetworkType> getNetworkType() async {
    final value = await _channel.invokeMethod<String>('getNetworkType');
    return switch (value) {
      'cellular' => OhosNetworkType.cellular,
      'wifi' => OhosNetworkType.wifi,
      'ethernet' => OhosNetworkType.ethernet,
      _ => OhosNetworkType.other,
    };
  }
}
