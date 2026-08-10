import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/web_socket_util.dart';
import 'package:simple_live_core/src/danmaku/kuaishou_emoji_assets.dart';
import 'package:test/test.dart';

void main() {
  test('builds server Kww from the kwfv1 cookie', () {
    expect(
      KuaishouSite.resolveServerKww('did=1; kwfv1=abc%2B123', 'fallback'),
      'abc+123###ssrc',
    );
    expect(KuaishouSite.resolveServerKww('did=1', 'fallback'), 'fallback');
  });
  test('decodes Kuaishou comment feed', () {
    final messages = <LiveMessage>[];
    final danmaku = KuaishouDanmaku()..onMessage = messages.add;

    danmaku.decodeMessage(_socketMessage(_feedPush(), compressionType: 0));

    expect(messages, hasLength(1));
    expect(messages.single.type, LiveMessageType.chat);
    expect(messages.single.userName, '测试用户');
    expect(messages.single.message, '测试弹幕');
    expect(messages.single.color.toString(), '#ff6600');
  });

  test('extracts known kuaishou emoji into image spans', () {
    final messages = <LiveMessage>[];
    final danmaku = KuaishouDanmaku()..onMessage = messages.add;

    danmaku.decodeMessage(
      _socketMessage(
        _feedPushWithContent('你好[奸笑]呀'),
        compressionType: 0,
      ),
    );

    final msg = messages.single;
    // message 保留原始文本（渲染端优先使用 spans）。
    expect(msg.message, '你好[奸笑]呀');
    expect(msg.spans, isNotNull);
    expect(msg.spans!.length, 3);
    expect(msg.spans![0].isText, isTrue);
    expect(msg.spans![0].text, '你好');
    expect(msg.spans![1].isImage, isTrue);
    expect(msg.spans![1].imageUrl, kuaishouEmojiAssets['[奸笑]']);
    expect(msg.spans![2].isText, isTrue);
    expect(msg.spans![2].text, '呀');
    expect(msg.imageUrls, contains(kuaishouEmojiAssets['[奸笑]']));
  });

  test('unknown bracket tokens stay as plain text', () {
    final messages = <LiveMessage>[];
    final danmaku = KuaishouDanmaku()..onMessage = messages.add;

    danmaku.decodeMessage(
      _socketMessage(
        _feedPushWithContent('普通[文本]测试'),
        compressionType: 0,
      ),
    );

    final msg = messages.single;
    expect(msg.spans, isNotNull);
    expect(msg.spans!.where((s) => s.isImage), isEmpty);
    expect(msg.spans!.map((s) => s.text).join(), '普通[文本]测试');
    expect(msg.imageUrls, isNull);
  });

  test('mixed multiple emoji and unknown tokens', () {
    final messages = <LiveMessage>[];
    final danmaku = KuaishouDanmaku()..onMessage = messages.add;

    danmaku.decodeMessage(
      _socketMessage(
        _feedPushWithContent('[666][不存在的]哈'),
        compressionType: 0,
      ),
    );

    final msg = messages.single;
    expect(msg.spans, hasLength(3));
    expect(msg.spans![0].isImage, isTrue);
    expect(msg.spans![0].imageUrl, kuaishouEmojiAssets['[666]']);
    expect(msg.spans![1].isText, isTrue);
    expect(msg.spans![1].text, '[不存在的]');
    expect(msg.spans![2].isText, isTrue);
    expect(msg.spans![2].text, '哈');
    expect(msg.imageUrls, hasLength(1));
  });

  test('decodes gzip-compressed Kuaishou comment feed', () {
    final messages = <LiveMessage>[];
    final danmaku = KuaishouDanmaku()..onMessage = messages.add;

    danmaku.decodeMessage(_socketMessage(_feedPush(), compressionType: 2));

    expect(messages.single.message, '测试弹幕');
  });

  test('decrypts and decodes AES-compressed Kuaishou comment feed', () {
    final messages = <LiveMessage>[];
    final danmaku = KuaishouDanmaku()..onMessage = messages.add;

    danmaku.decodeMessage(
      _socketMessage(
        _feedPush(),
        compressionType: 3,
        encodedPayload: base64.decode(
          'o32YdlVhCk9udTvBfNXGJ5VQ19qLbG5TXKUw+Cff99wChoUXLYWVU32TZhBtEoqT',
        ),
      ),
    );

    expect(messages, hasLength(1));
    expect(messages.single.userName, '测试用户');
    expect(messages.single.message, '测试弹幕');
    expect(messages.single.color.toString(), '#ff6600');
  });

  test('rejects malformed AES payload without emitting a message', () {
    final messages = <LiveMessage>[];
    final danmaku = KuaishouDanmaku()..onMessage = messages.add;

    danmaku.decodeMessage(
      _socketMessage(
        _feedPush(),
        compressionType: 3,
        encodedPayload: const [1, 2, 3],
      ),
    );

    expect(messages, isEmpty);
  });

  test('automatically retries delayed Kuaishou danmaku credentials', () async {
    final connection = _FakeConnection();
    final timers = <_FakeTimer>[];
    final closeMessages = <String>[];
    var resolverCalls = 0;
    var readyCalls = 0;
    final danmaku = KuaishouDanmaku(
      connector: (_, __) => connection,
      credentialRetryTimerFactory: (_, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    )
      ..onClose = closeMessages.add
      ..onReady = () => readyCalls += 1;

    await danmaku.start(
      _missingCredentials(
        resolver: () async {
          resolverCalls += 1;
          return resolverCalls == 1 ? null : _readyCredentials();
        },
      ),
    );

    expect(resolverCalls, 1);
    expect(timers, hasLength(1));
    expect(closeMessages.single, contains('正在自动重试'));
    expect(connection.sent, isEmpty);

    timers.single.fire();
    await _flushAsync();

    expect(resolverCalls, 2);
    expect(readyCalls, 1);
    expect(connection.sent, hasLength(1));
    await danmaku.stop();
  });

  test('anonymous playback without danmaku data stays silent', () async {
    final closeMessages = <String>[];
    final danmaku = KuaishouDanmaku()..onClose = closeMessages.add;

    await danmaku.start(null);

    expect(closeMessages, isEmpty);
    await danmaku.stop();
  });

  test('stopping Kuaishou danmaku cancels credential retry', () async {
    final timers = <_FakeTimer>[];
    var resolverCalls = 0;
    final danmaku = KuaishouDanmaku(
      credentialRetryTimerFactory: (_, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    await danmaku.start(
      _missingCredentials(
        resolver: () async {
          resolverCalls += 1;
          return null;
        },
      ),
    );
    expect(timers.single.isActive, isTrue);

    await danmaku.stop();
    expect(timers.single.isActive, isFalse);
    timers.single.fire();
    await _flushAsync();

    expect(resolverCalls, 1);
  });

  test('credential retry stops after exhausting the attempt budget', () async {
    final timers = <_FakeTimer>[];
    final closeMessages = <String>[];
    var resolverCalls = 0;
    final danmaku = KuaishouDanmaku(
      credentialRetryTimerFactory: (_, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
      maxCredentialRetryAttempts: 3,
    )..onClose = closeMessages.add;

    await danmaku.start(
      _missingCredentials(
        resolver: () async {
          resolverCalls += 1;
          return null;
        },
      ),
    );

    // 首次失败已计数；再触发两次后预算（3 次）耗尽，停止自动重试。
    expect(resolverCalls, 1);
    for (var i = 0; i < 3; i++) {
      final active = timers.where((t) => t.isActive).toList();
      if (active.isEmpty) {
        break;
      }
      active.first.fire();
      await _flushAsync();
    }

    expect(closeMessages.any((m) => m.contains('停止自动重试')), isTrue);
    final activeTimers = timers.where((t) => t.isActive).toList();
    expect(activeTimers, isEmpty, reason: '预算耗尽后不应再安排重试定时器');
  });

  test('cooldown idle time does not consume the retry duration budget',
      () async {
    final timers = <_FakeTimer>[];
    final closeMessages = <String>[];
    var resolverCalls = 0;
    var now = DateTime(2026, 1, 1);
    var cooldownActive = false;
    final danmaku = KuaishouDanmaku(
      credentialRetryTimerFactory: (_, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
      maxCredentialRetryDuration: const Duration(seconds: 60),
      credentialCooldownCheck: () => cooldownActive,
      credentialRetryNow: () => now,
    )..onClose = closeMessages.add;

    await danmaku.start(
      _missingCredentials(
        resolver: () async {
          resolverCalls += 1;
          return null;
        },
      ),
    );
    expect(resolverCalls, 1);

    // 进入冷却并推进时间 120s（> 60s 时长预算）：空转期间应推进 startedAt，
    // 使冷却时间不计入时长预算，恢复后仍可继续重试。
    cooldownActive = true;
    now = now.add(const Duration(seconds: 120));
    final coolingTimer = timers.where((t) => t.isActive).toList().first;
    coolingTimer.fire();
    await _flushAsync();
    // 冷却空转不发请求。
    expect(resolverCalls, 1);

    // 冷却结束：恢复重试，不应因时长预算耗尽而停止。
    cooldownActive = false;
    final resumeTimer = timers.where((t) => t.isActive).toList().first;
    resumeTimer.fire();
    await _flushAsync();
    expect(resolverCalls, 2, reason: '冷却空转时间不应计入时长预算');
  });

  group('kuaishou emoji refresh', () {
    test('静态表兜底：未刷新时命中内置映射', () {
      expect(
        resolveKuaishouEmoji('[奸笑]'),
        kuaishouEmojiAssets['[奸笑]'],
      );
    });

    test('动态映射覆盖优先，未覆盖项仍走静态表', () async {
      await refreshKuaishouEmoji(
        fetcher: () async =>
            '{"data":{"[新表情]":"//cdn.test/emoji/new.png","[奸笑]":"//cdn.test/emoji/jx.png"}}',
      );
      expect(
        resolveKuaishouEmoji('[新表情]'),
        'https://cdn.test/emoji/new.png',
      );
      expect(
        resolveKuaishouEmoji('[奸笑]'),
        'https://cdn.test/emoji/jx.png',
      );
      // 动态表未覆盖的静态项仍可解析。
      expect(resolveKuaishouEmoji('[666]'), kuaishouEmojiAssets['[666]']);
    });

    test('刷新失败静默降级，内置表仍可用', () async {
      await refreshKuaishouEmoji(
        fetcher: () async => throw Exception('network down'),
      );
      expect(resolveKuaishouEmoji('[奸笑]'), isNotNull);
    });
  });
}

KuaishouDanmakuArgs _missingCredentials({
  required KuaishouDanmakuCredentialResolver resolver,
}) {
  return KuaishouDanmakuArgs(
    roomId: 'room',
    liveStreamId: 'stream',
    token: '',
    websocketUrls: const [],
    pageId: 'page',
    credentialResolver: resolver,
  );
}

KuaishouDanmakuArgs _readyCredentials() {
  return KuaishouDanmakuArgs(
    roomId: 'room',
    liveStreamId: 'stream',
    token: 'token',
    websocketUrls: const ['wss://socket.test/ws'],
    pageId: 'page',
  );
}

class _FakeConnection implements WebSocketConnection {
  final StreamController<dynamic> controller = StreamController<dynamic>();
  final List<dynamic> sent = <dynamic>[];
  bool closed = false;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  void add(dynamic message) => sent.add(message);

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _FakeTimer implements Timer {
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  _FakeTimer(this.callback);

  void fire() {
    if (!_active) return;
    _active = false;
    _tick += 1;
    callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Uint8List _feedPush() {
  final user = _ProtoWriter()..writeString(2, '测试用户');
  final comment = _ProtoWriter()
    ..writeBytes(2, user.takeBytes())
    ..writeString(3, '测试弹幕')
    ..writeString(6, '#ff6600');
  return (_ProtoWriter()..writeBytes(5, comment.takeBytes())).takeBytes();
}

Uint8List _feedPushWithContent(String content) {
  final user = _ProtoWriter()..writeString(2, '测试用户');
  final comment = _ProtoWriter()
    ..writeBytes(2, user.takeBytes())
    ..writeString(3, content)
    ..writeString(6, '#ffffff');
  return (_ProtoWriter()..writeBytes(5, comment.takeBytes())).takeBytes();
}

Uint8List _socketMessage(
  Uint8List feedPush, {
  required int compressionType,
  List<int>? encodedPayload,
}) {
  final payload = encodedPayload ??
      (compressionType == 2 ? gzip.encode(feedPush) : feedPush);
  final writer = _ProtoWriter()..writeVarint(1, 310);
  if (compressionType != 0) {
    writer.writeVarint(2, compressionType);
  }
  writer.writeBytes(3, payload);
  return writer.takeBytes();
}

class _ProtoWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void writeVarint(int fieldNumber, int value) {
    _writeValue(fieldNumber << 3);
    _writeValue(value);
  }

  void writeString(int fieldNumber, String value) {
    writeBytes(fieldNumber, utf8.encode(value));
  }

  void writeBytes(int fieldNumber, List<int> value) {
    _writeValue((fieldNumber << 3) | 2);
    _writeValue(value.length);
    _builder.add(value);
  }

  void _writeValue(int value) {
    var current = value;
    while (current >= 0x80) {
      _builder.addByte((current & 0x7f) | 0x80);
      current >>= 7;
    }
    _builder.addByte(current);
  }

  Uint8List takeBytes() => _builder.takeBytes();
}
