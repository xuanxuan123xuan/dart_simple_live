import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:simple_live_app/app/utils.dart';

import 'package:get/get.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_flutter/webview_flutter.dart' as ohos;
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// A single, serialized browser session. The widget owns platform controllers;
/// this service owns request deadlines and never logs cookies or response JSON.
class XiaohongshuWebSessionService extends GetxService
    implements XiaohongshuRequestBridge, XiaohongshuSessionLifecycle {
  XiaohongshuWebSessionService(
      {bool Function()? platformSupported,
      this.requestTimeout = const Duration(seconds: 30)})
      : _platformSupported = platformSupported ?? (() => isSupported);
  final bool Function() _platformSupported;
  final Duration requestTimeout;

  static XiaohongshuWebSessionService get instance => Get.find();
  static bool get isSupported =>
      Utils.isOhos || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  final pageUrl = RxnString();
  final revision = 0.obs;
  Future<void> Function(String script)? evaluate;
  Completer<void>? _ready;
  final _pending = <String, Completer<dynamic>>{};
  final _pendingRooms = <String, String>{};
  final _activeRooms = <String>{};
  Future<void> _queue = Future.value();
  bool _closed = false;
  int _sequence = 0;
  final _roomEpoch = <String, int>{};

  @override
  void onInit() {
    (Sites.allSites[Constant.kXiaohongshu]!.liveSite as XiaohongshuSite)
        .requestBridge = this;
    super.onInit();
  }

  static bool isAllowedNavigation(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        (uri.port == 443) &&
        const {
          'www.xiaohongshu.com',
          'xiaohongshu.com',
          'live-room.xiaohongshu.com',
        }.contains(uri.host.toLowerCase());
  }

  void loaded({String? url, int? sessionRevision}) {
    if ((url != null && url != pageUrl.value) ||
        (sessionRevision != null && sessionRevision != revision.value)) {
      return;
    }
    if (_ready?.isCompleted == false) _ready!.complete();
  }

  void receive(dynamic payload) {
    try {
      final data = payload is String ? jsonDecode(payload) : payload;
      if (data is! Map) return;
      final id = data['id']?.toString();
      final pending = _pending.remove(id);
      _pendingRooms.remove(id);
      if (pending == null || pending.isCompleted) return;
      final status = int.tryParse('${data['status']}') ?? 0;
      if (data['ok'] != true) {
        pending.completeError(CoreError(
          status == 406 ? '小红书网页签名已失效' : '小红书网页请求不可用',
          statusCode: status,
          kind: CoreErrorKind.http,
        ));
      } else {
        pending.complete(data['data']);
      }
    } catch (_) {
      // Malformed page messages cannot complete another request.
    }
  }

  @override
  Future<void> releaseRoom(String roomId) async {
    _roomEpoch[roomId] = (_roomEpoch[roomId] ?? 0) + 1;
    _activeRooms.remove(roomId);
    final ids =
        _pendingRooms.keys.where((id) => _pendingRooms[id] == roomId).toList();
    for (final id in ids) {
      _pendingRooms.remove(id);
      final pending = _pending.remove(id);
      if (pending != null && !pending.isCompleted) {
        pending.completeError(CoreCancelledError());
      }
    }
    if (_activeRooms.isEmpty) {
      pageUrl.value = null;
      evaluate = null;
      if (_ready?.isCompleted == false) _ready!.complete();
      _ready = null;
    }
  }

  Future<void> cookieChanged(String previousCookie) async {
    if (!isSupported) return;
    try {
      // Only overwrite cookies previously injected by this account; never clear
      // the shared browser jar used by the other platforms.
      for (final part in previousCookie.split(';')) {
        final separator = part.indexOf('=');
        if (separator <= 0) continue;
        final name = part.substring(0, separator).trim();
        if (Utils.isOhos) {
          await ohos.WebViewCookieManager().setCookie(ohos.WebViewCookie(
              name: name, value: '', domain: '.xiaohongshu.com', path: '/'));
        } else {
          await CookieManager.instance().deleteCookie(
              url: WebUri(XiaohongshuSite.webBaseUrl),
              name: name,
              domain: '.xiaohongshu.com',
              path: '/');
        }
      }
    } catch (_) {}
    if (pageUrl.value != null) await reset();
  }

  Future<void> reset() async {
    evaluate = null;
    _ready = Completer<void>();
    revision.value++;
  }

  @override
  Future<dynamic> request(
      {required String method,
      required String path,
      Map<String, dynamic>? query,
      dynamic body}) {
    final roomId = '${query?['roomId'] ?? ''}';
    final epoch = _roomEpoch[roomId] ?? 0;
    final task = _queue.then((_) {
      if ((_roomEpoch[roomId] ?? 0) != epoch) throw CoreCancelledError();
      return _request(method, path, query, body);
    });
    _queue = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  Future<dynamic> _request(String method, String path,
      Map<String, dynamic>? query, dynamic body) async {
    if (_closed) throw CoreCancelledError();
    if (!_platformSupported()) throw CoreError('此设备未提供小红书网页签名能力');
    const paths = {
      XiaohongshuSite.roomInfoPath,
      XiaohongshuSite.statusPath,
      XiaohongshuSite.interactionPath,
      XiaohongshuSite.aggregatePath,
      XiaohongshuSite.stopInfoPath,
    };
    if (method != 'GET' || body != null || !paths.contains(path)) {
      throw CoreError('小红书会话仅允许已确认的只读请求', kind: CoreErrorKind.response);
    }
    final roomId = XiaohongshuSite.normalizeRoomId('${query?['roomId'] ?? ''}');
    if (roomId == null) throw CoreError('小红书房间号无效');
    final url = '${XiaohongshuSite.webBaseUrl}/livestream/$roomId';
    _activeRooms.add(roomId);
    // Signing covers the request URL; one same-origin page can serve every
    // open room without reloading the browser for each polling tick.
    if (pageUrl.value == null || _ready == null) {
      evaluate = null;
      _ready = Completer<void>();
      pageUrl.value = url;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final id = '${++_sequence}';
      final completer = Completer<dynamic>();
      try {
        await _ready!.future.timeout(requestTimeout);
        final run = evaluate;
        if (run == null) throw CoreError('此设备无法建立小红书网页会话');
        completer.future.ignore();
        _pending[id] = completer;
        _pendingRooms[id] = roomId;
        await run(buildRequestScript(id: id, path: path, query: query ?? {}));
        return await completer.future.timeout(requestTimeout);
      } on CoreError catch (error) {
        if (attempt == 0 && error.statusCode == 406) {
          await reset();
          continue;
        }
        await releaseRoom(roomId);
        rethrow;
      } on TimeoutException {
        await releaseRoom(roomId);
        throw CoreError('小红书网页会话超时', kind: CoreErrorKind.network);
      } finally {
        _pending.remove(id);
        _pendingRooms.remove(id);
      }
    }
    throw CoreError('小红书网页会话不可用');
  }

  static String buildRequestScript(
      {required String id,
      required String path,
      required Map<String, dynamic> query}) {
    final payload = jsonEncode({'id': id, 'path': path, 'query': query});
    return '''(async function() {
      const args = $payload;
      function send(value) {
        const message = JSON.stringify(value);
        if (window.XiaohongshuBridge) window.XiaohongshuBridge.postMessage(message);
        else if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('XiaohongshuBridge', message);
      }
      try {
        for (let i = 0; i < 100 && typeof window.sign !== 'function'; i++) {
          await new Promise(resolve => setTimeout(resolve, 100));
        }
        if (typeof window.sign !== 'function') {
          send({id: args.id, ok: false, status: 406}); return;
        }
        const query = new URLSearchParams(args.query).toString();
        const path = args.path + (query ? '?' + query : '');
        const headers = Object.assign({}, window.sign(path, undefined) || {},
          typeof window.f === 'function' ? window.f() : {});
        const response = await fetch('https://live-room.xiaohongshu.com' + path,
          {method: 'GET', headers, credentials: 'include'});
        const data = await response.json();
        send({id: args.id, ok: response.ok && data.success !== false,
          status: response.status, data});
      } catch (_) { send({id: args.id, ok: false, status: 0}); }
    })();''';
  }

  @override
  void onClose() {
    _closed = true;
    pageUrl.value = null;
    evaluate = null;
    if (_ready?.isCompleted == false) _ready!.complete();
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(CoreError('小红书会话已关闭'));
    }
    _pending.clear();
    _pendingRooms.clear();
    _activeRooms.clear();
    super.onClose();
  }
}
