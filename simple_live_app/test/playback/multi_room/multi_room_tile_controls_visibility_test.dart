import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_player_controller.dart';

void main() {
  group('MultiRoomTileControlsVisibility', () {
    testWidgets('initial display auto-hides after the configured delay',
        (tester) async {
      final controls = MultiRoomTileControlsVisibility(
        hideDelay: const Duration(seconds: 5),
      );
      addTearDown(controls.dispose);

      controls.showTemporarily();
      expect(controls.visible.value, isTrue);

      await tester.pump(const Duration(seconds: 4));
      expect(controls.visible.value, isTrue);

      await tester.pump(const Duration(seconds: 1));
      expect(controls.visible.value, isFalse);
    });

    testWidgets('tap toggles visibility and restarts the hide countdown',
        (tester) async {
      final controls = MultiRoomTileControlsVisibility(
        hideDelay: const Duration(seconds: 5),
      );
      addTearDown(controls.dispose);

      controls.showTemporarily();
      await tester.pump(const Duration(seconds: 2));

      controls.toggle();
      expect(controls.visible.value, isFalse);

      controls.toggle();
      expect(controls.visible.value, isTrue);
      await tester.pump(const Duration(seconds: 4));
      expect(controls.visible.value, isTrue);

      await tester.pump(const Duration(seconds: 1));
      expect(controls.visible.value, isFalse);
    });

    testWidgets('dispose cancels a pending auto-hide timer', (tester) async {
      final controls = MultiRoomTileControlsVisibility(
        hideDelay: const Duration(seconds: 5),
      );

      controls.showTemporarily();
      controls.dispose();
      await tester.pump(const Duration(seconds: 5));

      expect(controls.visible.value, isTrue);
    });

    testWidgets('paused auto-hide keeps controls visible until resumed',
        (tester) async {
      final controls = MultiRoomTileControlsVisibility(
        hideDelay: const Duration(seconds: 5),
      );
      addTearDown(controls.dispose);

      controls.showTemporarily();
      await tester.pump(const Duration(seconds: 2));
      controls.pauseAutoHide();

      await tester.pump(const Duration(seconds: 10));
      expect(controls.visible.value, isTrue);

      controls.toggle();
      expect(controls.visible.value, isTrue);

      controls.resumeAutoHide();
      await tester.pump(const Duration(seconds: 4));
      expect(controls.visible.value, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(controls.visible.value, isFalse);
    });
  });
}
