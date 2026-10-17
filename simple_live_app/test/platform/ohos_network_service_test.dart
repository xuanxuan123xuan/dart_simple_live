import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/ohos_network_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('simple_live/ohos_network');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final entry in const {
    'cellular': OhosNetworkType.cellular,
    'wifi': OhosNetworkType.wifi,
    'ethernet': OhosNetworkType.ethernet,
    'vpn': OhosNetworkType.other,
  }.entries) {
    test('maps native ${entry.key} network type', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getNetworkType');
        return entry.key;
      });

      expect(await OhosNetworkService.getNetworkType(), entry.value);
    });
  }
}
