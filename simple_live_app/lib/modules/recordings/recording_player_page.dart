import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_app/app/utils.dart';

/// Keeps the session's file lease until native playback has actually closed,
/// including the route's reverse transition and asynchronous widget disposal.
class RecordingPlaybackLifetime {
  Future<void> Function()? _close;
  bool _closing = false;
  Future<void> close() async {
    _closing = true;
    await _close?.call();
  }
}

class RecordingPlayerPage extends StatefulWidget {
  const RecordingPlayerPage({
    required this.path,
    required this.title,
    this.lifetime,
    super.key,
  });

  final String path;
  final String title;
  final RecordingPlaybackLifetime? lifetime;
  static final Set<Future<void> Function()> _closers = {};

  /// Keep the engine alive while local playback releases native video output.
  static Future<void> closeAll() async {
    await Future.wait(_closers.toList().map((close) => close()));
  }

  @override
  State<RecordingPlayerPage> createState() => _RecordingPlayerPageState();
}

class _RecordingPlayerPageState extends State<RecordingPlayerPage> {
  Player? _player;
  VideoController? _videoController;
  String? _error;
  bool _closing = false;
  Future<void>? _opening;
  Future<void>? _closePending;
  StreamSubscription<String>? _errors;

  @override
  void initState() {
    super.initState();
    widget.lifetime?._close = _closePlayer;
    if (widget.lifetime?._closing ?? false) {
      _closing = true;
      _error = '回放已关闭';
      return;
    }
    if (Utils.isOhos) {
      _error = '本平台暂不支持在应用内播放录制文件';
      return;
    }
    try {
      final player =
          Player(configuration: PlayerConfiguration(title: widget.title));
      _player = player;
      RecordingPlayerPage._closers.add(_closePlayer);
      _videoController = VideoController(player);
      _errors = player.stream.error.listen((error) {
        if (mounted && !_closing) setState(() => _error = '播放录制文件失败：$error');
      });
      _opening = _open(player);
    } catch (error) {
      _error = '创建回放播放器失败：$error';
    }
  }

  Future<void> _open(Player player) async {
    try {
      await player.open(Media(widget.path));
    } catch (error) {
      if (mounted && !_closing) setState(() => _error = '打开录制文件失败：$error');
    }
  }

  Future<void> _closePlayer() {
    return _closePending ??= _finishClose().then<void>((_) {},
        onError: (Object error, StackTrace stack) {
      _closePending = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _finishClose() async {
    _closing = true;
    await _errors?.cancel();
    await _opening;
    await _player?.dispose();
    RecordingPlayerPage._closers.remove(_closePlayer);
    widget.lifetime?._close = null;
  }

  @override
  void dispose() {
    unawaited(_closePlayer().catchError((Object error) {
      debugPrint('关闭录制回放播放器失败：$error');
    }));
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
