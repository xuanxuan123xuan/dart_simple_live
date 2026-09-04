import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/ohos_pip_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('simple_live/ohos_pip_test');
  const capabilitiesChannel =
      MethodChannel('simple_live/ohos_capabilities_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late OhosPipService service;

  setUp(() {
    service = OhosPipService(
      channel: channel,
      capabilitiesChannel: capabilitiesChannel,
      isOhos: () => true,
    );
    messenger.setMockMethodCallHandler(capabilitiesChannel, (call) async {
      return {
        'pipAvailable': true,
        'pipAutoOnLeaveSupported': true,
        'pipCanHideDanmaku': true,
      };
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(capabilitiesChannel, null);
    await service.dispose();
  });

  test('settings and native bridge use PiP capabilities', () {
    final settings = File(
      'lib/modules/settings/play_settings_page.dart',
    ).readAsStringSync();
    final plugin = File(
      'ohos/entry/src/main/ets/plugins/OhosCapabilitiesPlugin.ets',
    ).readAsStringSync();

    expect(settings, contains('capabilities.pipCanHideDanmaku'));
    expect(settings, contains('capabilities.pipAutoOnLeaveSupported'));
    expect(settings, contains('Floating().isPipAvailable'));
    expect(plugin, contains('PiPWindow.isPiPEnabled()'));
    expect(plugin, contains("'pipAvailable': available"));
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

  test('supported device can report that the player is not ready', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isAvailable');
      return false;
    });

    expect((await service.getCapabilities()).pipAvailable, isTrue);
    expect(await service.isAvailable(), isFalse);
  });

  test('libmpv registers as the PiP target and switches surfaces', () {
    final registry = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/PipSurfaceRegistry.ets',
    ).readAsStringSync();
    final manager = File(
      'third_party/video_player_ohos/ohos/src/main/ets/components/'
      'videoplayer/OhosPipManager.ets',
    ).readAsStringSync();
    final plugin = File(
      'ohos/entry/src/main/ets/plugins/OhosMpvPlugin.ets',
    ).readAsStringSync();
    final nativeBridge = File(
      'ohos/entry/src/main/cpp/mpv_napi.cpp',
    ).readAsStringSync();

    expect(registry, contains('interface PipPlaybackTarget'));
    expect(registry, contains('registerPlaybackTarget'));
    expect(manager, contains('PipSurfaceRegistry.getPlaybackTarget()'));
    expect(plugin, contains('implements FlutterPlugin, MethodCallHandler, PipPlaybackTarget'));
    expect(plugin, contains('PipSurfaceRegistry.registerPlaybackTarget(this)'));
    expect(plugin, contains('mpvNapi.switchSurface(surfaceId, this.createSeq)'));
    expect(plugin, contains('mpvNapi.switchSurface(this.cachedSurfaceId, this.createSeq)'));
    expect(nativeBridge, contains('CommandType::SWITCH_SURFACE'));
    expect(nativeBridge, contains('command.generation != g_latestRequestedGeneration.load()'));
    expect(nativeBridge, contains('mpv_set_property_string(mpv, "vo", "null")'));
    expect(nativeBridge, contains('mpv_set_property_string(mpv, "wid", command.surfaceId.c_str())'));
    expect(nativeBridge, contains('mpv_set_property_string(mpv, "vo", "gpu-next")'));
  });

  test('manual PiP distinguishes device support from player readiness', () {
    final controller = File(
      'lib/modules/live_room/player/player_controller.dart',
    ).readAsStringSync();

    expect(controller, contains('if (!capabilities.pipAvailable)'));
    expect(controller, contains('设备不支持小窗播放'));
    expect(controller, contains('播放器尚未准备好，请稍后重试'));
  });

  test('capabilities are cached and normalized', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(capabilitiesChannel, (call) async {
      calls += 1;
      return {
        'pipAvailable': true,
        'pipAutoOnLeaveSupported': true,
        'pipCanHideDanmaku': false,
      };
    });

    final first = await service.getCapabilities();
    final second = await service.getCapabilities();

    expect(first.pipAvailable, isTrue);
    expect(first.pipAutoOnLeaveSupported, isTrue);
    expect(first.pipCanHideDanmaku, isFalse);
    expect(identical(first, second), isTrue);
    expect(calls, 1);
  });

  test('capability failures safely disable PiP settings', () async {
    messenger.setMockMethodCallHandler(capabilitiesChannel, (call) async {
      throw PlatformException(code: 'unsupported');
    });

    final capabilities = await service.getCapabilities();

    expect(capabilities.pipAvailable, isFalse);
    expect(capabilities.pipAutoOnLeaveSupported, isFalse);
    expect(capabilities.pipCanHideDanmaku, isFalse);
  });

  test('non-OHOS platforms never invoke the native channel', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls += 1;
      return true;
    });
    final otherPlatform = OhosPipService(
      channel: channel,
      capabilitiesChannel: capabilitiesChannel,
      isOhos: () => false,
    );

    expect(await otherPlatform.isAvailable(), isFalse);
    expect(await otherPlatform.enter(width: 16, height: 9), isFalse);
    expect(calls, 0);
    await otherPlatform.dispose();
  });
}
