import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/recording/recording_models.dart';

const _recordingModeKey = 'RecordingMode';
const _recordingDirectoryKey = 'RecordingDirectory';

String recordingModeLabel(RecordingMode mode) => switch (mode) {
      RecordingMode.videoOnly => '仅视频',
      RecordingMode.videoWithDanmaku => '视频＋弹幕数据',
      RecordingMode.burnDanmaku => '自动合成弹幕',
    };

String recordingModeDescription(RecordingMode mode) => switch (mode) {
      RecordingMode.videoOnly => '保存直播画面和声音。',
      RecordingMode.videoWithDanmaku => '保存视频、弹幕时间轴和图片资源，之后可手动合成。',
      RecordingMode.burnDanmaku => '停录后自动导出弹幕已烧入画面的 MP4 视频。',
    };

Future<RecordingMode?> chooseRecordingMode(BuildContext context) async {
  final storage = LocalStorageService.instance;
  final saved = storage.getValue<String>(_recordingModeKey, 'videoOnly');
  var selected = RecordingMode.values.firstWhere(
    (mode) => mode.name == saved,
    orElse: () => RecordingMode.videoOnly,
  );

  final result = await showDialog<RecordingMode>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('录制方式'),
        content: RadioGroup<RecordingMode>(
          groupValue: selected,
          onChanged: (value) {
            if (value != null) setDialogState(() => selected = value);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: RecordingMode.values.map((mode) {
              return RadioListTile<RecordingMode>(
                contentPadding: EdgeInsets.zero,
                value: mode,
                title: Text(recordingModeLabel(mode)),
                subtitle: Text(recordingModeDescription(mode)),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(selected),
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );

  if (result != null) {
    await storage.setValue(_recordingModeKey, result.name);
  }
  return result;
}

/// Picks and remembers a desktop destination. Phones use the app's documents
/// directory and do not show a platform file picker.
Future<Directory?> chooseRecordingDirectory() async {
  if (!_isDesktop) return resolveRecordingDirectory(create: true);

  final storage = LocalStorageService.instance;
  final initial = storage.getValue<String>(_recordingDirectoryKey, '');
  final selectedPath = await FilePicker.platform.getDirectoryPath(
    dialogTitle: '选择录制文件夹',
    initialDirectory: initial.isEmpty ? null : initial,
  );
  if (selectedPath == null || selectedPath.trim().isEmpty) return null;

  await storage.setValue(_recordingDirectoryKey, selectedPath);
  return Directory(selectedPath);
}

Future<Directory?> resolveOrChooseRecordingDirectory() async {
  if (_isDesktop &&
      LocalStorageService.instance
          .getValue<String>(_recordingDirectoryKey, '')
          .trim()
          .isEmpty) {
    return chooseRecordingDirectory();
  }
  return resolveRecordingDirectory(create: true);
}

/// Resolves the configured folder for session discovery and recording setup.
Future<Directory> resolveRecordingDirectory({bool create = false}) async {
  String? configured;
  if (_isDesktop) {
    final value = LocalStorageService.instance
        .getValue<String>(_recordingDirectoryKey, '');
    if (value.trim().isNotEmpty) configured = value;
  }
  final directory = configured == null
      ? Directory(
          p.join((await getApplicationDocumentsDirectory()).path, 'recordings'))
      : Directory(configured);
  if (create && !await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}

bool get _isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;
