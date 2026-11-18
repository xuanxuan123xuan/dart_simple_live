import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/live_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('simple_live/live_notifications_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('parses a valid notification target', () {
    final target = LiveNotificationTarget.tryParse(const {
      'siteId': 'kuaishou',
      'roomId': 'room-1',
    });

    expect(target?.siteId, 'kuaishou');
    expect(target?.roomId, 'room-1');
  });

  test('rejects incomplete or empty notification targets', () {
    expect(
      LiveNotificationTarget.tryParse(const {'siteId': 'kuaishou'}),
      isNull,
    );
    expect(
      LiveNotificationTarget.tryParse(const {
        'siteId': 'kuaishou',
        'roomId': '   ',
      }),
      isNull,
    );
    expect(LiveNotificationTarget.tryParse('invalid'), isNull);
  });

  test('consumes a pending native target and opens it once', () async {
    var nativeCalls = 0;
    final opened = <LiveNotificationTarget>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'consumeNotificationTarget');
      nativeCalls += 1;
      if (nativeCalls == 1) {
        return const {
          'siteId': 'bilibili',
          'roomId': '123',
        };
      }
      return null;
    });
    final bridge = OhosNotificationTargetBridge(
      channel: channel,
      onTarget: opened.add,
    );

    await bridge.consumePendingTarget();
    await bridge.consumePendingTarget();

    expect(nativeCalls, 2);
    expect(opened, hasLength(1));
    expect(opened.single.siteId, 'bilibili');
    expect(opened.single.roomId, '123');
  });

  test('serializes concurrent notification target consumption', () async {
    final nativeCalls = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final sequence = nativeCalls.length + 1;
      nativeCalls.add(sequence);
      return {
        'siteId': 'douyu',
        'roomId': '$sequence',
      };
    });
    final opened = <String>[];
    final bridge = OhosNotificationTargetBridge(
      channel: channel,
      onTarget: (target) => opened.add(target.roomId),
    );

    await Future.wait([
      bridge.consumePendingTarget(),
      bridge.consumePendingTarget(),
    ]);

    expect(nativeCalls, [1, 2]);
    expect(opened, ['1', '2']);
  });
}
