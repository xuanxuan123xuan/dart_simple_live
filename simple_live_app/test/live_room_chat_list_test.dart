import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat list observes message and scroll state inside its local Obx', () {
    final source = File(
      'lib/modules/live_room/live_room_page.dart',
    ).readAsStringSync();
    final methodStart = source.indexOf('Widget buildChatList()');
    final methodEnd = source.indexOf(
      '\n  Widget buildLiveEventFlow()',
      methodStart,
    );

    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));

    final method = source.substring(methodStart, methodEnd);
    final builderStart = method.indexOf('return Builder(');
    final obxStart = method.indexOf('Obx(', builderStart);
    final stackStart = method.indexOf('Stack(', obxStart);

    expect(builderStart, greaterThanOrEqualTo(0));
    expect(obxStart, greaterThan(builderStart));
    expect(stackStart, greaterThan(obxStart));
    expect(method, contains('ScrollConfiguration.of(context)'));

    for (final dynamicRead in [
      'controller.messages.length',
      'controller.messages[i]',
      'controller.disableAutoScroll.value',
      'AppSettingsController.instance.chatTextGap.value',
    ]) {
      expect(
        method.indexOf(dynamicRead),
        greaterThan(obxStart),
        reason: '$dynamicRead must stay inside the local Obx',
      );
    }
  });
}
