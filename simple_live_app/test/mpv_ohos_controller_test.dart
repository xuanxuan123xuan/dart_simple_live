import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/mpv_ohos_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const method = MethodChannel('simple_live/ohos_mpv');
  const events = MethodChannel('simple_live/ohos_mpv_events');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('surface preserves landscape, portrait, square and cinema aspects', () {
    expect(mpvOhosSurfaceSize(const Size(1920, 1080)), const Size(1920, 1080));
    expect(mpvOhosSurfaceSize(const Size(720, 1280)), const Size(720, 1280));
    expect(mpvOhosSurfaceSize(const Size(1000, 1000)), const Size(1000, 1000));
    expect(mpvOhosSurfaceSize(const Size(1440, 1080)), const Size(1440, 1080));
    expect(mpvOhosSurfaceSize(const Size(3840, 1600)), const Size(3840, 1600));
    expect(mpvOhosSurfaceSize(const Size(721, 1281)), const Size(722, 1282));
    expect(mpvOhosSurfaceSize(Size.zero), const Size(1920, 1080));
  });
  late List<MethodCall> calls;
  late Map<String, String> properties;
  Future<void> Function(MethodCall)? reconfigure;

  Future<void> emit(String kind, String name,
      {String value = '', int generation = 7}) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      events.name,
      codec.encodeSuccessEnvelope({
        'kind': kind,
        'name': name,
        'value': value,
        'gen': generation,
      }),
      (_) => done.complete(),
    );
    await done.future;
  }

  setUp(() {
    calls = [];
    properties = {};
    reconfigure = null;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'create':
          return {'textureId': 3, 'generation': 7};
        case 'getSurfaceSize':
          return {'width': 1920, 'height': 1080};
        case 'getProperty':
          return properties[call.arguments['name']];
        case 'reconfigureSurface':
          await reconfigure?.call(call);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  Future<MpvOhosVideoController> open() async {
    final controller = MpvOhosVideoController(url: 'https://example.com/live');
    await controller.mpvCreate();
    await controller.mpvLoad(url: controller.dataSource);
    return controller;
  }

  Future<void> display(WidgetTester tester, int width, int height) async {
    properties['video-out-params/dw'] = '$width';
    properties['video-out-params/dh'] = '$height';
    await emit('property', 'video-out-params');
    await tester.pump();
  }

  Future<MpvOhosVideoController> visible(WidgetTester tester) async {
    final controller = await open();
    await emit('event', 'file-loaded');
    await display(tester, 1920, 1080);
    await emit('event', 'video-frame-presented');
    return controller;
  }

  testWidgets('consecutive and small size changes eventually reach the surface',
      (tester) async {
    final controller = await visible(tester);
    await display(tester, 1280, 720);
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.surfaceSize, const Size(1280, 720));
    // Arrives well inside the old five-second cooldown and two-percent cutoff.
    await display(tester, 1280, 728);
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.surfaceSize, const Size(1280, 728));
    await controller.dispose();
  });

  testWidgets('in-flight geometry updates serialize and keep the latest size',
      (tester) async {
    final controller = await visible(tester);
    final gate = Completer<void>();
    var updates = 0;
    reconfigure = (_) async {
      updates++;
      if (updates == 1) await gate.future;
    };
    await display(tester, 1280, 720);
    await tester.pump(const Duration(milliseconds: 300));
    await display(tester, 1440, 1080);
    await display(tester, 720, 1280);
    expect(updates, 1);
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(updates, 2);
    expect(controller.surfaceSize, const Size(720, 1280));
    await controller.dispose();
  });

  testWidgets('a failed update retries the newest size instead of the old one',
      (tester) async {
    final controller = await visible(tester);
    final gate = Completer<void>();
    var updates = 0;
    reconfigure = (_) async {
      if (++updates == 1) await gate.future;
    };
    await display(tester, 1280, 720);
    await tester.pump(const Duration(milliseconds: 300));
    await display(tester, 720, 1280);
    gate.completeError(PlatformException(code: 'surface_busy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(updates, 2);
    expect(controller.surfaceSize, const Size(720, 1280));
    await controller.dispose();
  });

  testWidgets('disposing cancels pending geometry work', (tester) async {
    final controller = await visible(tester);
    await display(tester, 1280, 720);
    await controller.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(calls.where((call) => call.method == 'reconfigureSurface'), isEmpty);
  });
  testWidgets(
      'opening a file without video does not satisfy first-frame timeout',
      (tester) async {
    final controller = await open();
    var frames = 0;
    controller.onFirstFrameDecoded = () => frames++;
    await emit('event', 'file-loaded');
    await tester.pump(const Duration(seconds: 4));
    expect(controller.visualReady, isFalse);
    expect(frames, 0);
    await controller.dispose();
  });

  testWidgets('old room events cannot reveal or end the new stream',
      (tester) async {
    final controller = await open();
    await emit('event', 'file-loaded');
    await emit('event', 'video-frame-presented', generation: 6);
    await emit('property', 'eof-reached', value: 'yes', generation: 6);
    expect(controller.visualReady, isFalse);
    expect(controller.eofReached, isFalse);
    properties.addAll({
      'video-out-params/dw': '1920',
      'video-out-params/dh': '1080',
    });
    await emit('property', 'video-out-params');
    await tester.pump();
    await emit('event', 'video-frame-presented');
    expect(controller.visualReady, isTrue);
    await controller.dispose();
  });

  testWidgets('an ended stream cannot be revealed by a delayed fallback',
      (tester) async {
    final controller = await open();
    await emit('event', 'file-loaded');
    await emit('event', 'end-file', value: 'stop');
    properties.addAll({
      'core-idle': 'no',
      'video-out-params/dw': '1920',
      'video-out-params/dh': '1080',
    });
    await tester.pump(const Duration(seconds: 4));
    expect(controller.visualReady, isFalse);
    await controller.dispose();
  });

  test('volume, speed and looping use the owning mpv generation', () async {
    final controller = await open();
    calls.clear();
    await controller.setVolume(.4);
    await controller.setPlaybackSpeed(1.1);
    await controller.setLooping(false);
    final writes = calls.where((call) => call.method == 'setProperty').toList();
    expect(writes.map((call) => call.arguments['name']),
        ['volume', 'speed', 'loop-file']);
    expect(writes.every((call) => call.arguments['generation'] == 7), isTrue);
    expect(controller.value.playbackSpeed, 1.1);
    await expectLater(
        controller.setPlaybackSpeed(double.nan), throwsArgumentError);
    await controller.dispose();
  });

  test('stable fallback restores options on the reused mpv player', () async {
    final controller = await open();
    Map<String, String> writes() => {
          for (final call
              in calls.where((call) => call.method == 'setProperty'))
            call.arguments['name'] as String: call.arguments['value'] as String,
        };

    for (final experimental in [false, true, false]) {
      calls.clear();
      await controller.applyPlaybackProfile(lowLatency: experimental);
      final options = writes();
      expect(options['video-sync'], experimental ? 'desync' : 'audio');
      expect(options['cache'], experimental ? 'no' : 'auto');
      expect(options['demuxer-lavf-o'], experimental ? 'fflags=+nobuffer' : '');
      expect(options['demuxer-lavf-analyzeduration'],
          experimental ? '0.5' : '1.5');
      expect(options['cache-pause'], 'no');
      expect(options['initial-audio-sync'], 'yes');
      expect(calls.every((call) => call.arguments['generation'] == 7), isTrue);
    }
    await controller.dispose();
  });

  test('a late creation is disposed without reopening a closed controller',
      () async {
    final gate = Completer<Object>();
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      return call.method == 'create' ? gate.future : null;
    });
    final controller = MpvOhosVideoController(url: 'https://example.com/live');
    final creation = controller.mpvCreate();
    await controller.dispose();
    gate.complete({'textureId': 3, 'generation': 7});
    await creation;
    expect(calls.last.method, 'dispose');
    expect(calls.last.arguments['generation'], 7);
    expect(calls.any((call) => call.method == 'getSurfaceSize'), isFalse);
  });
}
