import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'package:web_socket_channel/io.dart';

enum SignalRConnectionState {
  connecting,
  connected,
  disconnected,
}

class SignalRService {
  static const int kRoomIdLength = 6;
  static const String kDefaultUrl = "wss://june6699.top/sync";
  static const String kCloudflareUrl =
      "wss://simple-live-sync.3439394104.workers.dev/sync";
  static const String kDefaultLocalProxy = "127.0.0.1:51888";
  static const String kDirectProxyValue = "direct";

  static const List<SyncServerPreset> kServerPresets = [
    SyncServerPreset(
      label: "国内站点（推荐，可直连）",
      shortLabel: "国内站点",
      wsUrl: kDefaultUrl,
      note: "临时国内站点，无需代理即可使用",
    ),
    SyncServerPreset(
      label: "Cloudflare 站点（需代理）",
      shortLabel: "Cloudflare 站点",
      wsUrl: kCloudflareUrl,
      note: "workers.dev 域名，部分网络必须走代理才能连接",
    ),
  ];

  SignalRConnectionState state = SignalRConnectionState.connecting;

  final _stateStreamController =
      StreamController<SignalRConnectionState>.broadcast();
  Stream<SignalRConnectionState> get stateStream =>
      _stateStreamController.stream;

  final _onFavoriteStreamController =
      StreamController<RoomSyncPayload>.broadcast();
  Stream<RoomSyncPayload> get onFavoriteStream =>
      _onFavoriteStreamController.stream;

  final _onHistoryStreamController =
      StreamController<RoomSyncPayload>.broadcast();
  Stream<RoomSyncPayload> get onHistoryStream =>
      _onHistoryStreamController.stream;

  final _onShieldWordStreamController =
      StreamController<RoomSyncPayload>.broadcast();
  Stream<RoomSyncPayload> get onShieldWordStream =>
      _onShieldWordStreamController.stream;

  final _onBiliAccountStreamController =
      StreamController<RoomSyncPayload>.broadcast();
  Stream<RoomSyncPayload> get onBiliAccountStream =>
      _onBiliAccountStreamController.stream;

  final _onDouyinAccountStreamController =
      StreamController<RoomSyncPayload>.broadcast();
  Stream<RoomSyncPayload> get onDouyinAccountStream =>
      _onDouyinAccountStreamController.stream;

  final _onKuaishouAccountStreamController =
      StreamController<RoomSyncPayload>.broadcast();
  Stream<RoomSyncPayload> get onKuaishouAccountStream =>
      _onKuaishouAccountStreamController.stream;

  final _onRoomDestroyedStreamController = StreamController<String>.broadcast();
  Stream<String> get onRoomDestroyedStream =>
      _onRoomDestroyedStreamController.stream;

  final _onRoomUserUpdatedStreamController =
      StreamController<List<RoomUser>>.broadcast();
  Stream<List<RoomUser>> get onRoomUserUpdatedStream =>
      _onRoomUserUpdatedStreamController.stream;

  IOWebSocketChannel? _channel;
  HttpClient? _httpClient;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  int _requestId = 0;
  String _currentRoomId = "";
  final hubConnection = SignalRConnectionInfo();
  final Map<String, Completer<Resp<dynamic>>> _pendingRequests = {};

  static String get configuredUrl {
    final value = LocalStorageService.instance.getValue(
      LocalStorageService.kSyncServerUrl,
      "",
    );
    return value.trim().isEmpty ? kDefaultUrl : value.trim();
  }

  static Future<void> setConfiguredUrl(String value) {
    return LocalStorageService.instance.setValue(
      LocalStorageService.kSyncServerUrl,
      value.trim(),
    );
  }

  static String get configuredProxyUrl {
    return LocalStorageService.instance
        .getValue(LocalStorageService.kSyncProxyUrl, "")
        .trim();
  }

  static String get proxyDisplayName {
    final value = configuredProxyUrl;
    if (value.isEmpty) {
      return "自动检测 $kDefaultLocalProxy";
    }
    if (value.toLowerCase() == kDirectProxyValue) {
      return "直连";
    }
    return value;
  }

  static Future<void> setConfiguredProxyUrl(String value) {
    return LocalStorageService.instance.setValue(
      LocalStorageService.kSyncProxyUrl,
      value.trim(),
    );
  }

  static bool isValidProxyConfig(String value) {
    final text = value.trim();
    if (text.isEmpty || text.toLowerCase() == kDirectProxyValue) {
      return true;
    }
    return _normalizeProxyAddress(text) != null;
  }

  static SyncServerPreset? presetForUrl(String url) {
    final text = url.trim();
    for (final preset in kServerPresets) {
      if (preset.wsUrl == text) {
        return preset;
      }
    }
    return null;
  }

  /// 通过站点的 /health?format=json 探测连通性，自动按当前代理配置走。
  static Future<SyncServerProbeResult> probeServer(String wsUrl) async {
    final uri = Uri.tryParse(wsUrl.trim());
    if (uri == null ||
        !(uri.scheme == "wss" || uri.scheme == "ws") ||
        uri.host.isEmpty) {
      return const SyncServerProbeResult(false, 0, "地址无效");
    }
    final healthUrl = uri
        .replace(
          scheme: uri.scheme == "wss" ? "https" : "http",
        )
        .resolve("/health?format=json");
    final proxyAddress = await resolveProxyAddress();
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    if (proxyAddress != null) {
      client.findProxy = (_) => "PROXY $proxyAddress; DIRECT";
    }
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client
          .getUrl(healthUrl)
          .timeout(const Duration(seconds: 5));
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
      stopwatch.stop();
      if (response.statusCode >= 200 && response.statusCode < 400) {
        return SyncServerProbeResult(
          true,
          stopwatch.elapsedMilliseconds,
          proxyAddress == null ? "直连" : "经代理 $proxyAddress",
        );
      }
      return SyncServerProbeResult(
        false,
        stopwatch.elapsedMilliseconds,
        "HTTP ${response.statusCode}",
      );
    } catch (e) {
      stopwatch.stop();
      return SyncServerProbeResult(
        false,
        stopwatch.elapsedMilliseconds,
        _formatProbeError(e),
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _formatProbeError(Object error) {
    final text = error.toString();
    if (error is TimeoutException || text.contains("TimeoutException")) {
      return "连接超时";
    }
    if (text.contains("SocketException") || text.contains("HandshakeException")) {
      return "无法连接";
    }
    return text.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  }

  Future<void> connect() async {
    try {
      await disconnect();
      state = SignalRConnectionState.connecting;
      _stateStreamController.add(state);
      _httpClient = await _createWebSocketHttpClient();
      _channel = IOWebSocketChannel.connect(
        configuredUrl,
        pingInterval: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 15),
        customClient: _httpClient,
      );
      await _channel!.ready.timeout(const Duration(seconds: 15));
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
      );
      _startHeartbeat();
      state = SignalRConnectionState.connected;
      _stateStreamController.add(state);
    } catch (e) {
      Log.logPrint(e);
      await _cleanupSocket();
      _setDisconnected();
      throw Exception(_formatConnectionError(e));
    }
  }

  Future<void> disconnect() async {
    await _cleanupSocket();
    _setDisconnected();
  }

  Future<void> _cleanupSocket() async {
    _stopHeartbeat();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _httpClient?.close(force: true);
    _httpClient = null;
  }

  Future<Resp<String>> createRoom() async {
    final resp = await _sendRequest<String>(
      type: "createRoom",
      payload: _clientInfo(),
      successTypes: const {"roomCreated"},
      dataReader: (message) => message["roomId"]?.toString(),
    );
    if (resp.isSuccess && (resp.data?.isNotEmpty ?? false)) {
      _currentRoomId = resp.data!;
    }
    return resp;
  }

  Future<Resp> joinRoom(String roomId) async {
    final safeRoomId = roomId.trim().toUpperCase();
    final resp = await _sendRequest(
      type: "joinRoom",
      roomId: safeRoomId,
      payload: _clientInfo(),
      successTypes: const {"roomJoined"},
    );
    if (resp.isSuccess) {
      _currentRoomId = safeRoomId;
    }
    return resp;
  }

  Future<Resp> sendContent({
    required String roomName,
    required String action,
    required bool overlay,
    required String content,
    Map<String, Object?> extraPayload = const {},
  }) {
    return _sendRequest(
      type: _mapSendAction(action),
      roomId: roomName.trim().isEmpty ? _currentRoomId : roomName.trim(),
      payload: {
        "overlay": overlay,
        "content": content,
        if (action == "SendDouyinAccount") "accountType": "douyin",
        if (action == "SendKuaishouAccount") "accountType": "kuaishou",
        ...extraPayload,
      },
      successTypes: const {"ack"},
    );
  }

  void dispose() {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete(Resp(false, "连接已关闭", null));
      }
    }
    _pendingRequests.clear();
    _stateStreamController.close();
    _onFavoriteStreamController.close();
    _onHistoryStreamController.close();
    _onShieldWordStreamController.close();
    _onBiliAccountStreamController.close();
    _onDouyinAccountStreamController.close();
    _onKuaishouAccountStreamController.close();
    _onRoomDestroyedStreamController.close();
    _onRoomUserUpdatedStreamController.close();
    _stopHeartbeat();
    _subscription?.cancel();
    _channel?.sink.close();
  }

  Future<Resp<T>> _sendRequest<T>({
    required String type,
    String? roomId,
    Object? payload,
    required Set<String> successTypes,
    T? Function(Map<String, dynamic> message)? dataReader,
  }) async {
    if (state != SignalRConnectionState.connected || _channel == null) {
      throw Exception("not connected");
    }
    final requestId = (++_requestId).toString();
    final completer = Completer<Resp<dynamic>>();
    _pendingRequests[requestId] = completer;
    final message = <String, dynamic>{
      "type": type,
      "requestId": requestId,
      if (roomId != null && roomId.isNotEmpty) "roomId": roomId,
      if (payload != null) "payload": payload,
    };
    _channel!.sink.add(jsonEncode(message));
    final timer = Timer(const Duration(seconds: 15), () {
      final pending = _pendingRequests.remove(requestId);
      if (pending != null && !pending.isCompleted) {
        pending.complete(Resp(false, "同步服务响应超时", null));
      }
    });
    try {
      final resp = await completer.future;
      if (!resp.isSuccess) {
        return Resp<T>(false, resp.message, null);
      }
      final message = resp.data is Map<String, dynamic>
          ? resp.data as Map<String, dynamic>
          : <String, dynamic>{};
      if (!successTypes.contains(message["type"]?.toString())) {
        return Resp<T>(false, "同步服务返回异常：${message["type"]}", null);
      }
      return Resp<T>(
        true,
        "",
        dataReader == null ? null : dataReader(message),
      );
    } finally {
      timer.cancel();
      _pendingRequests.remove(requestId);
    }
  }

  void _handleMessage(dynamic raw) {
    try {
      if (raw is! String) {
        return;
      }
      final message = jsonDecode(raw);
      if (message is! Map) {
        return;
      }
      final data = Map<String, dynamic>.from(message);
      final type = data["type"]?.toString() ?? "";
      final requestId = data["requestId"]?.toString();
      if (requestId != null && requestId.isNotEmpty) {
        final pending = _pendingRequests.remove(requestId);
        if (pending != null && !pending.isCompleted) {
          if (type == "error") {
            pending.complete(Resp(false, _readErrorMessage(data), null));
          } else {
            pending.complete(Resp(true, "", data));
          }
          return;
        }
      }
      switch (type) {
        case "favoriteReceived":
          _emitBoolString(data, _onFavoriteStreamController);
          break;
        case "historyReceived":
          _emitBoolString(data, _onHistoryStreamController);
          break;
        case "shieldWordReceived":
          _emitBoolString(data, _onShieldWordStreamController);
          break;
        case "biliAccountReceived":
          _emitAccountPayload(data);
          break;
        case "douyinAccountReceived":
          _emitBoolString(data, _onDouyinAccountStreamController);
          break;
        case "kuaishouAccountReceived":
          _emitBoolString(data, _onKuaishouAccountStreamController);
          break;
        case "roomDestroyed":
          _onRoomDestroyedStreamController
              .add(data["reason"]?.toString() ?? "");
          break;
        case "userUpdated":
          final users = data["users"];
          final roomUsers = users is List
              ? users.map((e) => RoomUser.fromObject(e)).toList()
              : <RoomUser>[];
          for (final user in roomUsers) {
            if (user.isSelf) {
              hubConnection.connectionId = user.connectionId;
              break;
            }
          }
          _onRoomUserUpdatedStreamController.add(roomUsers);
          break;
      }
    } catch (e) {
      Log.logPrint(e);
    }
  }

  void _emitBoolString(
    Map<String, dynamic> message,
    StreamController<RoomSyncPayload> controller,
  ) {
    final payload = message["payload"];
    if (payload is! Map) {
      return;
    }
    controller.add(RoomSyncPayload.fromMap(Map<String, dynamic>.from(payload)));
  }

  void _emitAccountPayload(Map<String, dynamic> message) {
    final payload = message["payload"];
    var accountType = payload is Map
        ? payload["accountType"]?.toString().toLowerCase()
        : null;
    if (accountType == null || accountType.isEmpty) {
      final content = payload is Map ? payload["content"] : null;
      if (content is String) {
        try {
          final decoded = jsonDecode(content);
          if (decoded is Map) {
            accountType = decoded["accountType"]?.toString().toLowerCase();
          }
        } catch (_) {
          // The normal account handlers report malformed content.
        }
      }
    }
    final target = switch (accountType) {
      "douyin" => _onDouyinAccountStreamController,
      "kuaishou" => _onKuaishouAccountStreamController,
      _ => _onBiliAccountStreamController,
    };
    _emitBoolString(message, target);
  }

  void _handleSocketError(Object error, StackTrace stackTrace) {
    Log.logPrint(error);
    _completePendingWithError("同步服务连接失败：${_formatConnectionError(error)}");
    _setDisconnected();
  }

  void _handleSocketDone() {
    _completePendingWithError("同步服务连接已断开");
    _setDisconnected();
  }

  void _completePendingWithError(String message) {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete(Resp(false, message, null));
      }
    }
    _pendingRequests.clear();
  }

  void _setDisconnected() {
    _stopHeartbeat();
    state = SignalRConnectionState.disconnected;
    if (!_stateStreamController.isClosed) {
      _stateStreamController.add(state);
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (state == SignalRConnectionState.connected && _channel != null) {
        _channel!.sink.add(jsonEncode({
          "type": "ping",
          "requestId": "ping_${DateTime.now().millisecondsSinceEpoch}",
        }));
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<HttpClient?> _createWebSocketHttpClient() async {
    final proxyAddress = await resolveProxyAddress();
    if (proxyAddress == null) {
      return null;
    }
    Log.d("远程同步使用代理: $proxyAddress");
    final client = HttpClient();
    client.findProxy = (_) => "PROXY $proxyAddress; DIRECT";
    return client;
  }

  static Future<String?> resolveProxyAddress() async {
    final configured = configuredProxyUrl;
    if (configured.toLowerCase() == kDirectProxyValue) {
      return null;
    }
    if (configured.isNotEmpty) {
      return _normalizeProxyAddress(configured);
    }
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return null;
    }
    if (await _isTcpPortOpen("127.0.0.1", 51888)) {
      return kDefaultLocalProxy;
    }
    return null;
  }

  static String? _normalizeProxyAddress(String value) {
    var text = value.trim();
    if (text.isEmpty) {
      return null;
    }
    if (!text.contains("://")) {
      final parts = text.split(":");
      if (parts.length == 2 && int.tryParse(parts[1]) != null) {
        return text;
      }
      return null;
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !(uri.scheme == "http" || uri.scheme == "https") ||
        uri.host.isEmpty ||
        !uri.hasPort) {
      return null;
    }
    return "${uri.host}:${uri.port}";
  }

  static Future<bool> _isTcpPortOpen(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 400),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _clientInfo() => {
        "app": "Simple Live TV",
        "platform": "tv",
        "version": Utils.packageInfo.version,
      };

  String _mapSendAction(String action) {
    switch (action) {
      case "SendFavorite":
        return "sendFavorite";
      case "SendHistory":
        return "sendHistory";
      case "SendShieldWord":
        return "sendShieldWord";
      case "SendBiliAccount":
        return "sendBiliAccount";
      case "SendDouyinAccount":
      case "SendKuaishouAccount":
        return "sendBiliAccount";
      default:
        return action;
    }
  }

  String _readErrorMessage(Map<String, dynamic> message) {
    final error = message["error"];
    if (error is Map) {
      return error["message"]?.toString() ??
          error["code"]?.toString() ??
          "未知错误";
    }
    return error?.toString() ?? "未知错误";
  }

  String _formatConnectionError(Object error) {
    final text = error.toString();
    if (error is TimeoutException || text.contains("TimeoutException")) {
      return "同步服务连接超时，请检查网络或同步服务地址。"
          "可在同步设置中切换同步站点（国内站点 june6699.top 可直连，"
          "workers.dev 站点必须走代理）。"
          "如果本机代理可用，请确认同步代理地址为自动或 http://$kDefaultLocalProxy。"
          "注意 51888 只是作者的常用端口，连不上请查看代理软件的实际端口"
          "（如 v2rayN：参数设置 → 本地混合监控端口）。";
    }
    if (text.contains("SocketException")) {
      return "无法连接同步服务，请检查网络或同步服务地址";
    }
    return text.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  }
}

class SignalRConnectionInfo {
  String? connectionId;
}

class SyncServerPreset {
  final String label;
  final String shortLabel;
  final String wsUrl;
  final String note;

  const SyncServerPreset({
    required this.label,
    required this.shortLabel,
    required this.wsUrl,
    required this.note,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SyncServerPreset && other.wsUrl == wsUrl);

  @override
  int get hashCode => wsUrl.hashCode;
}

class SyncServerProbeResult {
  final bool ok;
  final int latencyMs;
  final String detail;

  const SyncServerProbeResult(this.ok, this.latencyMs, this.detail);
}

class Resp<T> {
  final bool isSuccess;
  final String message;
  final T? data;
  Resp(this.isSuccess, this.message, this.data);
}

class RoomSyncPayload {
  final bool overlay;
  final String content;
  final String accountType;
  final int chunkIndex;
  final int chunkTotal;
  final int itemStart;
  final int itemEnd;
  final int itemTotal;

  const RoomSyncPayload({
    required this.overlay,
    required this.content,
    this.accountType = "",
    this.chunkIndex = 1,
    this.chunkTotal = 1,
    this.itemStart = 0,
    this.itemEnd = 0,
    this.itemTotal = 0,
  });

  factory RoomSyncPayload.fromMap(Map<String, dynamic> payload) {
    var accountType = payload["accountType"]?.toString().toLowerCase() ?? "";
    if (accountType.isEmpty) {
      final content = payload["content"];
      if (content is String) {
        try {
          final decoded = jsonDecode(content);
          if (decoded is Map) {
            accountType = decoded["accountType"]?.toString().toLowerCase() ?? "";
          }
        } catch (_) {}
      }
    }
    return RoomSyncPayload(
      overlay: payload["overlay"] == true,
      content: payload["content"]?.toString() ?? "",
      accountType: accountType,
      chunkIndex: _readInt(payload["chunkIndex"], fallback: 1),
      chunkTotal: _readInt(payload["chunkTotal"], fallback: 1),
      itemStart: _readInt(payload["itemStart"], fallback: 0),
      itemEnd: _readInt(payload["itemEnd"], fallback: 0),
      itemTotal: _readInt(payload["itemTotal"], fallback: 0),
    );
  }

  bool get isLastChunk => chunkIndex >= chunkTotal;

  static int _readInt(dynamic value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? "") ?? fallback;
  }
}

class RoomUser {
  final String connectionId;
  final String shortId;
  final String platform;
  final String version;
  final String app;
  final bool? isCreator;
  final bool isSelf;

  RoomUser({
    required this.connectionId,
    required this.shortId,
    required this.platform,
    required this.version,
    required this.app,
    this.isCreator = false,
    this.isSelf = false,
  });

  factory RoomUser.fromJson(Map<String, dynamic> json) {
    return RoomUser(
      connectionId: json['connectionId']?.toString() ?? "",
      shortId: json['shortId']?.toString() ?? "",
      platform: json['platform']?.toString() ?? "",
      version: json['version']?.toString() ?? "",
      app: json['app']?.toString() ?? "",
      isCreator: json['isCreator'] == true,
      isSelf: json['isSelf'] == true,
    );
  }

  factory RoomUser.fromObject(Object? obj) {
    if (obj is Map) {
      return RoomUser.fromJson(Map<String, dynamic>.from(obj));
    }
    return RoomUser(
      connectionId: "",
      shortId: "",
      platform: "",
      version: "",
      app: "",
    );
  }
}
