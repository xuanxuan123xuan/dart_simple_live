import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/background_playback_guide_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('simple_live/background_playback_guide_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('opens each supported settings entry', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return true;
    });
    final service = BackgroundPlaybackGuideService.test(channel: channel);

    expect(await service.openBatteryOptimization(), isTrue);
    expect(await service.openAppBatteryManagement(), isTrue);
    expect(await service.openAutostart(), isTrue);
    expect(await service.openNotifications(), isTrue);
    expect(methods, [
      'openBatteryOptimization',
      'openAppBatteryManagement',
      'openAutostart',
      'openNotifications',
    ]);
  });

  test('returns false when Android does not expose the entry', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException();
    });
    final service = BackgroundPlaybackGuideService.test(channel: channel);

    expect(await service.openAutostart(), isFalse);
  });
}
