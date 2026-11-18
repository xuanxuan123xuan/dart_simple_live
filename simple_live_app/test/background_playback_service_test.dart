import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/background_playback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('simple_live/background_playback_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('serializes stop behind an in-flight start', () async {
    final calls = <String>[];
    final startGate = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'start') {
        await startGate.future;
      }
      return null;
    });
    final service = BackgroundPlaybackService.test(channel: channel);

    final start = service.start();
    await Future<void>.delayed(Duration.zero);
    final stop = service.stop();
    await Future<void>.delayed(Duration.zero);

    expect(calls, ['start']);
    startGate.complete();
    await Future.wait([start, stop]);
    expect(calls, ['start', 'stop']);
  });

  test('release is ordered after pending playback commands', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    final service = BackgroundPlaybackService.test(channel: channel);

    await service.start();
    await service.stop();
    await service.release();

    expect(calls, ['start', 'stop', 'release']);
  });

  test('sends current room metadata to the OHOS media session', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    final service = BackgroundPlaybackService.test(channel: channel);

    await service.updateMetadata(
      assetId: 'douyin:123',
      siteId: 'douyin',
      roomId: '123',
      title: '直播标题',
      artist: '主播',
      album: '抖音',
      artwork: ' https://example.com/cover.jpg ',
    );

    expect(received?.method, 'updateMetadata');
    expect(received?.arguments, {
      'assetId': 'douyin:123',
      'siteId': 'douyin',
      'roomId': '123',
      'title': '直播标题',
      'artist': '主播',
      'album': '抖音',
      'artwork': 'https://example.com/cover.jpg',
    });
  });

  test('does not send OHOS metadata on other platforms', () async {
    var callCount = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      callCount++;
      return null;
    });
    final service = BackgroundPlaybackService.test(
      channel: channel,
      ohos: false,
    );

    await service.updateMetadata(
      assetId: 'room',
      siteId: 'douyin',
      roomId: '123',
      title: 'title',
      artist: 'artist',
      album: 'site',
    );

    expect(callCount, 0);
  });
}
