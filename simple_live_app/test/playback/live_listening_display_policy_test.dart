import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/services/playback_display_coordinator.dart';

class _Player with PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin,
    PlayerSystemMixin {
  int pipCancellations = 0;

  @override
  Future<void> cancelAutoPipOnLeave() async {
    pipCancellations++;
  }
}

class _Display implements PlaybackDisplayGateway {
  bool awake = false;
  @override
  bool get requiresImmersiveRecheck => false;
  @override
  Future<void> setKeepScreenAwake(bool enabled) async => awake = enabled;
  @override
  Future<void> setImmersiveSystemUi(bool immersive) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async => Get.reset());

  test('playing events cannot keep the screen awake while listening or switching',
      () async {
    final gateway = _Display();
    final display = PlaybackDisplayCoordinator(gateway: gateway);
    Get.put(display);
    await display.initialize();
    final room = _Player()..initPlaybackDisplayLease();
    addTearDown(room.releasePlaybackDisplayLease);

    room.setPlaybackKeepScreenAwake(true);
    await display.settle();
    expect(gateway.awake, isTrue);

    room.listeningMode.value = true;
    room.setPlaybackKeepScreenAwake(true);
    await display.settle();
    expect(gateway.awake, isFalse);

    room.listeningMode.value = false;
    room.listeningModeChanging.value = true;
    room.setPlaybackKeepScreenAwake(true);
    await display.settle();
    expect(gateway.awake, isFalse);

    room.listeningModeChanging.value = false;
    room.setPlaybackKeepScreenAwake(false);
    await display.settle();
    expect(gateway.awake, isFalse, reason: 'returning to paused video stays asleep');
    room.setPlaybackKeepScreenAwake(true);
    await display.settle();
    expect(gateway.awake, isTrue);
  });

  testWidgets('listening controls remain visible without changing danmaku intent',
      (tester) async {
    final room = _Player();
    addTearDown(() {
      room.hideControlsTimer?.cancel();
      room.hideMouseCursorTimer?.cancel();
    });
    room.showDanmakuState.value = true;
    room.listeningMode.value = true;
    room.showControls();
    await tester.pump(const Duration(seconds: 10));
    expect(room.showControlsState.value, isTrue);
    expect(room.hideMouseCursorState.value, isFalse);
    expect(room.showDanmakuState.value, isTrue);

    room.listeningMode.value = false;
    room.showControls();
    await tester.pump(const Duration(seconds: 5));
    expect(room.showControlsState.value, isFalse);
    expect(room.showDanmakuState.value, isTrue);
  });

  test('listening and transitions cancel automatic PiP before platform access',
      () async {
    final room = _Player();
    room.listeningMode.value = true;
    expect(await room.prepareAutoPipOnLeave(), isFalse);
    room.listeningMode.value = false;
    room.listeningModeChanging.value = true;
    expect(await room.prepareAutoPipOnLeave(), isFalse);
    expect(room.pipCancellations, 2);
  });

  test('a new room starts in video mode with independent listening state', () {
    final oldRoom = _Player()..listeningMode.value = true;
    final newRoom = _Player();
    expect(oldRoom.videoPresentationEnabled, isFalse);
    expect(newRoom.listeningMode.value, isFalse);
    expect(newRoom.videoPresentationEnabled, isTrue);
  });
}
