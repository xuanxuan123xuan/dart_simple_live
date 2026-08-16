import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';

class _TestPlayerController
    with
        PlayerMixin,
        PlayerStateMixin,
        PlayerDanmakuMixin,
        PlayerSystemMixin,
        PlayerGestureControlMixin {}

void main() {
  test('tap reveals the unlock control while fullscreen controls are locked',
      () {
    final controller = _TestPlayerController();
    controller.fullScreenState.value = true;
    controller.lockControlsState.value = true;
    controller.showControlsState.value = false;

    controller.onTap();

    expect(controller.showLockEdgeState.value, isTrue);
    expect(controller.showControlsState.value, isFalse);
  });

  test('a second tap hides the fullscreen unlock control again', () {
    final controller = _TestPlayerController();
    controller.fullScreenState.value = true;
    controller.lockControlsState.value = true;
    controller.showLockEdgeState.value = true;

    controller.onTap();

    expect(controller.showLockEdgeState.value, isFalse);
    expect(controller.lockControlsState.value, isTrue);
  });
}
