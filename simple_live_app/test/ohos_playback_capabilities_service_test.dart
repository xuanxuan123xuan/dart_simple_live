import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/ohos_playback_capabilities_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('simple_live/ohos_capabilities_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('decodes the experimental playback capability', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getPlaybackCapabilities');
      return {'lowLatencyExperimentalSupported': true};
    });
    final service = OhosPlaybackCapabilitiesService(
      capabilitiesChannel: channel,
      isOhos: () => true,
    );

    final capabilities = await service.getCapabilities();

    expect(capabilities.lowLatencyExperimentalSupported, isTrue);
  });

  test('caches capabilities until explicitly refreshed', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls += 1;
      return {'lowLatencyExperimentalSupported': calls == 1};
    });
    final service = OhosPlaybackCapabilitiesService(
      capabilitiesChannel: channel,
      isOhos: () => true,
    );

    final first = await service.getCapabilities();
    final cached = await service.getCapabilities();
    final refreshed = await service.getCapabilities(refresh: true);

    expect(first.lowLatencyExperimentalSupported, isTrue);
    expect(cached.lowLatencyExperimentalSupported, isTrue);
    expect(refreshed.lowLatencyExperimentalSupported, isFalse);
    expect(calls, 2);
  });

  test('bridge failures fail closed', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unsupported');
    });
    final service = OhosPlaybackCapabilitiesService(
      capabilitiesChannel: channel,
      isOhos: () => true,
    );

    final capabilities = await service.getCapabilities();

    expect(capabilities.lowLatencyExperimentalSupported, isFalse);
  });

  test('non-OHOS platforms do not invoke the bridge', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls += 1;
      return {'lowLatencyExperimentalSupported': true};
    });
    final service = OhosPlaybackCapabilitiesService(
      capabilitiesChannel: channel,
      isOhos: () => false,
    );

    final capabilities = await service.getCapabilities();

    expect(capabilities.lowLatencyExperimentalSupported, isFalse);
    expect(calls, 0);
  });

  test('native bridge keeps PiP and playback capability methods', () {
    final plugin = File(
      'ohos/entry/src/main/ets/plugins/OhosCapabilitiesPlugin.ets',
    ).readAsStringSync();

    expect(plugin, contains("call.method === 'getPlaybackCapabilities'"));
    expect(plugin, contains('deviceInfo.sdkApiVersion >= 12'));
    expect(plugin, contains("'lowLatencyExperimentalSupported': supported"));
    expect(plugin, contains("call.method !== 'getPipCapabilities'"));
    expect(plugin, contains("'pipAvailable': available"));
  });
}
