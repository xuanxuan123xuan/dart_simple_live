import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/recordings/recording_player_page.dart';
import 'package:simple_live_app/modules/recordings/recording_preferences.dart';
import 'package:simple_live_app/modules/recordings/recording_session_tile.dart';
import 'package:simple_live_app/services/ohos_document_service.dart';
import 'package:simple_live_app/services/recording/recording_service.dart';

class RecordingsPage extends StatefulWidget {
  const RecordingsPage(
      {super.key,
      this.service,
      this.resolveDirectory,
      this.chooseDirectory,
      this.rememberDirectory});

  final RecordingService? service;
  final Future<Directory> Function()? resolveDirectory;
  final Future<Directory?> Function()? chooseDirectory;
  final Future<void> Function(Directory)? rememberDirectory;

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  late final RecordingService _service =
      widget.service ?? RecordingService.instance;
  Directory? _directory;
  String? _loadError;
  bool _loading = true;
  bool _loadingDirectory = false;
  final Set<String> _pendingActions = {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadSessions());
  }

  Future<void> _loadSessions() async {
    if (_loadingDirectory) return;
    _loadingDirectory = true;
    if (mounted) setState(() => _loading = true);
    try {
      final directory = await (widget.resolveDirectory?.call() ??
          resolveRecordingDirectory(create: true));
      await _service.initialize(directory.path);
      if (mounted) {
        setState(() {
          _directory = directory;
          _loading = false;
          _loadError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '读取录制列表失败：$error';
        });
      }
    } finally {
      _loadingDirectory = false;
    }
  }

  Future<void> _chooseDirectory() async {
    if (_loadingDirectory) return;
    if (_service.isRecording) {
      SmartDialog.showToast('录制期间不能更换保存目录');
      return;
    }
    _loadingDirectory = true;
    setState(() => _loading = true);
    try {
      final selected =
          await (widget.chooseDirectory?.call() ?? chooseRecordingDirectory());
      if (selected == null || !mounted) return;
      await _service.initialize(selected.path);
      await (widget.rememberDirectory?.call(selected) ??
          rememberRecordingDirectory(selected));
      if (mounted) {
        setState(() {
          _directory = selected;
          _loadError = null;
        });
      }
    } catch (error) {
      SmartDialog.showToast('切换保存目录失败：$error');
    } finally {
      _loadingDirectory = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteSession(RecordingSession session) async {
    final confirmed = await Utils.showDialogSafe<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除录制'),
        content: Text('确定删除“${session.roomTitle}”的录制文件吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runSessionAction(
        session, () => _service.deleteSession(session.id), '删除失败');
  }

  Future<void> _exportSession(RecordingSession session) async {
    await _runSessionAction(
        session,
        () => _service.exportSession(session.id,
            burnDanmaku: session.exportBurnDanmaku),
        '导出失败');
  }

  Future<void> _composeSession(RecordingSession session) => _runSessionAction(
      session,
      () => _service.exportSession(session.id, burnDanmaku: true),
      '合成失败');

  Future<void> _shareMaterials(RecordingSession session) async {
    final directory = session.directory;
    final archivePath = p.join(directory, 'danmaku-materials.zip');
    await _runSessionAction(session, () async {
      SmartDialog.showLoading(msg: '正在打包录制素材');
      try {
        await Isolate.run(() async {
          final encoder = ZipFileEncoder();
          encoder.create(archivePath);
          try {
            for (final name in ['raw.mkv', 'frames.jsonl', 'session.json']) {
              final file = File(p.join(directory, name));
              if (file.existsSync()) await encoder.addFile(file, name);
            }
            final sprites = Directory(p.join(directory, 'sprites'));
            if (sprites.existsSync()) {
              for (final entity in sprites.listSync()) {
                if (entity is File) {
                  await encoder.addFile(
                      entity, 'sprites/${p.basename(entity.path)}');
                }
              }
            }
          } finally {
            encoder.close();
          }
        });
      } finally {
        await SmartDialog.dismiss(status: SmartStatus.loading);
      }
      await _shareFiles([archivePath]);
    }, '素材导出失败', fileLease: true);
  }

  Future<void> _cancelExport(RecordingSession session) async {
    await _runSessionAction(
        session, () => _service.cancelExport(session.id), '取消导出失败');
  }

  Future<String> _existingOutput(RecordingSession session) async {
    final path = session.outputPath;
    if (path == null || path.isEmpty || !await File(path).exists()) {
      throw StateError('录制文件不存在');
    }
    return path;
  }

  Future<void> _shareSession(RecordingSession session) =>
      _runSessionAction(session, () async {
        final path = await _existingOutput(session);
        if (Utils.isOhos) {
          await OhosDocumentService.shareFile(path, title: p.basename(path));
        } else {
          await _shareFiles([path]);
        }
      }, '分享失败', fileLease: true);

  Future<void> _saveAs(RecordingSession session) =>
      _runSessionAction(session, () async {
        final path = await _existingOutput(session);
        if (Utils.isOhos) {
          SmartDialog.showToast('请使用分享功能保存录制文件');
          return;
        }
        if (!_isDesktop) {
          await _shareFiles([path], subject: '保存录制视频到文件');
          return;
        }
        final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
        final target = await FilePicker.platform.saveFile(
          dialogTitle: '另存录制文件',
          fileName: p.basename(path),
          type: extension.isEmpty ? FileType.any : FileType.custom,
          allowedExtensions: extension.isEmpty ? null : [extension],
        );
        if (target == null || p.equals(p.absolute(path), p.absolute(target))) {
          return;
        }
        await File(path).copy(target);
        SmartDialog.showToast('已另存录制文件');
      }, '另存失败', fileLease: true);

  Future<void> _playSession(RecordingSession session) =>
      _runSessionAction(session, () async {
        final path = await _existingOutput(session);
        if (!mounted) return;
        final lifetime = RecordingPlaybackLifetime();
        try {
          await Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => RecordingPlayerPage(
                path: path,
                lifetime: lifetime,
                title: session.roomTitle.isEmpty ? '录制回放' : session.roomTitle),
          ));
        } finally {
          await lifetime.close();
        }
      }, '播放失败', fileLease: true);

  Future<void> _runSessionAction(
      RecordingSession session, Future<void> Function() action, String failure,
      {bool fileLease = false}) async {
    if (!_pendingActions.add(session.id)) return;
    if (mounted) setState(() {});
    try {
      if (fileLease) {
        await _service.withSessionFiles(session.id, (_) => action());
      } else {
        await action();
      }
    } catch (error) {
      SmartDialog.showToast('$failure：$error');
    } finally {
      _pendingActions.remove(session.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _shareFiles(List<String> paths, {String? subject}) async {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    await Share.shareXFiles(paths.map((path) => XFile(path)).toList(),
        subject: subject, sharePositionOrigin: origin);
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('录制文件'),
        actions: [
          if (_isDesktop)
            IconButton(
              tooltip: '选择保存目录',
              onPressed: _loading ? null : _chooseDirectory,
              icon: const Icon(Icons.folder_open_outlined),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _loadSessions,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _service,
        builder: (context, _) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_loadError != null) {
            return _MessageState(
              message: _loadError!,
              action: TextButton.icon(
                onPressed: _loading ? null : _loadSessions,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            );
          }
          final sessions = _service.sessions.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          if (sessions.isEmpty) {
            return _MessageState(
              message: '还没有录制内容',
              detail: _directory == null ? null : '保存位置：${_directory!.path}',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final session = sessions[index];
              return RecordingSessionTile(
                session: session,
                operationBusy: _pendingActions.contains(session.id) ||
                    _service.isScanningDirectory,
                onDelete: () => _deleteSession(session),
                onExport: () => _exportSession(session),
                onCancelExport: () => _cancelExport(session),
                onShare: () => _shareSession(session),
                onSaveAs: () => _saveAs(session),
                onPlay: () => _playSession(session),
                onCompose: () => _composeSession(session),
                onShareMaterials: () => _shareMaterials(session),
              );
            },
          );
        },
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.detail, this.action});

  final String message;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (detail != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                detail!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
