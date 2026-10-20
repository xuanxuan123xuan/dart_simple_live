import 'package:flutter/material.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/recordings/recording_preferences.dart';
import 'package:simple_live_app/services/recording/recording_models.dart';

class RecordingSessionTile extends StatelessWidget {
  const RecordingSessionTile({
    required this.session,
    required this.onDelete,
    required this.onExport,
    required this.onCancelExport,
    required this.onShare,
    required this.onSaveAs,
    required this.onPlay,
    required this.onCompose,
    required this.onShareMaterials,
    super.key,
  });

  final RecordingSession session;
  final VoidCallback onDelete;
  final VoidCallback onExport;
  final VoidCallback onCancelExport;
  final VoidCallback onShare;
  final VoidCallback onSaveAs;
  final VoidCallback onPlay;
  final VoidCallback onCompose;
  final VoidCallback onShareMaterials;

  @override
  Widget build(BuildContext context) {
    final canExport = switch (session.status) {
      RecordingStatus.ready ||
      RecordingStatus.interrupted ||
      RecordingStatus.failed ||
      RecordingStatus.queued =>
        true,
      _ => false,
    };
    final taskBusy = session.status == RecordingStatus.recording ||
        session.status == RecordingStatus.exporting ||
        session.status == RecordingStatus.queued;
    final canPlay = !taskBusy && (session.outputPath?.isNotEmpty ?? false);
    final canCompose = !taskBusy &&
        session.mode != RecordingMode.videoOnly &&
        session.timelineConfirmed &&
        !session.captureFailed;
    final subtitle = _subtitle;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            ListTile(
              leading: Icon(_statusIcon, color: _statusColor(context)),
              title: Text(
                session.roomTitle.isEmpty ? '直播录制' : session.roomTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle:
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: '删除录制',
                onPressed: taskBusy ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ),
            if (session.status == RecordingStatus.exporting)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: LinearProgressIndicator(value: session.exportProgress),
              ),
            if (session.status == RecordingStatus.recording ||
                canExport ||
                session.status == RecordingStatus.exporting ||
                canPlay ||
                canCompose)
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  children: [
                    if (canCompose)
                      TextButton.icon(
                        onPressed: onCompose,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('合成弹幕'),
                      ),
                    if (!taskBusy && session.mode != RecordingMode.videoOnly)
                      TextButton.icon(
                        onPressed: onShareMaterials,
                        icon: const Icon(Icons.folder_zip_outlined),
                        label: const Text('导出弹幕素材'),
                      ),
                    if (canExport)
                      TextButton.icon(
                        onPressed: onExport,
                        icon: const Icon(Icons.refresh),
                        label: Text(session.status == RecordingStatus.ready
                            ? '导出'
                            : '重试导出'),
                      ),
                    if (session.status == RecordingStatus.exporting)
                      TextButton.icon(
                        onPressed: onCancelExport,
                        icon: const Icon(Icons.close),
                        label: const Text('取消导出'),
                      ),
                    if (canPlay) ...[
                      IconButton(
                        tooltip: '播放',
                        onPressed: onPlay,
                        icon: const Icon(Icons.play_arrow),
                      ),
                      IconButton(
                        tooltip: '分享',
                        onPressed: onShare,
                        icon: const Icon(Icons.share_outlined),
                      ),
                      IconButton(
                        tooltip: '另存为',
                        onPressed: onSaveAs,
                        icon: const Icon(Icons.save_alt),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String get _subtitle {
    final date = Utils.parseTime(session.createdAt);
    final duration = _formatDuration(session.durationMs);
    final mode = recordingModeLabel(session.mode);
    final statusText = switch (session.status) {
      RecordingStatus.recording => '录制中',
      RecordingStatus.interrupted => '录制中断',
      RecordingStatus.ready => '等待导出',
      RecordingStatus.queued => '等待处理',
      RecordingStatus.exporting => '正在导出',
      RecordingStatus.complete => '已完成',
      RecordingStatus.failed => '导出失败',
    };
    final details = <String>[date, duration, mode, statusText]
        .where((item) => item.isNotEmpty)
        .join(' · ');
    final error = session.error;
    return error == null || error.isEmpty ? details : '$details\n$error';
  }

  IconData get _statusIcon => switch (session.status) {
        RecordingStatus.recording => Icons.fiber_manual_record,
        RecordingStatus.interrupted => Icons.warning_amber_rounded,
        RecordingStatus.ready ||
        RecordingStatus.queued =>
          Icons.hourglass_empty,
        RecordingStatus.exporting => Icons.sync,
        RecordingStatus.complete => Icons.check_circle_outline,
        RecordingStatus.failed => Icons.error_outline,
      };

  Color _statusColor(BuildContext context) => switch (session.status) {
        RecordingStatus.recording => Colors.red,
        RecordingStatus.interrupted ||
        RecordingStatus.failed =>
          Theme.of(context).colorScheme.error,
        RecordingStatus.exporting ||
        RecordingStatus.queued =>
          Theme.of(context).colorScheme.primary,
        _ => Theme.of(context).colorScheme.secondary,
      };

  String _formatDuration(int milliseconds) {
    if (milliseconds <= 0) return '';
    final seconds = Duration(milliseconds: milliseconds).inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
