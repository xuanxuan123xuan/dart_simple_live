import 'dart:async';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

void main() {
  test('parses comments, server cursor, default interval, and display counts',
      () {
    final page = XiaohongshuInteractionPage.fromResponse({
      'data': {
        'comments': [
          {
            'id': 'comment-1',
            'profile': {
              'nickname': '昵称',
              'avatar': 'https://example.com/avatar.jpg',
            },
            'desc': '评论正文',
            'createTime': 1712345678,
          },
        ],
        'endTimestamp': 456,
        'displayViewerCount': '1万+',
        'displayPraiseCount': '1千+',
      },
    });

    expect(page.endTimestamp, 456);
    expect(page.nextRequestInterval, const Duration(seconds: 5));
    expect(page.viewerCount, 10000);
    expect(page.praiseCount, 1000);
    expect(page.hasViewerCount, isTrue);
    expect(page.comments, hasLength(1));
    expect(page.comments.single.id, 'comment-1');
    expect(page.comments.single.userName, '昵称');
    expect(page.comments.single.message, '评论正文');
    expect(page.comments.single.timestamp, '1712345678');
    expect(page.comments.single.avatar, 'https://example.com/avatar.jpg');

    final zeroViewers = XiaohongshuInteractionPage.fromResponse({
      'data': {'viewerCount': '0', 'nextRequestInterval': 0},
    });
    expect(zeroViewers.viewerCount, 0);
    expect(zeroViewers.hasViewerCount, isTrue);
    expect(zeroViewers.nextRequestInterval, const Duration(seconds: 5));
  });

  test('starts at cursor zero, advances to endTimestamp, and deduplicates',
      () async {
    final cursors = <int>[];
    final messages = <LiveMessage>[];
    final danmaku = XiaohongshuDanmaku()..onMessage = messages.add;
    await danmaku.start(XiaohongshuDanmakuArgs(
      roomId: 'room-a',
      pollingIntervalOverride: Duration.zero,
      fetchPage: (cursor) async {
        cursors.add(cursor);
        if (cursors.length == 1) {
          return _page(
            endTimestamp: 123,
            viewerCount: 9,
            comments: [
              _comment(id: 'id-1', message: '有 id 的评论', timestamp: '10'),
              _comment(message: '同文', timestamp: '10'),
            ],
          );
        }
        return _page(
          endTimestamp: 456,
          viewerCount: 0,
          comments: [
            // The stable ID wins even if a server timestamp changes.
            _comment(id: 'id-1', message: '有 id 的评论', timestamp: '11'),
            // Repeated text at the same time is a duplicate.
            _comment(message: '同文', timestamp: '10'),
            // The timestamp keeps a later identical comment distinct.
            _comment(message: '同文', timestamp: '11'),
          ],
        );
      },
    ));

    await _waitUntil(() =>
        cursors.length >= 2 &&
        messages.where((item) => item.type == LiveMessageType.chat).length ==
            3);
    await danmaku.stop();

    expect(cursors, [0, 123]);
    final chats =
        messages.where((item) => item.type == LiveMessageType.chat).toList();
    expect(chats.map((item) => item.message), ['有 id 的评论', '同文', '同文']);
    expect(chats.every((item) => item.imageUrls == null), isTrue);
    expect(
      messages.map((item) => item.type).toSet(),
      {LiveMessageType.chat, LiveMessageType.online},
    );
    expect(
      messages
          .where((item) => item.type == LiveMessageType.online)
          .map((item) => item.data),
      [9, 0],
    );
  });

  test('retries the initial request and bounds failures without leaking errors',
      () async {
    final messages = <LiveMessage>[];
    final closeMessages = <String>[];
    var attempts = 0;
    final danmaku = XiaohongshuDanmaku()
      ..onMessage = messages.add
      ..onClose = closeMessages.add;

    await danmaku.start(XiaohongshuDanmakuArgs(
      roomId: 'room-retry',
      retryDelay: Duration.zero,
      fetchPage: (_) async {
        attempts++;
        if (attempts < 3) throw Exception('secret cookie=abc');
        return _page(endTimestamp: 20);
      },
    ));
    expect(attempts, 3);
    expect(closeMessages, isEmpty);
    await danmaku.stop();

    attempts = 0;
    await danmaku.start(XiaohongshuDanmakuArgs(
      roomId: 'room-failure',
      retryDelay: Duration.zero,
      fetchPage: (_) async {
        attempts++;
        throw Exception('response body contains cookie=secret');
      },
    ));
    expect(attempts, 3);
    expect(closeMessages, ['小红书评论连接失败，请稍后重试']);
    expect(closeMessages.single, isNot(contains('secret')));
    await danmaku.stop();

    attempts = 0;
    closeMessages.clear();
    await danmaku.start(XiaohongshuDanmakuArgs(
      roomId: 'room-core-error',
      retryDelay: Duration.zero,
      fetchPage: (_) async {
        attempts++;
        throw CoreError(
          'response contains cookie=secret',
          statusCode: 503,
          kind: CoreErrorKind.http,
        );
      },
    ));
    expect(attempts, 3);
    expect(closeMessages, ['小红书评论请求失败，请稍后重试']);
    expect(closeMessages.single, isNot(contains('secret')));
    await danmaku.stop();

    attempts = 0;
    closeMessages.clear();
    await danmaku.start(XiaohongshuDanmakuArgs(
      roomId: 'room-cancelled',
      retryDelay: Duration.zero,
      fetchPage: (_) async {
        attempts++;
        throw CoreError(
          'cookie=secret',
          kind: CoreErrorKind.cancelled,
        );
      },
    ));
    expect(attempts, 1);
    expect(closeMessages, ['小红书评论请求已取消']);
    expect(closeMessages.single, isNot(contains('secret')));
    await danmaku.stop();
  });

  test('stop cancels a pending retry timer and releases its waiter', () async {
    var attempts = 0;
    var stopCount = 0;
    final danmaku = XiaohongshuDanmaku();
    final start = danmaku.start(XiaohongshuDanmakuArgs(
      roomId: 'room-cancel-retry',
      onStop: () async => stopCount++,
      retryDelay: const Duration(days: 1),
      fetchPage: (_) async {
        attempts++;
        throw Exception('temporary');
      },
    ));

    await _waitUntil(() => attempts == 1);
    await danmaku.stop();
    await start;

    expect(attempts, 1);
    expect(stopCount, 1);
  });

  test('discards a late response from a replaced room and from stop', () async {
    final oldResponse = Completer<XiaohongshuInteractionPage>();
    final messages = <LiveMessage>[];
    var oldStopCount = 0;
    var newStopCount = 0;
    final danmaku = XiaohongshuDanmaku()..onMessage = messages.add;
    final oldStart = danmaku.start(XiaohongshuDanmakuArgs(
      roomId: 'old-room',
      onStop: () async => oldStopCount++,
      fetchPage: (_) => oldResponse.future,
    ));

    await danmaku.start(XiaohongshuDanmakuArgs(
      roomId: 'new-room',
      onStop: () async => newStopCount++,
      fetchPage: (_) async => _page(
        endTimestamp: 2,
        comments: [_comment(id: 'new', message: '新房间消息')],
      ),
    ));
    oldResponse.complete(_page(
      endTimestamp: 1,
      comments: [_comment(id: 'old', message: '旧房间消息')],
    ));
    await oldStart;

    expect(oldStopCount, 1);
    expect(
        messages
            .where((item) => item.type == LiveMessageType.chat)
            .map((item) => item.message),
        ['新房间消息']);
    await danmaku.stop();
    await danmaku.stop();
    expect(newStopCount, 1);

    final stoppedResponse = Completer<XiaohongshuInteractionPage>();
    final stoppedStart = danmaku.start(XiaohongshuDanmakuArgs(
      roomId: 'stopped-room',
      fetchPage: (_) => stoppedResponse.future,
    ));
    await danmaku.stop();
    stoppedResponse.complete(_page(
      endTimestamp: 3,
      comments: [_comment(id: 'stopped', message: '停止后的消息')],
    ));
    await stoppedStart;

    expect(
        messages
            .where((item) => item.type == LiveMessageType.chat)
            .map((item) => item.message),
        ['新房间消息']);
  });
}

XiaohongshuInteractionPage _page({
  int endTimestamp = 0,
  int viewerCount = 0,
  List<XiaohongshuComment> comments = const [],
}) =>
    XiaohongshuInteractionPage(
      comments: comments,
      endTimestamp: endTimestamp,
      nextRequestInterval: const Duration(seconds: 5),
      viewerCount: viewerCount,
      praiseCount: 99,
    );

XiaohongshuComment _comment({
  String id = '',
  required String message,
  String timestamp = '',
}) =>
    XiaohongshuComment(
      id: id,
      userName: '用户',
      message: message,
      timestamp: timestamp,
      avatar: 'https://example.com/avatar.jpg',
    );

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached while yielding to the event loop');
}
