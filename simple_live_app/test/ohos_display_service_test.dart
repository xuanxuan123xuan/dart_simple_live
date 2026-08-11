import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/ohos_display_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('simple_live/ohos_display_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('OHOS native bridge uses the window keep-screen-on API', () {
    final plugin = File(
      'ohos/entry/src/main/ets/plugins/OhosDisplayPlugin.ets',
    ).readAsStringSync();
    final entryAbility = File(
      'ohos/entry/src/main/ets/entryability/EntryAbility.ets',
    ).readAsStringSync();

    expect(plugin, contains('simple_live/ohos_display'));
    expect(plugin, contains('setWindowKeepScreenOn(enabled)'));
    expect(plugin, contains('setWindowKeepScreenOn(false)'));
    expect(entryAbility, contains('new OhosDisplayPlugin()'));
  });

  test('setKeepScreenOn is idempotent and forwards transitions', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final service = OhosDisplayService(
      channel: channel,
      isOhos: () => true,
    );

    await service.setKeepScreenOn(true);
    await service.setKeepScreenOn(true);
    await service.setKeepScreenOn(false);

    expect(calls.map((call) => call.method), [
      'setKeepScreenOn',
      'setKeepScreenOn',
    ]);
    expect(calls.map((call) => call.arguments), [
      {'enabled': true},
      {'enabled': false},
    ]);
  });

  test('failed native updates are retried instead of cached', () async {
    var attempts = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      attempts += 1;
      if (attempts == 1) {
        throw PlatformException(code: 'window_unavailable');
      }
      return null;
    });
    final service = OhosDisplayService(
      channel: channel,
      isOhos: () => true,
    );

    await expectLater(
      service.setKeepScreenOn(true),
      throwsA(isA<PlatformException>()),
    );
    await service.setKeepScreenOn(true);

    expect(attempts, 2);
  });

  test('non-OHOS platforms do not invoke the native channel', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls += 1;
      return true;
    });
    final service = OhosDisplayService(
      channel: channel,
      isOhos: () => false,
    );

    await service.setKeepScreenOn(true);

    expect(await service.getKeepScreenOn(), isFalse);
    expect(calls, 0);
  });
}
