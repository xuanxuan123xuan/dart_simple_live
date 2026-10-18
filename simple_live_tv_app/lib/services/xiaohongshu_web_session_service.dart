import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/sites.dart';

/// Android-only, serialized bridge for Xiaohongshu's read-only live APIs.
///
/// The hidden WebView signs JSON requests. Native video playback continues to
/// use the HLS/FLV URLs parsed from SSR and never uses this WebView.
class XiaohongshuWebSessionService extends GetxService
    implements XiaohongshuRequestBridge, XiaohongshuSessionLifecycle {
  XiaohongshuWebSessionService({
    XiaohongshuSite? site,
    bool Function()? platformSupported,
    this.requestTimeout = const Duration(seconds: 30),
  })  : _siteOverride = site,
        _platformSupported = platformSupported ?? (() => Platform.isAndroid);

  static XiaohongshuWebSessionService get instance => Get.find();
  static bool get isSupported => Platform.isAndroid;

  static const javascriptChannelName = 'XiaohongshuBridge';
  static const Set<String> _roomPaths = {
    XiaohongshuSite.roomInfoPath,
    XiaohongshuSite.statusPath,
    XiaohongshuSite.interactionPath,
    XiaohongshuSite.aggregatePath,
    XiaohongshuSite.stopInfoPath,
  };

  final XiaohongshuSite? _siteOverride;
  final bool Function() _platformSupported;
  final Duration requestTimeout;

  XiaohongshuSite get _site =>
      _siteOverride ??
      Sites.allSites[Constant.kXiaohongshu]!.liveSite as XiaohongshuSite;

  final pageUrl = RxnString();
  final revision = 0.obs;
  Future<void> Function(String script)? evaluate;

  Completer<void>? _ready;
  final _pending = <String, Completer<dynamic>>{};
  final _pendingRooms = <String, String>{};
  final _activeRooms = <String>{};
  final _roomEpoch = <String, int>{};
  final _transientRoomRefs = <String, int>{};
  Future<void> _queue = Future<void>.value();
  Future<void> _cookieChange = Future<void>.value();
  bool _closed = false;
  int _sequence = 0;
  int _transientRequests = 0;
  final _cancellations = <Completer<void>, String>{};
  int _requestGeneration = 0;

  void _invalidateRequests() {
    _requestGeneration++;
    for (final cancellation in _cancellations.keys.toList()) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    _cancellations.clear();
    _cancelAllRequests();
  }

  void hostDetached(int sessionRevision) {
    if (_closed || sessionRevision != revision.value) return;
    _invalidateRequests();
    evaluate = null;
    pageUrl.value = null;
    _ready = null;
    revision.value++;
  }

  @override
  void onInit() {
    _site.requestBridge = this;
    super.onInit();
  }

  static bool isAllowedNavigation(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme.toLowerCase() == 'https' &&
        uri.userInfo.isEmpty &&
        uri.port == 443 &&
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
          kind: status == 0 ? CoreErrorKind.network : CoreErrorKind.http,
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
    final normalized = XiaohongshuSite.normalizeRoomId(roomId);
    if (normalized == null) return;
    _roomEpoch[normalized] = (_roomEpoch[normalized] ?? 0) + 1;
    for (final entry in _cancellations.entries.toList()) {
      if (entry.value == normalized) {
        _cancellations.remove(entry.key);
        if (!entry.key.isCompleted) entry.key.complete();
      }
    }
    _activeRooms.remove(normalized);
    _cancelRoomRequests(normalized);
    await _closeRoomSessionIfUnused();
  }

  /// Clears only Cookie names that belonged to the replaced account.
  Future<void> cookieChanged(String previousCookie) async {
    _invalidateRequests();
    evaluate = null;
    pageUrl.value = null;
    if (_ready?.isCompleted == false) _ready!.complete();
    _ready = null;
    revision.value++;
    // Do not mount a replacement host until deletion has finished: otherwise
    // deleting an old name could delete the replacement Cookie of that name.
    final cleanup =
        _cookieChange.then((_) => _clearPlatformCookies(previousCookie));
    _cookieChange = cleanup;
    await cleanup;
  }

  Future<void> _clearPlatformCookies(String previousCookie) async {
    if (!_platformSupported()) return;
    try {
      final names = <String>{};
      for (final part in previousCookie.split(';')) {
        final separator = part.indexOf('=');
        if (separator > 0) names.add(part.substring(0, separator).trim());
      }
      for (final name in names) {
        await CookieManager.instance()
            .deleteCookie(
              url: WebUri(XiaohongshuSite.webBaseUrl),
              name: name,
              domain: '.xiaohongshu.com',
              path: '/',
            )
            .timeout(requestTimeout);
      }
    } catch (_) {
      // A missing platform plugin must not block SSR playback or Cookie save.
    }
  }

  Future<void> reset({bool invalidateRequests = true}) async {
    if (invalidateRequests) _invalidateRequests();
    evaluate = null;
    final previousReady = _ready;
    _ready = Completer<void>();
    revision.value++;
    if (previousReady?.isCompleted == false) previousReady!.complete();
    _cancelAllRequests();
  }

  @override
  Future<dynamic> request({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    dynamic body,
  }) {
    if (method != 'GET' || body != null || !_roomPaths.contains(path)) {
      return Future<dynamic>.error(
        CoreError('小红书会话仅允许已确认的只读请求', kind: CoreErrorKind.response),
      );
    }
    final roomId = XiaohongshuSite.normalizeRoomId('${query?['roomId'] ?? ''}');
    if (roomId == null) {
      return Future<dynamic>.error(CoreError('小红书房间号无效'));
    }
    if (_closed || !_platformSupported()) {
      return Future<dynamic>.error(CoreError('此设备未提供小红书网页签名能力'));
    }

    final isInteraction = path == XiaohongshuSite.interactionPath;
    if (isInteraction) {
      _activeRooms.add(roomId);
    } else {
      _transientRequests++;
      _transientRoomRefs.update(roomId, (count) => count + 1,
          ifAbsent: () => 1);
    }
    final epoch = _roomEpoch[roomId] ?? 0;
    final generation = _requestGeneration;
    final signal = Completer<void>();
    _cancellations[signal] = roomId;
    final cancellation =
        signal.future.then<dynamic>((_) => throw CoreCancelledError());
    cancellation.ignore();
    final task = _queue.then((_) async {
      await _cookieChange;
      if (_closed || !_platformSupported()) {
        throw CoreError('此设备未提供小红书网页签名能力');
      }
      _checkRoom(roomId, epoch);
      if (generation != _requestGeneration) throw CoreCancelledError();
      return _requestEmbedded(
          path, query ?? const {}, roomId, epoch, cancellation);
    }).whenComplete(() {
      _cancellations.remove(signal);
    });
    _queue = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    if (isInteraction) return Future.any<dynamic>([task, cancellation]);
    final released =
        task.whenComplete(() => _releaseTransientReference(roomId));
    return Future.any<dynamic>([released, cancellation]);
  }

  Future<dynamic> _requestEmbedded(
    String path,
    Map<String, dynamic> query,
    String roomId,
    int epoch,
    Future<dynamic> cancellation,
  ) async {
    final deadline = DateTime.now().add(requestTimeout);
    if (pageUrl.value == null || _ready == null) {
      evaluate = null;
      _ready = Completer<void>();
      pageUrl.value = '${XiaohongshuSite.webBaseUrl}/livestream/$roomId';
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final id = '${++_sequence}';
      final completer = Completer<dynamic>();
      try {
        await _within(
            Future.any<dynamic>([_ready!.future, cancellation]), deadline);
        _checkRoom(roomId, epoch);
        final run = evaluate;
        if (run == null) throw CoreError('此设备无法建立小红书网页会话');
        completer.future.ignore();
        _pending[id] = completer;
        _pendingRooms[id] = roomId;
        await _within(
          Future.any<dynamic>([
            run(buildRequestScript(id: id, path: path, query: query)),
            cancellation
          ]),
          deadline,
        );
        final result = await _within(
            Future.any<dynamic>([completer.future, cancellation]), deadline);
        _checkRoom(roomId, epoch);
        return result;
      } on CoreError catch (error) {
        if (attempt == 0 && error.statusCode == 406) {
          _checkRoom(roomId, epoch);
          await reset(invalidateRequests: false);
          continue;
        }
        rethrow;
      } on TimeoutException {
        throw CoreError('小红书网页会话超时', kind: CoreErrorKind.network);
      } finally {
        _pending.remove(id);
        _pendingRooms.remove(id);
      }
    }
    throw CoreError('小红书网页会话不可用');
  }

  Future<T> _within<T>(Future<T> work, DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) throw TimeoutException('session deadline');
    return work.timeout(remaining);
  }

  void _checkRoom(String roomId, int epoch) {
    if (_closed || (_roomEpoch[roomId] ?? 0) != epoch) {
      throw CoreCancelledError();
    }
  }

  void _releaseTransientReference(String roomId) {
    _transientRequests--;
    final count = _transientRoomRefs[roomId] ?? 0;
    if (count <= 1) {
      _transientRoomRefs.remove(roomId);
    } else {
      _transientRoomRefs[roomId] = count - 1;
    }
    _closeRoomSessionIfUnused().ignore();
  }

  Future<void> _closeRoomSessionIfUnused() async {
    if (_activeRooms.isNotEmpty || _transientRequests > 0) return;
    if (pageUrl.value != null) revision.value++;
    pageUrl.value = null;
    evaluate = null;
    if (_ready?.isCompleted == false) _ready!.complete();
    _ready = null;
  }

  void _cancelRoomRequests(String roomId) {
    final ids = _pendingRooms.entries
        .where((entry) => entry.value == roomId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in ids) {
      _pendingRooms.remove(id);
      final pending = _pending.remove(id);
      if (pending != null && !pending.isCompleted) {
        pending.completeError(CoreCancelledError());
      }
    }
  }

  void _cancelAllRequests() {
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(CoreCancelledError());
    }
    _pending.clear();
    _pendingRooms.clear();
  }

  static String buildRequestScript({
    required String id,
    required String path,
    required Map<String, dynamic> query,
  }) {
    final payload = jsonEncode({'id': id, 'path': path, 'query': query});
    return '''(async function() {
      const args = $payload;
      function send(value) {
        const message = JSON.stringify(value);
        if (window.chrome && window.chrome.webview && window.chrome.webview.postMessage) {
          window.chrome.webview.postMessage(message);
        } else if (window.webkit && window.webkit.messageHandlers &&
                   window.webkit.messageHandlers.XiaohongshuBridge) {
          window.webkit.messageHandlers.XiaohongshuBridge.postMessage(message);
        } else if (window.XiaohongshuBridge) {
          window.XiaohongshuBridge.postMessage(message);
        } else if (window.flutter_inappwebview) {
          window.flutter_inappwebview.callHandler('XiaohongshuBridge', message);
        }
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
          {method: 'GET', headers, credentials: 'include', redirect: 'error'});
        const data = await response.json();
        send({id: args.id, ok: response.ok, status: response.status, data});
      } catch (_) { send({id: args.id, ok: false, status: 0}); }
    })();''';
  }

  @override
  void onClose() {
    _closed = true;
    _invalidateRequests();
    pageUrl.value = null;
    evaluate = null;
    if (_ready?.isCompleted == false) _ready!.complete();
    _ready = null;
    _cancelAllRequests();
    _activeRooms.clear();
    _transientRoomRefs.clear();
    if (identical(_site.requestBridge, this)) _site.requestBridge = null;
    super.onClose();
  }
}
