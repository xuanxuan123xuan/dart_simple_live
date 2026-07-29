import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/ohos_pip_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('simple_live/ohos_pip_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late OhosPipService service;

  setUp(() {
    service = OhosPipService(
      channel: channel,
      isOhos: () => true,
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await service.dispose();
  });

  test('manual enter forwards normalized video dimensions', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });

    final entered = await service.enter(width: 1920.4, height: 1080.4);

    expect(entered, isTrue);
    expect(received?.method, 'enter');
    expect(received?.arguments, {'width': 1920, 'height': 1080});
  });

  test('prepare and cancel automatic PiP use the native channel', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return call.method == 'prepareAuto' ? true : null;
    });

    expect(
      await service.prepareAuto(width: 0, height: 0),
      isTrue,
    );
    await service.cancelAuto();

    expect(methods, ['prepareAuto', 'cancelAuto']);
  });

  test('native state changes are exposed once per transition', () async {
    service.initialize();
    final states = <bool>[];
    final subscription = service.stateChanges.listen(states.add);

    Future<void> sendState(bool enabled) async {
      final completer = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          MethodCall('stateChanged', {'enabled': enabled}),
        ),
        (_) => completer.complete(),
      );
      await completer.future;
    }

    await sendState(true);
    await sendState(true);
    await sendState(false);
    await subscription.cancel();

    expect(states, [true, false]);
  });

  test('unsupported devices report PiP as unavailable', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unsupported');
    });

    expect(await service.isAvailable(), isFalse);
  });
  test('non-OHOS platforms never invoke the native channel', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls += 1;
      return true;
    });
    final otherPlatform = OhosPipService(
      channel: channel,
      isOhos: () => false,
    );

    expect(await otherPlatform.isAvailable(), isFalse);
    expect(await otherPlatform.enter(width: 16, height: 9), isFalse);
    expect(calls, 0);
    await otherPlatform.dispose();
  });
}
