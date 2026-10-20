import 'package:flutter/material.dart';
import 'package:simple_live_app/modules/live_room/live_room_recording_coordinator.dart';

/// Shared by the room's top-right More sheet and fullscreen More panel.
class RecordingMenuTile extends StatelessWidget {
  const RecordingMenuTile(
      {required this.recording, required this.closeMenu, super.key});
  final LiveRoomRecordingCoordinator recording;
  final VoidCallback closeMenu;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: recording,
        builder: (context, _) => SwitchListTile(
          key: const ValueKey('live-room-recording-switch'),
          secondary: Icon(Icons.fiber_manual_record,
              color: recording.active ? Colors.redAccent : null),
          title: const Text('录制直播'),
          subtitle: Text(recording.busy
              ? '正在处理录制'
              : recording.active
                  ? '关闭开关停止并保存本段录制'
                  : '选择录制方式并保存到本地'),
          value: recording.active,
          onChanged: recording.busy
              ? null
              : (_) async {
                  final pageContext =
                      Navigator.of(context, rootNavigator: true).context;
                  closeMenu();
                  await Future<void>.delayed(Duration.zero);
                  if (pageContext.mounted) {
                    await recording.toggle(pageContext);
                  }
                },
        ),
      );
}
