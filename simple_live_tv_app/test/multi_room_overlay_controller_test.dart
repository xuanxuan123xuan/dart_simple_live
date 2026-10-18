import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_overlay_controller.dart';

void main() {
  const idleDuration = Duration(seconds: 5);

  testWidgets('starts visible and hides after five idle seconds',
      (tester) async {
    final controller = MultiRoomOverlayController(idleDuration: idleDuration);
    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(controller.visible, isTrue);
    await tester.pump(const Duration(milliseconds: 4999));
    expect(controller.visible, isTrue);
    await tester.pump(const Duration(milliseconds: 1));

    expect(controller.visible, isFalse);
    expect(notifications, 1);
    controller.dispose();
  });

  testWidgets('activity restarts the full idle interval', (tester) async {
    final controller = MultiRoomOverlayController(idleDuration: idleDuration);

    await tester.pump(const Duration(seconds: 4));
    controller.activity();
    await tester.pump(const Duration(seconds: 4));
    expect(controller.visible, isTrue);
    await tester.pump(const Duration(seconds: 1));

    expect(controller.visible, isFalse);
    controller.dispose();
  });

  testWidgets('nested holds block automatic and manual hiding until released',
      (tester) async {
    final controller = MultiRoomOverlayController(idleDuration: idleDuration);
    final releaseFirst = controller.hold();
    final releaseSecond = controller.hold();

    await tester.pump(const Duration(seconds: 10));
    controller.hide();
    expect(controller.visible, isTrue);

    releaseFirst();
    releaseFirst();
    await tester.pump(idleDuration);
    expect(controller.visible, isTrue);

    releaseSecond();
    await tester.pump(const Duration(milliseconds: 4999));
    expect(controller.visible, isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.visible, isFalse);
    releaseSecond();
    controller.dispose();
  });

  testWidgets('runs the focus callback before hiding and only once',
      (tester) async {
    late final MultiRoomOverlayController controller;
    var callbackCount = 0;
    controller = MultiRoomOverlayController(
      idleDuration: idleDuration,
      onBeforeHide: () {
        callbackCount++;
        expect(controller.visible, isTrue);
      },
    );
    var visibleAtNotification = true;
    controller.addListener(() {
      visibleAtNotification = controller.visible;
    });

    controller.hide();
    controller.hide();

    expect(callbackCount, 1);
    expect(controller.visible, isFalse);
    expect(visibleAtNotification, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(callbackCount, 1);
    controller.dispose();
  });

  testWidgets('activity from the before-hide callback cannot restart a timer',
      (tester) async {
    late final MultiRoomOverlayController controller;
    var callbackCount = 0;
    controller = MultiRoomOverlayController(
      idleDuration: idleDuration,
      onBeforeHide: () {
        callbackCount++;
        controller.activity();
      },
    );

    await tester.pump(idleDuration);
    expect(controller.visible, isFalse);
    expect(callbackCount, 1);
    await tester.pump(const Duration(seconds: 15));
    expect(controller.visible, isFalse);
    expect(callbackCount, 1);
    controller.dispose();
  });

  testWidgets('dispose cancels timers and ignores later activity and releases',
      (tester) async {
    final controller = MultiRoomOverlayController(idleDuration: idleDuration);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final release = controller.hold();

    controller.dispose();
    release();
    release();
    controller.activity();
    controller.hide();
    await tester.pump(const Duration(seconds: 10));

    expect(controller.visible, isTrue);
    expect(notifications, 0);
  });
}
