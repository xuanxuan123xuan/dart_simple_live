import 'dart:async';

import 'package:simple_live_core/src/common/core_error.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/model/live_message.dart';

typedef XiaohongshuInteractionFetcher = Future<XiaohongshuInteractionPage>
    Function(int startTimestamp);
typedef XiaohongshuDanmakuStopCallback = Future<void> Function();

class XiaohongshuComment {
  XiaohongshuComment({
    this.id = '',
    required this.userName,
    required this.message,
    this.timestamp = '',
    this.avatar = '',
  });

  final String id;
  final String userName;
  final String message;
  final String timestamp;
  final String avatar;
}

class XiaohongshuInteractionPage {
  XiaohongshuInteractionPage({
    required this.comments,
    this.endTimestamp = 0,
    this.nextRequestInterval = const Duration(seconds: 5),
    required this.viewerCount,
    required this.praiseCount,
    this.hasViewerCount = true,
  });

  final List<XiaohongshuComment> comments;
  final int endTimestamp;
  final Duration nextRequestInterval;
  final int viewerCount;
  final int praiseCount;
  final bool hasViewerCount;

  factory XiaohongshuInteractionPage.fromResponse(dynamic response) {
    final root = response is Map ? response : const <dynamic, dynamic>{};
    final data = root['data'] is Map ? root['data'] as Map : root;
    final comments = <XiaohongshuComment>[];
    final rawComments = data['comments'];
    if (rawComments is List) {
      for (final raw in rawComments) {
        if (raw is! Map) continue;
        final profile = raw['profile'] is Map
            ? raw['profile'] as Map
            : const <dynamic, dynamic>{};
        final message = raw['desc']?.toString().trim() ?? '';
        final userName = profile['nickname']?.toString().trim() ?? '';
        if (message.isEmpty) continue;
        comments.add(XiaohongshuComment(
          id: _firstText([raw['id'], raw['commentId']]),
          userName: userName.isEmpty ? '小红书用户' : userName,
          message: message,
          timestamp: _firstText([
            raw['timestamp'],
            raw['createTime'],
            raw['createdAt'],
            raw['create_time'],
            raw['time'],
          ]),
          avatar: _firstText([profile['avatar'], profile['images']]),
        ));
      }
    }
    final interval = _int(
      data['nextRequestInterval'] ?? data['next_request_interval'],
    );
    final viewerValue = data['displayViewerCount'] ?? data['viewerCount'];
    final praiseValue = data['displayPraiseCount'] ?? data['praiseCount'];
    return XiaohongshuInteractionPage(
      comments: comments,
      endTimestamp: _int(data['endTimestamp']),
      nextRequestInterval: Duration(
        milliseconds: (interval > 0 ? interval : 5000).clamp(1000, 60000),
      ),
      viewerCount: _count(viewerValue),
      praiseCount: _count(praiseValue),
      hasViewerCount: viewerValue != null,
    );
  }

  static String _firstText(Iterable<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _count(dynamic value) {
    if (value is num) return value.toInt();
    final text = value?.toString().trim().replaceAll(',', '') ?? '';
    final direct = int.tryParse(text);
    if (direct != null) return direct;
    final match = RegExp(r'^(\d+(?:\.\d+)?)(万|千|w)?\+?$', caseSensitive: false)
        .firstMatch(text);
    if (match == null) return 0;
    final count = double.tryParse(match.group(1)!);
    if (count == null) return 0;
    final unit = match.group(2)?.toLowerCase();
    final multiplier = switch (unit) {
      '千' => 1000,
      '万' || 'w' => 10000,
      _ => 1,
    };
    return (count * multiplier).round();
  }
}

class XiaohongshuDanmakuArgs {
  XiaohongshuDanmakuArgs({
    required this.roomId,
    required this.fetchPage,
    this.onStop,
    this.retryDelay = const Duration(seconds: 1),
    this.pollingIntervalOverride,
  });

  final String roomId;
  final XiaohongshuInteractionFetcher fetchPage;
  final XiaohongshuDanmakuStopCallback? onStop;

  /// Delay between the limited retries of a failed interaction request.
  final Duration retryDelay;

  /// Optional scheduling override for deterministic clients and tests.
  final Duration? pollingIntervalOverride;
}

class XiaohongshuDanmaku implements LiveDanmaku {
  static const int _maxAttempts = 3;

  Timer? _timer;
  Completer<void>? _retryWaiter;
  bool _stopped = true;
  int _cursor = 0;
  int _generation = 0;
  XiaohongshuDanmakuArgs? _activeArgs;
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
    final nextArgs = args is XiaohongshuDanmakuArgs ? args : null;
    final invalidation = _invalidateCurrentRun(nextArgs);
    final generation = _generation;
    await invalidation;
    if (nextArgs == null) return;
    if (generation != _generation) return;
    _stopped = false;
    final page = await _fetchPageWithRetries(nextArgs, 0, generation);
    if (page == null || !_isCurrent(generation)) return;

    _consume(page, requestCursor: 0);
    _cursor = page.endTimestamp;
    onReady?.call();
    _schedule(nextArgs, page.nextRequestInterval, generation);
  }

  void _schedule(
    XiaohongshuDanmakuArgs args,
    Duration delay,
    int generation,
  ) {
    if (!_isCurrent(generation)) return;
    _timer?.cancel();
    _timer = Timer(
      args.pollingIntervalOverride ?? delay,
      () => _poll(args, generation),
    );
  }

  Future<void> _poll(XiaohongshuDanmakuArgs args, int generation) async {
    if (!_isCurrent(generation)) return;
    _timer = null;
    final cursor = _cursor;
    final page = await _fetchPageWithRetries(args, cursor, generation);
    if (page == null || !_isCurrent(generation)) return;

    _consume(page, requestCursor: cursor);
    if (page.endTimestamp > _cursor) _cursor = page.endTimestamp;
    _schedule(args, page.nextRequestInterval, generation);
  }

  Future<XiaohongshuInteractionPage?> _fetchPageWithRetries(
    XiaohongshuDanmakuArgs args,
    int cursor,
    int generation,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      if (!_isCurrent(generation)) return null;
      try {
        final page = await args.fetchPage(cursor);
        return _isCurrent(generation) ? page : null;
      } catch (error) {
        if (!_isCurrent(generation)) return null;
        if (error is CoreError && error.kind == CoreErrorKind.cancelled) {
          _finishWithError(error, generation);
          return null;
        }
        lastError = error;
        if (attempt + 1 < _maxAttempts && args.retryDelay > Duration.zero) {
          await _waitBeforeRetry(args.retryDelay, generation);
        }
      }
    }
    if (_isCurrent(generation)) _finishWithError(lastError!, generation);
    return null;
  }

  void _finishWithError(Object error, int generation) {
    if (!_isCurrent(generation)) return;
    _stopped = true;
    _cancelTimer();
    _generation++;
    final onStop = _activeArgs?.onStop;
    _activeArgs = null;
    unawaited(_notifyStopped(onStop));
    onClose?.call(_messageForError(error));
  }

  void _consume(
    XiaohongshuInteractionPage page, {
    required int requestCursor,
  }) {
    if (page.hasViewerCount) {
      onMessage?.call(LiveMessage(
        type: LiveMessageType.online,
        userName: '',
        message: '',
        data: page.viewerCount,
        color: LiveMessageColor.white,
      ));
    }
    for (final comment in page.comments) {
      final fingerprint = _fingerprint(comment, page, requestCursor);
      if (!_seen.add(fingerprint)) continue;
      if (_seen.length > 1000) _seen.remove(_seen.first);
      onMessage?.call(LiveMessage(
        type: LiveMessageType.chat,
        userName: comment.userName,
        message: comment.message,
        color: LiveMessageColor.white,
      ));
    }
  }

  String _fingerprint(
    XiaohongshuComment comment,
    XiaohongshuInteractionPage page,
    int requestCursor,
  ) {
    if (comment.id.isNotEmpty) return 'id:${comment.id}';
    final timestamp = comment.timestamp.isNotEmpty
        ? comment.timestamp
        : page.endTimestamp != 0
            ? page.endTimestamp.toString()
            : requestCursor.toString();
    return 'text:$timestamp|${comment.userName}|${comment.message}';
  }

  String _messageForError(Object error) {
    if (error is! CoreError) return '小红书评论连接失败，请稍后重试';

    switch (error.statusCode) {
      case 406:
        return '小红书评论请求需要重新建立网页会话';
      case 401:
      case 403:
        return '小红书评论访问受限，请检查网页会话';
      case 404:
        return '小红书直播间评论不可用';
      case 429:
        return '小红书评论请求过于频繁，请稍后再试';
    }

    return switch (error.kind) {
      CoreErrorKind.cancelled => '小红书评论请求已取消',
      CoreErrorKind.network => '小红书评论网络连接失败，请检查网络后重试',
      CoreErrorKind.http => '小红书评论请求失败，请稍后重试',
      CoreErrorKind.response => '小红书评论响应异常，请稍后重试',
      CoreErrorKind.search || CoreErrorKind.unknown => '小红书评论连接失败，请稍后重试',
    };
  }

  bool _isCurrent(int generation) => !_stopped && generation == _generation;

  Future<int> _invalidateCurrentRun(
    XiaohongshuDanmakuArgs? nextArgs,
  ) async {
    _generation++;
    final generation = _generation;
    _stopped = true;
    _cancelTimer();
    _cursor = 0;
    _seen.clear();
    final onStop = _activeArgs?.onStop;
    _activeArgs = nextArgs;
    await _notifyStopped(onStop);
    return generation;
  }

  Future<void> _waitBeforeRetry(Duration delay, int generation) {
    if (!_isCurrent(generation)) return Future<void>.value();
    final waiter = Completer<void>();
    _retryWaiter = waiter;
    _timer = Timer(delay, () {
      if (identical(_retryWaiter, waiter)) {
        _retryWaiter = null;
        _timer = null;
      }
      if (!waiter.isCompleted) waiter.complete();
    });
    return waiter.future;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    final waiter = _retryWaiter;
    _retryWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<void> _notifyStopped(XiaohongshuDanmakuStopCallback? onStop) async {
    if (onStop == null) return;
    try {
      await onStop();
    } catch (_) {
      // Stopping the polling loop must remain safe if the web session is gone.
    }
  }

  @override
  Future<void> stop() async {
    await _invalidateCurrentRun(null);
  }
}
