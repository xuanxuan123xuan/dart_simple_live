import 'dart:async';

import 'package:simple_live_core/src/common/core_error.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/model/live_message.dart';

typedef XiaohongshuInteractionFetcher = Future<XiaohongshuInteractionPage>
    Function(int startTimestamp);

class XiaohongshuComment {
  XiaohongshuComment({
    required this.id,
    required this.userName,
    required this.message,
    this.avatar = '',
  });

  final String id;
  final String userName;
  final String message;
  final String avatar;
}

class XiaohongshuInteractionPage {
  XiaohongshuInteractionPage({
    required this.comments,
    required this.endTimestamp,
    required this.nextRequestInterval,
    required this.viewerCount,
    required this.praiseCount,
  });

  final List<XiaohongshuComment> comments;
  final int endTimestamp;
  final Duration nextRequestInterval;
  final int viewerCount;
  final int praiseCount;

  factory XiaohongshuInteractionPage.fromResponse(dynamic response) {
    final root = response is Map ? response : const <dynamic, dynamic>{};
    final data = root['data'] is Map ? root['data'] as Map : root;
    final comments = <XiaohongshuComment>[];
    final rawComments = data['comments'];
    if (rawComments is List) {
      for (final raw in rawComments) {
        if (raw is! Map) continue;
        final profile = raw['profile'] is Map ? raw['profile'] as Map : raw;
        final message = raw['desc']?.toString().trim() ?? '';
        final userName = profile['nickname']?.toString().trim() ?? '';
        if (message.isEmpty) continue;
        comments.add(XiaohongshuComment(
          id: raw['id']?.toString() ??
              raw['commentId']?.toString() ??
              '$userName:$message',
          userName: userName.isEmpty ? '小红书用户' : userName,
          message: message,
          avatar: profile['avatar']?.toString() ??
              profile['images']?.toString() ??
              '',
        ));
      }
    }
    final interval = _int(data['nextRequestInterval']);
    return XiaohongshuInteractionPage(
      comments: comments,
      endTimestamp: _int(data['endTimestamp']),
      nextRequestInterval: Duration(
        milliseconds: (interval > 0 ? interval : 5000).clamp(1000, 60000),
      ),
      viewerCount: _int(data['displayViewerCount'] ?? data['viewerCount']),
      praiseCount: _int(data['displayPraiseCount'] ?? data['praiseCount']),
    );
  }

  static int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class XiaohongshuDanmakuArgs {
  XiaohongshuDanmakuArgs({
    required this.roomId,
    required this.fetchPage,
  });

  final String roomId;
  final XiaohongshuInteractionFetcher fetchPage;
}

class XiaohongshuDanmaku implements LiveDanmaku {
  Timer? _timer;
  bool _stopped = true;
  int _cursor = 0;
  final Set<String> _seen = <String>{};

  @override
  Function(LiveMessage msg)? onMessage;

  @override
  Function(String msg)? onClose;

  @override
  Function()? onReady;

  @override
  int heartbeatTime = 5000;

  @override
  void heartbeat() {}

  @override
  Future<void> start(dynamic args) async {
    await stop();
    if (args is! XiaohongshuDanmakuArgs) return;
    _stopped = false;
    try {
      final page = await args.fetchPage(0);
      if (_stopped) return;
      _consume(page);
      _cursor = page.endTimestamp;
      onReady?.call();
      _schedule(args, page.nextRequestInterval);
    } catch (error) {
      if (!_stopped) onClose?.call(_messageForError(error));
    }
  }

  void _schedule(XiaohongshuDanmakuArgs args, Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => _poll(args));
  }

  Future<void> _poll(XiaohongshuDanmakuArgs args) async {
    if (_stopped) return;
    try {
      final page = await args.fetchPage(_cursor);
      if (_stopped) return;
      _consume(page);
      if (page.endTimestamp > _cursor) _cursor = page.endTimestamp;
      _schedule(args, page.nextRequestInterval);
    } catch (error) {
      if (_stopped) return;
      onClose?.call(_messageForError(error));
      _schedule(args, const Duration(seconds: 10));
    }
  }

  void _consume(XiaohongshuInteractionPage page) {
    if (page.viewerCount > 0) {
      onMessage?.call(LiveMessage(
        type: LiveMessageType.online,
        userName: '',
        message: '',
        data: page.viewerCount,
        color: LiveMessageColor.white,
      ));
    }
    for (final comment in page.comments) {
      final fingerprint = comment.id.isEmpty
          ? '${comment.userName}|${comment.message}'
          : comment.id;
      if (!_seen.add(fingerprint)) continue;
      if (_seen.length > 1000) _seen.remove(_seen.first);
      onMessage?.call(LiveMessage(
        type: LiveMessageType.chat,
        userName: comment.userName,
        message: comment.message,
        color: LiveMessageColor.white,
        imageUrls: comment.avatar.isEmpty ? null : [comment.avatar],
      ));
    }
  }

  String _messageForError(Object error) {
    if (error is CoreError && error.statusCode == 406) {
      return '小红书评论请求需要重新建立网页会话';
    }
    return '小红书评论连接失败：$error';
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    _cursor = 0;
    _seen.clear();
  }
}
