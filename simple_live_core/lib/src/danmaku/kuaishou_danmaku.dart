import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/web_socket_util.dart';
import 'package:simple_live_core/src/danmaku/kuaishou_emoji_assets.dart';

const _kuaishouAesKey = 'PPbzKKL7NB15leYy';
const _kuaishouAesIv = 'JRODKJiolJ9xqso0';

typedef KuaishouDanmakuCredentialResolver = Future<KuaishouDanmakuArgs?>
    Function();

class KuaishouDanmakuArgs {
  final String roomId;
  final String liveStreamId;
  final String token;
  final List<String> websocketUrls;
  final String pageId;
  final String expTag;
  final String attach;
  final String cookie;
  final String userAgent;
  final KuaishouDanmakuCredentialResolver? credentialResolver;

  KuaishouDanmakuArgs({
    required this.roomId,
    required this.liveStreamId,
    required this.token,
    required this.websocketUrls,
    required this.pageId,
    this.expTag = '',
    this.attach = '',
    this.cookie = '',
    this.credentialResolver,
    this.userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  });

  bool get hasConnectionInfo =>
      liveStreamId.isNotEmpty && token.isNotEmpty && websocketUrls.isNotEmpty;

  KuaishouDanmakuArgs copyWith({
    String? roomId,
    String? liveStreamId,
    String? token,
    List<String>? websocketUrls,
    String? pageId,
    String? expTag,
    String? attach,
    String? cookie,
    String? userAgent,
    KuaishouDanmakuCredentialResolver? credentialResolver,
  }) {
    return KuaishouDanmakuArgs(
      roomId: roomId ?? this.roomId,
      liveStreamId: liveStreamId ?? this.liveStreamId,
      token: token ?? this.token,
      websocketUrls: websocketUrls ?? this.websocketUrls,
      pageId: pageId ?? this.pageId,
      expTag: expTag ?? this.expTag,
      attach: attach ?? this.attach,
      cookie: cookie ?? this.cookie,
      userAgent: userAgent ?? this.userAgent,
      credentialResolver: credentialResolver ?? this.credentialResolver,
    );
  }

  @override
  String toString() {
    return json.encode({
      "roomId": roomId,
      "liveStreamId": liveStreamId,
      "token": token.isEmpty ? "" : "***",
      "websocketUrls": websocketUrls,
      "pageId": pageId,
      "expTag": expTag,
      "attach": attach,
      "cookie": cookie.isEmpty ? "" : "***",
      "userAgent": userAgent,
    });
  }
}

class KuaishouDanmaku extends LiveDanmaku {
  KuaishouDanmaku({
    WebSocketConnector? connector,
    WebSocketRetryTimerFactory? socketRetryTimerFactory,
    WebSocketRetryTimerFactory? credentialRetryTimerFactory,
    this.credentialRetryDelay = const Duration(seconds: 5),
    this.credentialCooldownCheck,
    this.maxCredentialRetryAttempts = _kMaxCredentialRetryAttempts,
    this.maxCredentialRetryDuration = _kMaxCredentialRetryDuration,
    DateTime Function()? credentialRetryNow,
  })  : _connector = connector,
        _socketRetryTimerFactory = socketRetryTimerFactory,
        _credentialRetryTimerFactory =
            credentialRetryTimerFactory ?? _defaultCredentialRetryTimer,
        _credentialNow = credentialRetryNow ?? DateTime.now {
    heartbeatTime = 20 * 1000;
    _maybeRefreshEmoji();
  }

  /// S5-T3：凭证自动重试的收敛参数（阶段 6 真机验收后再定稿）。
  ///
  /// 背景（docs/快手直播请求频率限制设计.md 7.2 / 9.5）：房间 HTML 缺
  /// liveStreamId/token 时，`_resolveDanmakuCredentials` 会再抓房间详情并
  /// 请求 websocketinfo，而凭证重试每 5s 一次、无总次数/总时长上限，形成
  /// "越失败越请求"的正反馈（受限后延长恢复）。这里给自动重试加硬上限：
  ///
  /// 1. 连续解析失败 [maxCredentialRetryAttempts] 次（默认 10）即停止；
  /// 2. 从首次失败起超过 [maxCredentialRetryDuration]（默认 60s）也停止；
  ///    达到上限后等待显式触发（重新 start / 房间刷新），不再后台请求。
  ///
  /// 另按失败次数线性退避重试间隔（基础 [credentialRetryDelay] × 次数，
  /// 封顶 [_kMaxCredentialRetryBackoffFactor] 倍，默认 30s），保证"播放画面
  /// 已可用而弹幕凭证缺失"时不会继续高频打详情/websocketinfo 接口。
  static const int _kMaxCredentialRetryAttempts = 10;
  static const Duration _kMaxCredentialRetryDuration = Duration(seconds: 60);
  static const int _kMaxCredentialRetryBackoffFactor = 6;

  /// 全局只拉取一次最新表情映射（进程内）；cookie 变化（用户登录
  /// 后带 cookie 再刷一次）除外。失败静默走内置表。
  static bool _emojiRefreshStarted = false;
  static String? _lastRefreshCookie;

  void _maybeRefreshEmoji([String? cookie]) {
    final effective = (cookie == null || cookie.isEmpty) ? null : cookie;
    if (_emojiRefreshStarted && effective == _lastRefreshCookie) {
      return;
    }
    _emojiRefreshStarted = true;
    _lastRefreshCookie = effective;
    unawaited(refreshKuaishouEmoji(cookie: effective));
  }

  final WebSocketConnector? _connector;
  final WebSocketRetryTimerFactory? _socketRetryTimerFactory;
  final WebSocketRetryTimerFactory _credentialRetryTimerFactory;
  final Duration credentialRetryDelay;

  /// 可选：协调器冷却检查，如 `() => site.coordinator.inCooldown`。
  ///
  /// KuaishouDanmaku 不持有 KuaishouSite 引用（`kuaishou_site.dart` 用
  /// `KuaishouDanmaku()` 无参构造），resolver 闭包也不暴露协调器，因此
  /// 由接线方注入冷却状态检查。默认 null = 不检查，保持与现有调用方兼容。
  /// 注入后：冷却期间凭证重试暂停（不发起任何敏感请求），冷却结束自动恢复，
  /// 且不消耗重试预算。阶段 6 在站点侧接线。
  final bool Function()? credentialCooldownCheck;

  /// 凭证自动重试的总次数/总时长上限（S5-T3，阶段 6 真机验收后定稿）。
  final int maxCredentialRetryAttempts;
  final Duration maxCredentialRetryDuration;

  /// 凭证重试计时的时钟源（可注入以便测试总时长上限）。
  final DateTime Function() _credentialNow;

  WebScoketUtils? webScoketUtils;
  KuaishouDanmakuArgs? danmakuArgs;
  Timer? _credentialRetryTimer;
  KuaishouDanmakuCredentialResolver? _credentialResolver;
  int _startGeneration = 0;
  bool _credentialRetryNotified = false;
  int _credentialRetryAttempts = 0;
  DateTime? _credentialRetryStartedAt;

  static Timer _defaultCredentialRetryTimer(
    Duration delay,
    void Function() callback,
  ) {
    return Timer(delay, callback);
  }

  @override
  Future start(dynamic args) async {
    final generation = ++_startGeneration;
    _credentialRetryTimer?.cancel();
    _credentialRetryTimer = null;
    _credentialRetryNotified = false;
    _credentialRetryAttempts = 0;
    _credentialRetryStartedAt = null;
    if (args == null) {
      return;
    }
    if (args is! KuaishouDanmakuArgs) {
      onClose?.call("快手弹幕凭证尚未就绪，请稍后刷新直播间重试");
      return;
    }

    danmakuArgs = args;
    _credentialResolver = args.credentialResolver;
    _maybeRefreshEmoji(args.cookie);
    if (!args.hasConnectionInfo) {
      await _resolveCredentials(generation);
      return;
    }
    await _connect(args, generation);
  }

  Future<void> _resolveCredentials(int generation) async {
    if (generation != _startGeneration) {
      return;
    }
    // S5-T3：协调器冷却期间暂停凭证请求（不发起任何敏感请求），仅保留
    // 本地轮询定时器，冷却结束后自动恢复；冷却等待不消耗重试预算——
    // 将时长起点推进到当前时刻，使冷却空转时间不计入 60s 时长上限。
    if (credentialCooldownCheck?.call() ?? false) {
      _credentialRetryStartedAt = _credentialNow();
      _armCredentialRetryTimer(generation);
      return;
    }
    final resolver = _credentialResolver;
    if (resolver == null) {
      onClose?.call("快手弹幕凭证尚未就绪，请稍后刷新直播间重试");
      return;
    }
    try {
      final resolved = await resolver();
      if (generation != _startGeneration) {
        return;
      }
      if (resolved != null && resolved.hasConnectionInfo) {
        danmakuArgs = resolved;
        await _connect(resolved, generation);
        return;
      }
    } catch (e) {
      CoreLog.error(e);
    }
    _scheduleCredentialRetry(generation);
  }

  /// S5-T3：记录一次凭证解析失败并安排下一次重试；
  /// 超过总次数/总时长上限后停止自动重试，等待显式触发（重新 start / 刷新）。
  void _scheduleCredentialRetry(int generation) {
    if (generation != _startGeneration || _credentialRetryTimer != null) {
      return;
    }
    _credentialRetryAttempts += 1;
    _credentialRetryStartedAt ??= _credentialNow();
    if (_credentialRetryBudgetExhausted()) {
      onClose?.call(
        "快手弹幕凭证持续获取失败，已停止自动重试，请刷新直播间重试",
      );
      return;
    }
    _armCredentialRetryTimer(generation);
  }

  /// 安排一次凭证重试定时器（含冷却等待期的空转轮询，不发请求）。
  ///
  /// 重试间隔按失败次数线性退避：`credentialRetryDelay × attempts`，
  /// 封顶 [_kMaxCredentialRetryBackoffFactor] 倍，避免"播放画面已可用而弹幕
  /// 凭证缺失"时继续高频打详情/websocketinfo 接口（设计文档 9.5）。
  void _armCredentialRetryTimer(int generation) {
    if (generation != _startGeneration || _credentialRetryTimer != null) {
      return;
    }
    if (!_credentialRetryNotified) {
      _credentialRetryNotified = true;
      onClose?.call("快手弹幕凭证尚未就绪，正在自动重试");
    }
    final factor = _credentialRetryAttempts.clamp(
      1,
      _kMaxCredentialRetryBackoffFactor,
    );
    _credentialRetryTimer = _credentialRetryTimerFactory(
      credentialRetryDelay * factor,
      () {
        _credentialRetryTimer = null;
        if (generation != _startGeneration) {
          return;
        }
        unawaited(_resolveCredentials(generation));
      },
    );
  }

  /// 自动重试预算是否已耗尽：次数达上限，或自首次失败起总时长达上限。
  bool _credentialRetryBudgetExhausted() {
    if (_credentialRetryAttempts >= maxCredentialRetryAttempts) {
      return true;
    }
    final startedAt = _credentialRetryStartedAt;
    if (startedAt != null &&
        _credentialNow().difference(startedAt) >= maxCredentialRetryDuration) {
      return true;
    }
    return false;
  }

  Future<void> _connect(
    KuaishouDanmakuArgs args,
    int generation,
  ) async {
    if (generation != _startGeneration) {
      return;
    }
    webScoketUtils?.close();
    webScoketUtils = WebScoketUtils(
      url: args.websocketUrls.first,
      backupUrls: args.websocketUrls.skip(1).toList(),
      heartBeatTime: heartbeatTime,
      headers: {
        "User-Agent": args.userAgent,
        "Origin": "https://live.kuaishou.com",
        "Referer": "https://live.kuaishou.com/u/${args.roomId}",
        if (args.cookie.isNotEmpty) "Cookie": args.cookie,
      },
      onMessage: decodeMessage,
      onReady: () {
        onReady?.call();
        joinRoom();
      },
      onHeartBeat: heartbeat,
      onReconnect: () {
        onClose?.call("与服务器断开连接，正在尝试重连");
      },
      onClose: (e) {
        onClose?.call("服务器连接失败$e");
      },
      connector: _connector,
      retryTimerFactory: _socketRetryTimerFactory,
    );
    await webScoketUtils?.connect();
  }

  @override
  Future stop() async {
    _startGeneration += 1;
    _credentialRetryTimer?.cancel();
    _credentialRetryTimer = null;
    _credentialResolver = null;
    _credentialRetryNotified = false;
    _credentialRetryAttempts = 0;
    _credentialRetryStartedAt = null;
    onMessage = null;
    onClose = null;
    onReady = null;
    webScoketUtils?.close();
    webScoketUtils = null;
    danmakuArgs = null;
  }

  void joinRoom() {
    final args = danmakuArgs;
    if (args == null) {
      return;
    }
    final payload = _KuaishouProtoWriter()
      ..writeString(1, args.token)
      ..writeString(2, args.liveStreamId)
      ..writeVarintField(3, 0)
      ..writeVarintField(4, 0)
      ..writeString(5, args.expTag)
      ..writeString(6, args.attach)
      ..writeString(7, args.pageId);
    webScoketUtils?.sendMessage(_encodeSocketMessage(200, payload.takeBytes()));
  }

  @override
  void heartbeat() {
    final payload = _KuaishouProtoWriter()
      ..writeVarintField(1, DateTime.now().millisecondsSinceEpoch);
    webScoketUtils?.sendMessage(_encodeSocketMessage(1, payload.takeBytes()));
  }

  void decodeMessage(dynamic data) {
    try {
      if (data is ByteBuffer) {
        data = data.asUint8List();
      }
      if (data is! List<int>) {
        return;
      }

      final socketMessage = _decodeSocketMessage(data);
      var payload = socketMessage.payload;
      if (payload.isEmpty) {
        return;
      }
      if (socketMessage.compressionType == 2) {
        payload = gzip.decode(payload);
      } else if (socketMessage.compressionType == 3) {
        payload = decryptAesPayload(payload);
      }

      switch (socketMessage.payloadType) {
        case 103:
          final error = _decodeError(payload);
          if (error.isNotEmpty) {
            onClose?.call(error);
          }
          break;
        case 310:
          _decodeFeedPush(payload);
          break;
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }

  static Uint8List decryptAesPayload(List<int> payload) {
    if (payload.isEmpty || payload.length % 16 != 0) {
      throw const FormatException(
        'Invalid Kuaishou AES payload block length',
      );
    }
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    )..init(
        false,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>,
            CipherParameters?>(
          ParametersWithIV<KeyParameter>(
            KeyParameter(Uint8List.fromList(utf8.encode(_kuaishouAesKey))),
            Uint8List.fromList(utf8.encode(_kuaishouAesIv)),
          ),
          null,
        ),
      );
    return cipher.process(Uint8List.fromList(payload));
  }

  Uint8List _encodeSocketMessage(int payloadType, List<int> payload) {
    final writer = _KuaishouProtoWriter()
      ..writeVarintField(1, payloadType)
      ..writeBytes(3, payload);
    return writer.takeBytes();
  }

  _KuaishouSocketMessage _decodeSocketMessage(List<int> data) {
    final reader = _KuaishouProtoReader(data);
    var payloadType = 0;
    var compressionType = 0;
    var payload = <int>[];
    reader.readFields((fieldNumber, wireType) {
      if (fieldNumber == 1 && wireType == 0) {
        payloadType = reader.readVarint();
      } else if (fieldNumber == 2 && wireType == 0) {
        compressionType = reader.readVarint();
      } else if (fieldNumber == 3 && wireType == 2) {
        payload = reader.readBytes();
      } else {
        reader.skip(wireType);
      }
    });
    return _KuaishouSocketMessage(
      payloadType: payloadType,
      compressionType: compressionType,
      payload: payload,
    );
  }

  String _decodeError(List<int> payload) {
    final reader = _KuaishouProtoReader(payload);
    var code = 0;
    var message = '';
    reader.readFields((fieldNumber, wireType) {
      if (fieldNumber == 1 && wireType == 0) {
        code = reader.readVarint();
      } else if (fieldNumber == 2 && wireType == 2) {
        message = reader.readString();
      } else {
        reader.skip(wireType);
      }
    });
    if (message.isEmpty && code == 0) {
      return '';
    }
    return message.isEmpty ? "快手弹幕错误：$code" : "快手弹幕错误：$message";
  }

  void _decodeFeedPush(List<int> payload) {
    final reader = _KuaishouProtoReader(payload);
    reader.readFields((fieldNumber, wireType) {
      if (fieldNumber == 5 && wireType == 2) {
        final message = _decodeCommentFeed(reader.readBytes());
        if (message != null) {
          onMessage?.call(message);
        }
      } else {
        reader.skip(wireType);
      }
    });
  }

  LiveMessage? _decodeCommentFeed(List<int> payload) {
    final reader = _KuaishouProtoReader(payload);
    var userName = '';
    var content = '';
    var color = LiveMessageColor.white;
    var hidden = false;

    reader.readFields((fieldNumber, wireType) {
      if (fieldNumber == 2 && wireType == 2) {
        userName = _decodeSimpleUserInfo(reader.readBytes());
      } else if (fieldNumber == 3 && wireType == 2) {
        content = reader.readString();
      } else if (fieldNumber == 6 && wireType == 2) {
        color = _parseColor(reader.readString());
      } else if (fieldNumber == 7 && wireType == 0) {
        hidden = reader.readVarint() == 2;
      } else {
        reader.skip(wireType);
      }
    });

    if (hidden || content.isEmpty) {
      return null;
    }

    // 上游可能把文本截断在表情 token 中间，先去掉尾部残片再切 spans，
    // 保证 message 与 spans 一致（列表与弹幕层显示相同内容）。
    final text = _stripTruncatedEmojiTail(content);
    if (text.isEmpty) {
      return null;
    }

    final spans = _buildEmojiSpans(text);
    final imageUrls = spans
        .where((item) => item.isImage)
        .map((item) => item.imageUrl!.trim())
        .toSet()
        .toList();

    return LiveMessage(
      type: LiveMessageType.chat,
      userName: userName,
      message: text,
      color: color,
      imageUrls: imageUrls.isEmpty ? null : imageUrls,
      spans: spans.isEmpty ? null : spans,
    );
  }

  /// 把弹幕文本中的 `[表情名]` token 转成图文混合片段；
  /// 未命中 [kuaishouEmojiAssets] 的方括号文本保持原样，避免误伤普通文本。
  static final RegExp _kuaishouEmojiPattern = RegExp(r'\[[^\[\]\r\n]{1,64}\]');
  static final Set<String> _reportedUnknownEmojiTokens = <String>{};

  /// 尾部截断残片：按字节切断时可能落在 UTF-8 序列中间，
  /// `utf8.decode(allowMalformed: true)` 会留下若干 U+FFFD。
  static final RegExp _trailingReplacementChars = RegExp('�+\$');

  /// 尾部截断残片的长度上限（不含 `[`），超过则视为普通文本不删。
  ///
  /// 两张词库 + 别名共 273 个 token，表情名长度分布为 1 字 ×25、2 字 ×156、
  /// 3 字 ×64、4 字 ×25、5 字 ×1、6 字 ×2，即实测最长 6 字：真正被截断的
  /// 残片一定很短。这个上限用来兜住误判的破坏力——没有它，
  /// `substring(0, open)` 会删掉长度不受限的尾巴，例如
  /// `主播这个操作[笑死我了哈哈哈哈哈` 会连着 `[` 一起丢掉 10 个字符。
  static const int _kMaxTruncatedEmojiResidue = 8;

  /// 去掉尾部被截断的表情 token 残片（如 `[奸笑][奸` 的 `[奸`）。
  ///
  /// 上游（服务端或发送方客户端）会在 token 中间截断文本，残片缺少 `]`
  /// 无法匹配 [_kuaishouEmojiPattern]，会原样渲染成 `[`、`[奸` 之类的乱码。
  /// 只要末尾存在未闭合的 `[`，且其后（去掉尾部 U+FFFD）不超过
  /// [_kMaxTruncatedEmojiResidue] 个字符，就无条件丢弃这段残片——不再校验
  /// 它是否为已知表情名的前缀，因为新上线、本地词库还没收录的表情永远过不了
  /// 前缀校验，残片会漏到界面上。
  ///
  /// 代价是明确接受误判：用户自己打出的、结尾带未闭合 `[` 的短文本
  /// （如 `你猜[`）也会被删掉。这是有意的取舍，破坏范围由上限兜住。
  static String _stripTruncatedEmojiTail(String content) {
    final open = content.lastIndexOf('[');
    if (open < 0 || content.indexOf(']', open) >= 0) {
      // 没有未闭合的 `[`，说明尾部不是被切断的 token。
      return content;
    }
    final residue = content
        .substring(open + 1)
        .replaceFirst(_trailingReplacementChars, '');
    if (residue.length > _kMaxTruncatedEmojiResidue) {
      return content;
    }
    return content.substring(0, open);
  }

  List<LiveMessageSpan> _buildEmojiSpans(String content) {
    final spans = <LiveMessageSpan>[];
    var start = 0;
    for (final match in _kuaishouEmojiPattern.allMatches(content)) {
      if (match.start > start) {
        spans.add(LiveMessageSpan.text(content.substring(start, match.start)));
      }
      final token = match.group(0)!;
      final url = resolveKuaishouEmoji(token);
      if (url != null) {
        spans.add(LiveMessageSpan.image(url, fallbackText: token));
      } else {
        spans.add(LiveMessageSpan.text(token));
        if (_reportedUnknownEmojiTokens.add(token)) {
          CoreLog.d('快手未映射表情 token: $token');
        }
      }
      start = match.end;
    }
    if (start < content.length) {
      spans.add(LiveMessageSpan.text(content.substring(start)));
    }
    return spans;
  }

  String _decodeSimpleUserInfo(List<int> payload) {
    final reader = _KuaishouProtoReader(payload);
    var userName = '';
    reader.readFields((fieldNumber, wireType) {
      if (fieldNumber == 2 && wireType == 2) {
        userName = reader.readString();
      } else {
        reader.skip(wireType);
      }
    });
    return userName;
  }

  LiveMessageColor _parseColor(String value) {
    final colorText = value.trim().replaceFirst('#', '');
    if (colorText.length == 6) {
      final colorValue = int.tryParse(colorText, radix: 16);
      if (colorValue != null) {
        return LiveMessageColor.numberToColor(colorValue);
      }
    }
    return LiveMessageColor.white;
  }
}

class _KuaishouSocketMessage {
  final int payloadType;
  final int compressionType;
  final List<int> payload;

  _KuaishouSocketMessage({
    required this.payloadType,
    required this.compressionType,
    required this.payload,
  });
}

class _KuaishouProtoWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void writeVarintField(int fieldNumber, int value) {
    _writeVarint((fieldNumber << 3) | 0);
    _writeVarint(value);
  }

  void writeString(int fieldNumber, String value) {
    if (value.isEmpty) {
      return;
    }
    writeBytes(fieldNumber, utf8.encode(value));
  }

  void writeBytes(int fieldNumber, List<int> value) {
    _writeVarint((fieldNumber << 3) | 2);
    _writeVarint(value.length);
    _builder.add(value);
  }

  void _writeVarint(int value) {
    var current = value;
    while (current >= 0x80) {
      _builder.addByte((current & 0x7f) | 0x80);
      current >>= 7;
    }
    _builder.addByte(current);
  }

  Uint8List takeBytes() => _builder.takeBytes();
}

class _KuaishouProtoReader {
  final List<int> _data;
  int _offset = 0;

  _KuaishouProtoReader(List<int> data) : _data = data;

  void readFields(void Function(int fieldNumber, int wireType) onField) {
    while (_offset < _data.length) {
      final tag = readVarint();
      if (tag == 0) {
        return;
      }
      onField(tag >> 3, tag & 0x07);
    }
  }

  int readVarint() {
    var shift = 0;
    var result = 0;
    while (_offset < _data.length) {
      final byte = _data[_offset++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return result;
      }
      shift += 7;
      if (shift > 63) {
        throw FormatException("Invalid protobuf varint");
      }
    }
    throw FormatException("Unexpected protobuf EOF");
  }

  List<int> readBytes() {
    final length = readVarint();
    final end = _offset + length;
    if (end > _data.length) {
      throw FormatException("Unexpected protobuf bytes EOF");
    }
    final result = _data.sublist(_offset, end);
    _offset = end;
    return result;
  }

  String readString() {
    return utf8.decode(readBytes(), allowMalformed: true);
  }

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
        break;
      case 1:
        _offset += 8;
        break;
      case 2:
        final length = readVarint();
        _offset += length;
        break;
      case 5:
        _offset += 4;
        break;
      default:
        throw FormatException("Unsupported protobuf wire type: $wireType");
    }
    if (_offset > _data.length) {
      throw FormatException("Unexpected protobuf skip EOF");
    }
  }
}
