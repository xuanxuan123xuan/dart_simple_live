import 'dart:async';
import 'dart:math';

import 'package:web_socket_channel/io.dart';

enum SocketStatus { connected, failed, closed }

abstract interface class WebSocketConnection {
  Future<void> get ready;
  Stream<dynamic> get stream;
  void add(dynamic message);
  Future<void> close();
}

typedef WebSocketConnector = FutureOr<WebSocketConnection> Function(
  String url,
  Map<String, dynamic>? headers,
);
typedef WebSocketRetryTimerFactory = Timer Function(
  Duration delay,
  void Function() callback,
);

class _IoWebSocketConnection implements WebSocketConnection {
  final IOWebSocketChannel channel;

  _IoWebSocketConnection(this.channel);

  @override
  Future<void> get ready => channel.ready;

  @override
  Stream<dynamic> get stream => channel.stream;

  @override
  void add(dynamic message) => channel.sink.add(message);

  @override
  Future<void> close() async {
    await channel.sink.close();
  }
}

class WebScoketUtils {
  SocketStatus status = SocketStatus.closed;

  /// 链接
  final String url;

  /// 备用链接
  final String? backupUrl;

  /// 备用链接列表
  final List<String> backupUrls;

  /// 心跳时间
  final int heartBeatTime;

  /// 接收到信息
  final Function(dynamic)? onMessage;

  /// 连接关闭
  final Function(String msg)? onClose;

  /// 尝试重连
  final Function()? onReconnect;

  /// 准备就绪
  final Function()? onReady;

  /// 心跳
  final Function()? onHeartBeat;

  /// 请求头
  Map<String, dynamic>? headers;

  final WebSocketConnector _connector;
  final WebSocketRetryTimerFactory _retryTimerFactory;

  /// 单个候选地址的连接超时时间。
  final Duration connectTimeout;

  /// 是否随机化候选地址顺序。
  final bool shuffleUrls;

  /// 每轮最多尝试的候选地址数量，null 表示全部尝试。
  final int? maxConnectAttempts;

  /// 连接断开后的重连间隔。
  final Duration reconnectDelay;

  WebScoketUtils({
    required this.url,
    required this.heartBeatTime,
    this.onMessage,
    this.onClose,
    this.onReconnect,
    this.onReady,
    this.onHeartBeat,
    this.headers,
    this.backupUrl,
    this.backupUrls = const [],
    WebSocketConnector? connector,
    WebSocketRetryTimerFactory? retryTimerFactory,
    this.connectTimeout = const Duration(seconds: 10),
    this.shuffleUrls = false,
    this.maxConnectAttempts,
    this.reconnectDelay = const Duration(seconds: 5),
    this.maxReconnectTime = 5,
  })  : _connector = connector ??
            ((url, headers) => _IoWebSocketConnection(
                  IOWebSocketChannel.connect(
                    url,
                    connectTimeout: connectTimeout,
                    headers: headers,
                  ),
                )),
        _retryTimerFactory = retryTimerFactory ?? _defaultRetryTimer;

  WebSocketConnection? webSocket;
  Timer? heartBeatTimer;

  /// 重连次数
  int reconnectTime = 0;
  Timer? reconnectTimer;

  /// 最大重连次数
  int maxReconnectTime;

  StreamSubscription<dynamic>? streamSubscription;
  bool _manuallyClosed = true;
  bool _disconnectHandled = false;
  int _nextUrlIndex = 0;
  int _connectionGeneration = 0;
  List<String> _activeConnectUrls = const [];

  static Timer _defaultRetryTimer(
    Duration delay,
    void Function() callback,
  ) {
    return Timer(delay, callback);
  }

  List<String> get _connectUrls {
    final urls = <String>[url];
    if (backupUrl != null && backupUrl!.isNotEmpty) {
      urls.add(backupUrl!);
    }
    urls.addAll(backupUrls.where((item) => item.isNotEmpty));
    return urls.toSet().toList();
  }

  /// Exposes the de-duplicated candidate order for diagnostics and tests.
  List<String> get connectUrls => List.unmodifiable(_connectUrls);

  Future<void> connect({bool retry = false}) async {
    if (!retry) {
      _manuallyClosed = false;
      reconnectTime = 0;
      _nextUrlIndex = 0;
      _activeConnectUrls = _buildConnectAttemptUrls();
      reconnectTimer?.cancel();
      reconnectTimer = null;
    }
    await _teardownConnection();
    if (_manuallyClosed) {
      return;
    }
    await _connectNextUrl();
  }

  Future<void> _connectNextUrl() async {
    final urls = _activeConnectUrls.isEmpty
        ? _buildConnectAttemptUrls()
        : _activeConnectUrls;
    if (urls.isEmpty || _manuallyClosed) {
      return;
    }
    final wsurl = urls[_nextUrlIndex % urls.length];
    _nextUrlIndex += 1;
    final generation = ++_connectionGeneration;
    _disconnectHandled = false;
    try {
      final connection = await Future<WebSocketConnection>.value(
        _connector(wsurl, headers),
      );
      if (_manuallyClosed || generation != _connectionGeneration) {
        await connection.close();
        return;
      }
      webSocket = connection;
      await connection.ready;
      if (_manuallyClosed || generation != _connectionGeneration) {
        await connection.close();
        return;
      }
      _ready(generation);
    } catch (error, stackTrace) {
      await _handleDisconnect(
        error,
        stackTrace,
        generation: generation,
      );
    }
  }

  List<String> _buildConnectAttemptUrls() {
    final urls = _connectUrls.toList();
    if (shuffleUrls) {
      urls.shuffle(Random());
    }
    return maxConnectAttempts == null
        ? urls
        : urls.take(maxConnectAttempts!).toList();
  }

  void _ready(int generation) {
    status = SocketStatus.connected;
    streamSubscription = webSocket?.stream.listen(
      receiveMessage,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(
          _handleDisconnect(
            error,
            stackTrace,
            generation: generation,
          ),
        );
      },
      onDone: () {
        unawaited(
          _handleDisconnect(
            'WebSocket connection closed',
            StackTrace.current,
            generation: generation,
            notifyError: false,
          ),
        );
      },
      cancelOnError: true,
    );
    onReady?.call();
    initHeartBeat();
  }

  void initHeartBeat() {
    heartBeatTimer?.cancel();
    if (heartBeatTime <= 0) {
      return;
    }
    heartBeatTimer = Timer.periodic(
      Duration(milliseconds: heartBeatTime),
      (_) => onHeartBeat?.call(),
    );
  }

  void receiveMessage(dynamic data) {
    reconnectTime = 0;
    _nextUrlIndex = 0;
    onMessage?.call(data);
  }

  Future<void> _handleDisconnect(
    Object error,
    StackTrace? stackTrace, {
    required int generation,
    bool notifyError = true,
  }) async {
    if (_manuallyClosed ||
        generation != _connectionGeneration ||
        _disconnectHandled) {
      return;
    }
    _disconnectHandled = true;
    status = SocketStatus.failed;
    if (notifyError) {
      onClose?.call(error.toString());
    }
    await _teardownConnection(invalidateGeneration: false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manuallyClosed || reconnectTimer != null) {
      return;
    }
    if (reconnectTime >= maxReconnectTime) {
      status = SocketStatus.closed;
      onClose?.call("重连超过最大次数，与服务器断开连接");
      return;
    }
    reconnectTime += 1;
    onReconnect?.call();
    reconnectTimer = _retryTimerFactory(reconnectDelay, () {
      reconnectTimer = null;
      if (_manuallyClosed) {
        return;
      }
      unawaited(_connectNextUrl());
    });
  }

  void onError(Object error, StackTrace? stackTrace) {
    unawaited(
      _handleDisconnect(
        error,
        stackTrace,
        generation: _connectionGeneration,
      ),
    );
  }

  void onDone() {
    unawaited(
      _handleDisconnect(
        'WebSocket connection closed',
        StackTrace.current,
        generation: _connectionGeneration,
        notifyError: false,
      ),
    );
  }

  void sendMessage(dynamic message) {
    if (status == SocketStatus.connected) {
      webSocket?.add(message);
    }
  }

  void close() {
    _manuallyClosed = true;
    status = SocketStatus.closed;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    reconnectTime = 0;
    _connectionGeneration += 1;
    unawaited(_teardownConnection(invalidateGeneration: false));
  }

  Future<void> _teardownConnection({bool invalidateGeneration = true}) async {
    if (invalidateGeneration) {
      _connectionGeneration += 1;
    }
    heartBeatTimer?.cancel();
    heartBeatTimer = null;
    final subscription = streamSubscription;
    streamSubscription = null;
    await subscription?.cancel();
    final connection = webSocket;
    webSocket = null;
    try {
      await connection?.close();
    } catch (_) {}
  }

  void reconnect() {
    if (_manuallyClosed) {
      return;
    }
    _scheduleReconnect();
  }
}
