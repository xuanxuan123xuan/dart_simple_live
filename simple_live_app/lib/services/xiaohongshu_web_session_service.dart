import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_flutter/webview_flutter.dart' as ohos;
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/xiaohongshu_desktop_web_session_host.dart';
import 'package:simple_live_app/services/xiaohongshu_desktop_webview_window_host.dart';
import 'package:simple_live_app/services/xiaohongshu_host_id.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// A serialized browser session for Xiaohongshu's read-only web APIs.
///
/// The H5 live-room signer has a room-scoped lifetime. Desktop PC profile
/// lookups use a separate, short-lived WebView because the PC site exposes its
/// signer on a different origin and profile page. Cookies and response bodies
/// are never written to logs.
class XiaohongshuWebSessionService extends GetxService
    implements
        XiaohongshuRequestBridge,
        XiaohongshuHostRequestBridge,
        XiaohongshuSessionLifecycle {
  XiaohongshuWebSessionService({
    bool Function()? platformSupported,
    bool? desktopEnabled,
    XiaohongshuDesktopWebSessionFactory? desktopFactory,
    String Function()? cookieProvider,
    this.requestTimeout = const Duration(seconds: 30),
  })  : _platformSupported = platformSupported ?? (() => isSupported),
        _desktopFactory = desktopFactory ?? _defaultDesktopFactory,
        _desktopEnabled = desktopEnabled ?? _isDesktopPlatform,
        _cookieProvider = cookieProvider ?? _siteCookie;

  final bool Function() _platformSupported;
  final XiaohongshuDesktopWebSessionFactory? _desktopFactory;
  final bool _desktopEnabled;
  final String Function() _cookieProvider;
  final Duration requestTimeout;

  static const javascriptChannelName = 'XiaohongshuBridge';
  static const pcProfileUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/141.0.0.0 Safari/537.36';
  static String userAgentFor({required bool profile}) =>
      profile ? pcProfileUserAgent : XiaohongshuSite.defaultUserAgent;
  static XiaohongshuWebSessionService get instance => Get.find();
  static bool get isSupported =>
      Utils.isOhos ||
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      _isDesktopPlatform;
  static bool get usesNativeDesktopHost => _isDesktopPlatform;
  static bool get _isDesktopPlatform => Platform.isWindows || Platform.isLinux;
  static XiaohongshuDesktopWebSessionFactory? get _defaultDesktopFactory =>
      _isDesktopPlatform
          ? const XiaohongshuDesktopWebviewWindowFactory()
          : null;

  static String _siteCookie() =>
      (Sites.allSites[Constant.kXiaohongshu]!.liveSite as XiaohongshuSite)
          .cookie;

  final pageUrl = RxnString();
  final revision = 0.obs;
  Future<void> Function(String script)? evaluate;
  Completer<void>? _ready;
  final profilePageUrl = RxnString();
  final profileRevision = 0.obs;
  Future<void> Function(String script)? evaluateProfile;
  Completer<void>? _profileReady;
  String? _profileRoomId;
  final _pending = <String, Completer<dynamic>>{};
  final _pendingRooms = <String, String>{};
  final _pendingKinds = <String, String>{};
  final _activeRooms = <String>{};
  final _transientRoomRefs = <String, int>{};
  final _profileSessions = <XiaohongshuDesktopWebSession>{};
  Future<void> _queue = Future.value();
  Future<void> _hostQueue = Future.value();
  Future<XiaohongshuDesktopWebSession>? _desktopRoomCreation;
  XiaohongshuDesktopWebSession? _desktopRoomSession;
  bool _closed = false;
  int _sequence = 0;
  int _transientRequests = 0;
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

  void loadedProfile({String? url, int? sessionRevision}) {
    if ((url != null && url != profilePageUrl.value) ||
        (sessionRevision != null && sessionRevision != profileRevision.value)) {
      return;
    }
    if (_profileReady?.isCompleted == false) _profileReady!.complete();
  }

  void receive(dynamic payload) => _receive(payload, 'room');

  void receiveProfile(dynamic payload) => _receive(payload, 'profile');

  void _receive(dynamic payload, String kind) {
    try {
      final data = payload is String ? jsonDecode(payload) : payload;
      if (data is! Map) return;
      final id = data['id']?.toString();
      if (_pendingKinds[id] != kind) return;
      final pending = _pending.remove(id);
      _pendingRooms.remove(id);
      _pendingKinds.remove(id);
      if (pending == null || pending.isCompleted) return;
      final status = int.tryParse('${data['status']}') ?? 0;
      if (data['ok'] != true) {
        pending.completeError(CoreError(
          status == 406 ? '小红书网页签名已失效' : '小红书网页请求不可用',
          statusCode: status,
          kind: status == 0 ? CoreErrorKind.network : CoreErrorKind.http,
        ));
      } else {
        // HTTP success and the API's business success are separate. Return the
        // raw body so core can handle logged-out code=-101 and other app codes.
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
      _pendingKinds.remove(id);
      if (pending != null && !pending.isCompleted) {
        pending.completeError(CoreCancelledError());
      }
    }
    if (_profileRoomId == roomId) _closeProfileContext();
    await _closeRoomSessionIfUnused();
  }

  Future<void> cookieChanged(String previousCookie) async {
    if (!isSupported) return;
    if (_desktopEnabled && _desktopFactory != null) {
      // Desktop contexts have private per-window jars. Closing them removes
      // only Xiaohongshu session state owned by this service.
      await reset();
      final profiles = _profileSessions.toList();
      _profileSessions.clear();
      await Future.wait(profiles.map((session) => session.close()));
      return;
    }
    try {
      // Mobile and OHOS preserve their existing WebView cookie integration.
      // Only overwrite cookies previously injected by this account.
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
    _closeProfileContext();
  }

  Future<void> reset() async {
    evaluate = null;
    _ready = Completer<void>();
    revision.value++;
    final roomSession = _desktopRoomSession;
    _desktopRoomSession = null;
    _desktopRoomCreation = null;
    if (roomSession != null) await roomSession.close();
  }

  void _closeProfileContext() {
    evaluateProfile = null;
    profilePageUrl.value = null;
    profileRevision.value++;
    if (_profileReady?.isCompleted == false) _profileReady!.complete();
    _profileReady = null;
    _profileRoomId = null;
  }

  @override
  Future<dynamic> request({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    dynamic body,
  }) {
    final roomId = XiaohongshuSite.normalizeRoomId('${query?['roomId'] ?? ''}');
    final knownPath = _roomPaths.contains(path);
    final eligible =
        method == 'GET' && body == null && knownPath && roomId != null;
    final isInteraction = eligible && path == XiaohongshuSite.interactionPath;
    if (eligible) {
      if (isInteraction) {
        _activeRooms.add(roomId);
      } else {
        _transientRequests++;
        _transientRoomRefs.update(roomId, (count) => count + 1,
            ifAbsent: () => 1);
      }
    }

    final epoch = roomId == null ? 0 : (_roomEpoch[roomId] ?? 0);
    final task = _queue.then((_) {
      if (_closed) throw CoreCancelledError();
      if (roomId != null && (_roomEpoch[roomId] ?? 0) != epoch) {
        throw CoreCancelledError();
      }
      return _request(method, path, query, body, epoch);
    });
    _queue = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    if (!eligible || isInteraction) return task;
    return task.whenComplete(() => _releaseTransientReference(roomId));
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
    pageUrl.value = null;
    evaluate = null;
    if (_ready?.isCompleted == false) _ready!.complete();
    _ready = null;
    final session = _desktopRoomSession;
    _desktopRoomSession = null;
    _desktopRoomCreation = null;
    if (session != null) await session.close();
  }

  Future<dynamic> _request(String method, String path,
      Map<String, dynamic>? query, dynamic body, int epoch) async {
    if (_closed) throw CoreCancelledError();
    if (!_platformSupported()) throw CoreError('此设备未提供小红书网页签名能力');
    if (method != 'GET' || body != null || !_roomPaths.contains(path)) {
      throw CoreError('小红书会话仅允许已确认的只读请求', kind: CoreErrorKind.response);
    }
    final roomId = XiaohongshuSite.normalizeRoomId('${query?['roomId'] ?? ''}');
    if (roomId == null) throw CoreError('小红书房间号无效');
    final url = '${XiaohongshuSite.webBaseUrl}/livestream/$roomId';
    if (_desktopEnabled && _desktopFactory != null) {
      return _requestDesktopRoom(path, query ?? {}, url, roomId, epoch);
    }
    return _requestEmbeddedRoom(path, query ?? {}, url, roomId, epoch);
  }

  Future<dynamic> _requestEmbeddedRoom(String path, Map<String, dynamic> query,
      String url, String roomId, int epoch) async {
    final deadline = DateTime.now().add(requestTimeout);
    if (pageUrl.value == null || _ready == null) {
      evaluate = null;
      _ready = Completer<void>();
      pageUrl.value = url;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final id = '${++_sequence}';
      final completer = Completer<dynamic>();
      try {
        await _within(_ready!.future, deadline);
        _checkRoom(roomId, epoch);
        final run = evaluate;
        if (run == null) throw CoreError('此设备无法建立小红书网页会话');
        completer.future.ignore();
        _pending[id] = completer;
        _pendingRooms[id] = roomId;
        _pendingKinds[id] = 'room';
        await _within(run(buildRequestScript(id: id, path: path, query: query)),
            deadline);
        final result = await _within(completer.future, deadline);
        _checkRoom(roomId, epoch);
        return result;
      } on CoreError catch (error) {
        if (attempt == 0 && error.statusCode == 406) {
          await reset();
          continue;
        }
        rethrow;
      } on TimeoutException {
        throw CoreError('小红书网页会话超时', kind: CoreErrorKind.network);
      } finally {
        _pending.remove(id);
        _pendingRooms.remove(id);
        _pendingKinds.remove(id);
      }
    }
    throw CoreError('小红书网页会话不可用');
  }

  Future<dynamic> _requestDesktopRoom(String path, Map<String, dynamic> query,
      String url, String roomId, int epoch) async {
    final factory = _desktopFactory!;
    final deadline = DateTime.now().add(requestTimeout);
    for (var attempt = 0; attempt < 2; attempt++) {
      final id = '${++_sequence}';
      final completer = Completer<dynamic>();
      try {
        final session =
            await _within(_ensureDesktopRoomSession(factory, url), deadline);
        _checkRoom(roomId, epoch);
        _pending[id] = completer;
        _pendingRooms[id] = roomId;
        _pendingKinds[id] = 'room';
        completer.future.ignore();
        await _within(
            session.evaluateJavaScript(
                buildRequestScript(id: id, path: path, query: query)),
            deadline);
        final result = await _within(completer.future, deadline);
        _checkRoom(roomId, epoch);
        return result;
      } on CoreError catch (error) {
        if (attempt == 0 && error.statusCode == 406) {
          await reset();
          continue;
        }
        rethrow;
      } on TimeoutException {
        await reset();
        throw CoreError('小红书网页会话超时', kind: CoreErrorKind.network);
      } on XiaohongshuDesktopWebSessionUnavailable catch (error) {
        throw CoreError(error.message, kind: CoreErrorKind.network);
      } finally {
        _pending.remove(id);
        _pendingRooms.remove(id);
        _pendingKinds.remove(id);
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

  Future<XiaohongshuDesktopWebSession> _ensureDesktopRoomSession(
      XiaohongshuDesktopWebSessionFactory factory, String url) async {
    final current = _desktopRoomSession;
    if (current != null) return current;
    final pending = _desktopRoomCreation;
    if (pending != null) return pending;
    final created = factory.create(
      initialUrl: url,
      cookie: _cookieProvider(),
      onMessage: receive,
    );
    _desktopRoomCreation = created;
    try {
      final session = await created;
      if (!identical(_desktopRoomCreation, created) || _closed) {
        await session.close();
        throw CoreCancelledError();
      }
      _desktopRoomCreation = null;
      _desktopRoomSession = session;
      pageUrl.value = url;
      return session;
    } catch (_) {
      if (identical(_desktopRoomCreation, created)) _desktopRoomCreation = null;
      rethrow;
    }
  }

  @override
  Future<dynamic> requestHost(
      {required String hostId, required String roomId}) {
    final normalizedHostId = normalizeXiaohongshuHostId(hostId);
    final normalizedRoomId = XiaohongshuSite.normalizeRoomId(roomId);
    if (normalizedHostId == null || normalizedRoomId == null) {
      return Future<dynamic>.error(CoreError('小红书主播信息无效'));
    }
    if (!_platformSupported()) {
      return Future<dynamic>.error(CoreError('此设备未提供小红书网页签名能力'));
    }
    if (Utils.isOhos && !_desktopEnabled) {
      return Future<dynamic>.error(CoreError('此设备未提供小红书 PC 网页签名能力'));
    }
    final epoch = _roomEpoch[normalizedRoomId] ?? 0;
    final task = _hostQueue.then((_) {
      _checkRoom(normalizedRoomId, epoch);
      return _requestHost(normalizedHostId, normalizedRoomId, epoch);
    });
    _hostQueue = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  Future<dynamic> _requestHost(String hostId, String roomId, int epoch) async {
    if (_closed) throw CoreCancelledError();
    final deadline = DateTime.now().add(requestTimeout);
    final profileUrl = '${XiaohongshuSite.webBaseUrl}/user/profile/$hostId';
    for (var attempt = 0; attempt < 2; attempt++) {
      XiaohongshuDesktopWebSession? session;
      var abandonCreation = false;
      final id = '${++_sequence}';
      final completer = Completer<dynamic>();
      try {
        Future<void> Function(String script)? run;
        if (_desktopEnabled) {
          final factory = _desktopFactory;
          if (factory == null) {
            throw CoreError('此设备未提供小红书 PC 网页签名能力');
          }
          final creating = factory.create(
            initialUrl: profileUrl,
            cookie: _cookieProvider(),
            onMessage: receiveProfile,
          );
          creating.then((created) {
            if (abandonCreation) created.close().ignore();
          }, onError: (Object _, StackTrace __) {});
          try {
            final createdSession = await _within(creating, deadline);
            session = createdSession;
            _profileSessions.add(createdSession);
            run = createdSession.evaluateJavaScript;
          } on TimeoutException {
            abandonCreation = true;
            rethrow;
          }
        } else {
          _profileRoomId = roomId;
          _profileReady = Completer<void>();
          profileRevision.value++;
          profilePageUrl.value = profileUrl;
          await _within(_profileReady!.future, deadline);
          _checkRoom(roomId, epoch);
          run = evaluateProfile;
          if (run == null) {
            throw CoreError('此设备无法建立小红书 PC 网页会话');
          }
        }
        _checkRoom(roomId, epoch);
        _pending[id] = completer;
        _pendingRooms[id] = roomId;
        _pendingKinds[id] = 'profile';
        completer.future.ignore();
        await _within(
            run(buildHostRequestScript(id: id, hostId: hostId)), deadline);
        final result = await _within(completer.future, deadline);
        _checkRoom(roomId, epoch);
        return result;
      } on CoreError catch (error) {
        if (attempt == 0 && error.statusCode == 406) continue;
        rethrow;
      } on TimeoutException {
        throw CoreError('小红书主播信息查询超时', kind: CoreErrorKind.network);
      } on XiaohongshuDesktopWebSessionUnavailable catch (error) {
        throw CoreError(error.message, kind: CoreErrorKind.network);
      } finally {
        _pending.remove(id);
        _pendingRooms.remove(id);
        _pendingKinds.remove(id);
        _closeProfileContext();
        if (session != null) {
          _profileSessions.remove(session);
          await session.close();
        }
      }
    }
    throw CoreError('小红书主播信息不可用');
  }

  static const Set<String> _roomPaths = {
    XiaohongshuSite.roomInfoPath,
    XiaohongshuSite.statusPath,
    XiaohongshuSite.interactionPath,
    XiaohongshuSite.aggregatePath,
    XiaohongshuSite.stopInfoPath,
  };

  static String buildHostRequestScript(
      {required String id, required String hostId}) {
    // This URL and method are deliberately fixed. The PC site supplies the
    // signing function; no caller-provided path, origin, method or body enters
    // the page script.
    final payload = jsonEncode({'id': id, 'hostId': hostId});
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
        for (let i = 0; i < 100 && typeof window._webmsxyw !== 'function'; i++) {
          await new Promise(resolve => setTimeout(resolve, 100));
        }
        if (typeof window._webmsxyw !== 'function') {
          send({id: args.id, ok: false, status: 406}); return;
        }
        const path = '/api/sns/web/v1/user/hover_card?' + new URLSearchParams([
          ['target_user_id', args.hostId],
          ['image_formats', 'jpg,webp'],
          ['xsec_source', 'pc_hovercard'],
          ['xsec_token', '']
        ]).toString();
        const headers = window._webmsxyw(path, undefined);
        if (!headers || typeof headers !== 'object') {
          send({id: args.id, ok: false, status: 406}); return;
        }
        const response = await fetch('https://edith.xiaohongshu.com' + path, {
          method: 'GET', headers: headers, credentials: 'include', redirect: 'error'
        });
        const data = await response.json();
        send({id: args.id, ok: response.ok, status: response.status, data: data});
      } catch (_) {
        send({id: args.id, ok: false, status: 0});
      }
    })();''';
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
          {method: 'GET', headers, credentials: 'include'});
        const data = await response.json();
        send({id: args.id, ok: response.ok, status: response.status, data});
      } catch (_) { send({id: args.id, ok: false, status: 0}); }
    })();''';
  }

  @override
  void onClose() {
    _closed = true;
    pageUrl.value = null;
    evaluate = null;
    _closeProfileContext();
    if (_ready?.isCompleted == false) _ready!.complete();
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(CoreError('小红书会话已关闭'));
    }
    _pending.clear();
    _pendingRooms.clear();
    _pendingKinds.clear();
    _activeRooms.clear();
    _transientRoomRefs.clear();
    _transientRequests = 0;
    _desktopRoomSession?.close().ignore();
    _desktopRoomSession = null;
    _desktopRoomCreation = null;
    for (final session in _profileSessions.toList()) {
      session.close().ignore();
    }
    _profileSessions.clear();
    super.onClose();
  }
}
