import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/web_socket_util.dart';
import 'package:simple_live_core/src/danmaku/kuaishou_emoji_assets.dart';
import 'package:simple_live_core/src/danmaku/kuaishou_mobile_emoji_assets.dart';
import 'package:test/test.dart';

import '../tool/generate_kuaishou_mobile_emoji.dart';

void main() {
  test('mobile emoji catalog matches the official Android snapshot', () {
    expect(kuaishouMobileEmojiClientVersion, '14.7.10.49551');
    expect(kuaishouMobileEmojiAssetCount, 258);
    expect(kuaishouMobileEmojiAssets, hasLength(258));
    expect(kuaishouMobileEmojiAssets.keys.toSet(), hasLength(258));
    for (final entry in kuaishouMobileEmojiAssets.entries) {
      expect(entry.key, matches(RegExp(r'^\[[^\[\]\r\n]{1,64}\]$')));
      final uri = Uri.parse(entry.value);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    }
    for (final token in const [
      '[都市丽人]',
      '[猪猪]',
      '[尊嘟假嘟]',
      '[憨笑哪吒]',
    ]) {
      expect(kuaishouMobileEmojiAssets[token], isNotNull);
      expect(resolveKuaishouEmoji(token), kuaishouMobileEmojiAssets[token]);
    }
  });

  test('mobile emoji extractor keeps aliases from every language group', () {
    final assets = collectKuaishouMobileEmojiAssets(
      {
        'emotionPackageList': [
          {
            'emotions': [
              {
                'bizType': 1,
                'emotionImageSmallUrl': [
                  {'url': '//cdn.test/emoji/base.png'},
                ],
                'emotionCodes': [
                  {
                    'language': 'zh_CN',
                    'codes': ['[点赞]'],
                  },
                  {
                    'language': 'zh_TW',
                    'codes': ['[點讚]'],
                  },
                  {
                    'language': 'en_US',
                    'codes': ['[like]'],
                  },
                ],
              },
            ],
          },
        ],
      },
    );

    expect(assets, hasLength(3));
    expect(assets['[点赞]'], 'https://cdn.test/emoji/base.png');
    expect(assets['[點讚]'], 'https://cdn.test/emoji/base.png');
    expect(assets['[like]'], 'https://cdn.test/emoji/base.png');
  });

  test('kuaishou emoji resolves known traditional and english aliases', () {
    expect(resolveKuaishouEmoji('[点点关注]'), isNotNull);
    expect(resolveKuaishouEmoji('[點點關注]'), resolveKuaishouEmoji('[点点关注]'));
    expect(resolveKuaishouEmoji('[ok]'), isNotNull);
    expect(resolveKuaishouEmoji('[OK]'), resolveKuaishouEmoji('[ok]'));
    expect(resolveKuaishouEmoji('[yes]'), isNotNull);
    expect(resolveKuaishouEmoji('[YES]'), resolveKuaishouEmoji('[yes]'));
    expect(resolveKuaishouEmoji('[no]'), isNotNull);
    expect(resolveKuaishouEmoji('[NO]'), resolveKuaishouEmoji('[no]'));
    expect(resolveKuaishouEmoji('[ILoveU]'), isNotNull);
    expect(resolveKuaishouEmoji('[iloveu]'), resolveKuaishouEmoji('[ILoveU]'));
  });

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
    expect(msg.spans![1].imageUrl, kuaishouMobileEmojiAssets['[奸笑]']);
    expect(msg.spans![1].fallbackText, '[奸笑]');
    expect(msg.spans![2].isText, isTrue);
    expect(msg.spans![2].text, '呀');
    expect(msg.imageUrls, contains(kuaishouMobileEmojiAssets['[奸笑]']));
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
    expect(msg.spans![0].imageUrl, kuaishouMobileEmojiAssets['[666]']);
    expect(msg.spans![0].fallbackText, '[666]');
    expect(msg.spans![1].isText, isTrue);
    expect(msg.spans![1].text, '[不存在的]');
    expect(msg.spans![2].isText, isTrue);
    expect(msg.spans![2].text, '哈');
    expect(msg.imageUrls, hasLength(1));
  });

  group('上游截断的尾部表情残片', () {
    LiveMessage? decodeContent(String content) {
      final messages = <LiveMessage>[];
      final danmaku = KuaishouDanmaku()..onMessage = messages.add;
      danmaku.decodeMessage(
        _socketMessage(
          _feedPushWithContent(content),
          compressionType: 0,
        ),
      );
      return messages.isEmpty ? null : messages.single;
    }

    test('截断在表情名中间时丢弃残片', () {
      final msg = decodeContent('[奸笑][奸')!;
      expect(msg.message, '[奸笑]');
      expect(msg.spans, hasLength(1));
      expect(msg.spans!.single.isImage, isTrue);
      expect(msg.spans!.single.fallbackText, '[奸笑]');
    });

    test('截断只剩裸左括号时丢弃残片', () {
      final msg = decodeContent('[奸笑][')!;
      expect(msg.message, '[奸笑]');
      expect(msg.spans, hasLength(1));
      expect(msg.spans!.single.isImage, isTrue);
    });

    test('字节截断产生的 U+FFFD 不影响识别', () {
      final withName = decodeContent('[奸笑][奸�')!;
      expect(withName.message, '[奸笑]');
      expect(withName.spans!.where((s) => s.isText), isEmpty);

      final bare = decodeContent('[奸笑][�')!;
      expect(bare.message, '[奸笑]');
      expect(bare.spans!.where((s) => s.isText), isEmpty);
    });

    test('大量表情后被截断时保留全部图片且不留残字', () {
      final content = '${'[奸笑]' * 20}[奸';
      final msg = decodeContent(content)!;
      expect(msg.message, '[奸笑]' * 20);
      expect(msg.spans, hasLength(20));
      expect(msg.spans!.where((s) => s.isImage), hasLength(20));
      expect(msg.spans!.where((s) => s.isText), isEmpty);
      expect(msg.imageUrls, hasLength(1));
    });

    test('残片就是整条内容时整条丢弃', () {
      expect(decodeContent('[奸'), isNull);
      expect(decodeContent('['), isNull);
      expect(decodeContent('[�'), isNull);
    });

    test('不像表情名但长度未超上限的残片同样丢弃（有意接受误判）', () {
      // 残片 7 字未超上限：不再校验是否为已知表情名前缀，一律丢弃。
      final msg = decodeContent('[奸笑][随便打的一段话')!;
      expect(msg.message, '[奸笑]');
      expect(msg.spans, hasLength(1));
      expect(msg.spans!.single.isImage, isTrue);
      expect(msg.spans!.where((s) => s.isText), isEmpty);
    });

    test('本地词库未收录的新表情残片也能丢弃（旧前缀校验的盲区）', () {
      // 旧实现要求残片是已知表情名前缀，快手新上线、词库还没收录的表情
      // 永远过不了校验，残片会漏到界面上；现在无条件丢弃。
      expect(resolveKuaishouEmoji('[全新未收录表情]'), isNull);
      final msg = decodeContent('[奸笑][全新未收录')!;
      expect(msg.message, '[奸笑]');
      expect(msg.spans, hasLength(1));
      expect(msg.spans!.single.isImage, isTrue);
      expect(msg.spans!.where((s) => s.isText), isEmpty);
    });

    test('残片超过长度上限时原样保留，避免吃掉长尾文本', () {
      // 残片 9 字 > 上限 8：视为用户真的打了方括号，整条原样保留。
      const content = '主播这个操作[笑死我了哈哈哈哈哈';
      final msg = decodeContent(content)!;
      expect(msg.message, content);
      expect(msg.spans!.where((s) => s.isImage), isEmpty);
      expect(
        msg.spans!.where((s) => s.isText).map((s) => s.text).join(),
        content,
      );
    });

    test('残片长度正好在上限边界上：8 字丢弃、9 字保留', () {
      const eight = '笑死我了哈哈哈哈';
      expect(eight.length, 8);
      final stripped = decodeContent('前缀文本[$eight')!;
      expect(stripped.message, '前缀文本');

      const nine = '笑死我了哈哈哈哈哈';
      expect(nine.length, 9);
      final kept = decodeContent('前缀文本[$nine')!;
      expect(kept.message, '前缀文本[$nine');
    });

    test('已闭合的未知 token 与普通结尾不受影响', () {
      expect(decodeContent('[不存在的]')!.message, '[不存在的]');
      expect(decodeContent('[奸笑]完整结尾')!.message, '[奸笑]完整结尾');
      expect(decodeContent('普通文本')!.message, '普通文本');
    });
  });

  test('parses official emoji tokens longer than the old 16 character limit',
      () async {
    const token = '[这是一个超过十六字符限制的移动端官方表情名称]';
    await refreshKuaishouEmoji(
      fetcher: () async =>
          '{"data":{"$token":"https://cdn.test/emoji/long.png"}}',
    );
    final messages = <LiveMessage>[];
    final danmaku = KuaishouDanmaku()..onMessage = messages.add;

    danmaku.decodeMessage(
      _socketMessage(
        _feedPushWithContent('前$token后'),
        compressionType: 0,
      ),
    );

    expect(messages.single.spans, hasLength(3));
    expect(messages.single.spans![1].fallbackText, token);
    expect(
      messages.single.spans![1].imageUrl,
      'https://cdn.test/emoji/long.png',
    );
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
    test('移动端词库兜底：未刷新时命中内置映射', () {
      expect(
        resolveKuaishouEmoji('[奸笑]'),
        kuaishouMobileEmojiAssets['[奸笑]'],
      );
    });

    test('动态映射覆盖优先，未覆盖项仍走移动端词库', () async {
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
      // 动态表未覆盖的移动端内置项仍可解析。
      expect(
        resolveKuaishouEmoji('[666]'),
        kuaishouMobileEmojiAssets['[666]'],
      );
    });

    test('动态映射覆盖移动端完整词库', () async {
      const token = '[都市丽人]';
      final mobileUrl = kuaishouMobileEmojiAssets[token];
      expect(mobileUrl, isNotNull);

      await refreshKuaishouEmoji(
        fetcher: () async =>
            '{"data":{"$token":"https://cdn.test/emoji/runtime.png"}}',
      );

      expect(
        resolveKuaishouEmoji(token),
        'https://cdn.test/emoji/runtime.png',
      );
      expect(resolveKuaishouEmoji(token), isNot(mobileUrl));
    });

    test('多次官方刷新采用合并更新且 URL 统一为 HTTPS', () async {
      await refreshKuaishouEmoji(
        fetcher: () async =>
            '{"data":{"[移动增量一]":"http://cdn.test/emoji/a.png"}}',
      );
      await refreshKuaishouEmoji(
        fetcher: () async => '{"data":{"[移动增量二]":"//cdn.test/emoji/b.png"}}',
      );

      expect(
        resolveKuaishouEmoji('[移动增量一]'),
        'https://cdn.test/emoji/a.png',
      );
      expect(
        resolveKuaishouEmoji('[移动增量二]'),
        'https://cdn.test/emoji/b.png',
      );
    });

    test('官方刷新忽略非 HTTPS 可规范化 URL', () async {
      await refreshKuaishouEmoji(
        fetcher: () async => '{"data":{"[非法地址]":"file:///tmp/emoji.png"}}',
      );
      expect(resolveKuaishouEmoji('[非法地址]'), isNull);
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
