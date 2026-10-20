import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/live_room/live_room_recording_coordinator.dart';
import 'package:simple_live_app/modules/recordings/recording_menu_tile.dart';
import 'package:simple_live_app/modules/recordings/recording_session_tile.dart';
import 'package:simple_live_app/services/recording/recording_models.dart';

class _RoomRecording extends LiveRoomRecordingCoordinator {
  _RoomRecording()
      : super(
            player: () => throw StateError('No native player'),
            roomId: () => '1',
            roomTitle: () => 'room',
            platform: () => 'test',
            canRecord: () => true,
            danmakuVisible: () => true);
  bool enabled = false, working = false;
  int toggles = 0;
  int stops = 0;
  @override
  bool get active => enabled;
  @override
  bool get busy => working;
  @override
  Future<void> toggle(BuildContext context) async {
    toggles++;
  }

  @override
  Future<void> stop({String reason = 'test'}) async {
    stops++;
  }

  @override
  Future<void> close() async {
    enabled = false;
    await super.close();
  }
}

void main() {
  testWidgets('late capture errors cannot stop an inactive or closed room',
      (tester) async {
    final recording = _RoomRecording();
    recording.capture.onError!(StateError('late frame'), StackTrace.current);
    expect(recording.stops, 0);
    await recording.close();
    final stops = recording.stops;
    recording.capture.onError!(StateError('old callback'), StackTrace.current);
    expect(recording.stops, stops);
  });

  testWidgets('More menu switch closes menu before starting or stopping',
      (tester) async {
    final recording = _RoomRecording();
    var closed = 0;
    await tester.pumpWidget(GetMaterialApp(
        home: Scaffold(
            body: RecordingMenuTile(
                recording: recording, closeMenu: () => closed++))));
    expect(find.text('录制直播'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump(const Duration(milliseconds: 1));
    expect(closed, 1);
    expect(recording.toggles, 1);
    recording.enabled = true;
    recording.notifyListeners();
    await tester.pump(const Duration(milliseconds: 1));
    expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, true);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump(const Duration(milliseconds: 1));
    expect(recording.toggles, 2);
    await tester.pumpWidget(const SizedBox());
    await recording.close();
    Get.reset();
  });

  testWidgets('saved video and danmaku can compose later and export materials',
      (tester) async {
    final session = RecordingSession(
        id: 'test',
        directory: '/recordings/test',
        roomId: '1',
        roomTitle: 'room',
        platform: 'test',
        mode: RecordingMode.videoWithDanmaku,
        createdAt: DateTime(2026),
        status: RecordingStatus.complete,
        outputPath: 'recording.mp4',
        timelineConfirmed: true);
    var composed = 0, materials = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RecordingSessionTile(
      session: session,
      onCompose: () => composed++,
      onShareMaterials: () => materials++,
      onDelete: () {},
      onExport: () {},
      onCancelExport: () {},
      onShare: () {},
      onSaveAs: () {},
      onPlay: () {},
    ))));
    await tester.tap(find.text('合成弹幕'));
    await tester.tap(find.text('导出弹幕素材'));
    expect(composed, 1);
    expect(materials, 1);
  });
}
