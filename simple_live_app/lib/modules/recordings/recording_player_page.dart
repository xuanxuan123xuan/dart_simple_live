import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/app/utils.dart';

class RecordingPlayerPage extends StatefulWidget {
  const RecordingPlayerPage({
    required this.path,
    required this.title,
    super.key,
  });

  final String path;
  final String title;

  @override
  State<RecordingPlayerPage> createState() => _RecordingPlayerPageState();
}

class _RecordingPlayerPageState extends State<RecordingPlayerPage> {
  Player? _player;
  VideoController? _videoController;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (Utils.isOhos) {
      _error = '本平台暂不支持在应用内播放录制文件';
      return;
    }
    final player =
        Player(configuration: PlayerConfiguration(title: widget.title));
    _player = player;
    _videoController = VideoController(player);
    unawaited(_open(player));
  }

  Future<void> _open(Player player) async {
    try {
      await player.open(Media(widget.path));
    } catch (error) {
      if (mounted) setState(() => _error = '打开录制文件失败：$error');
    }
  }

  @override
  void dispose() {
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videoController = _videoController;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              )
            : videoController == null
                ? const CircularProgressIndicator()
                : Video(controller: videoController),
      ),
    );
  }
}
