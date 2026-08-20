import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';

class _TestPlayerController with PlayerMixin, PlayerStateMixin {}

void main() {
  testWidgets('volume overlay pauses single-room controls auto-hide',
      (tester) async {
    final controller = _TestPlayerController();
    addTearDown(() {
      controller.hideControlsTimer?.cancel();
      controller.hideMouseCursorTimer?.cancel();
    });

    controller.showControlsState.value = true;
    controller.resetHideControlsTimer();
    controller.pauseControlsAutoHide();

    await tester.pump(const Duration(seconds: 10));
    expect(controller.showControlsState.value, isTrue);

    controller.hideControls();
    expect(controller.showControlsState.value, isTrue);

    controller.resumeControlsAutoHide();
    await tester.pump(const Duration(seconds: 4));
    expect(controller.showControlsState.value, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.showControlsState.value, isFalse);
  });
}
