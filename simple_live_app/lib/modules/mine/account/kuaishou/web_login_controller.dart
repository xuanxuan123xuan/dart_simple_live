import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';
import 'package:webview_flutter/webview_flutter.dart' as ohos_webview;

class KuaishouWebLoginController extends BaseController {
  static const _loginUrl = "https://live.kuaishou.com/";
  static const _cookieUrls = [
    "https://live.kuaishou.com",
    "https://kuaishou.com",
    "https://www.kuaishou.com",
  ];
  static const _desktopSafariUserAgent =
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
      "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15";
  static const _desktopChromeUserAgent =
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  InAppWebViewController? webViewController;
  ohos_webview.WebViewController? ohosWebViewController;
  CookieManager? cookieManager;
  final progress = 0.0.obs;
  final checking = false.obs;
  final errorMessage = "".obs;
  static const _ohosWebCookieChannel =
      MethodChannel('simple_live/ohos_web_cookie');
  Timer? _sessionPollTimer;
  bool _loginPageReady = false;
  bool _autoChecking = false;
  bool _ohosLoginRequestLoaded = false;
  bool _freshOhosSessionPrepared = false;
  bool _freshOhosStorageResetPending = false;
  bool _closing = false;
  final _freshSession = KuaishouFreshLoginSessionCoordinator();

  late final KuaishouAccountSlot targetSlot =
      Get.arguments is KuaishouAccountSlot
          ? Get.arguments as KuaishouAccountSlot
          : KuaishouAccountSlot.primary;

  String get targetSlotName =>
      targetSlot == KuaishouAccountSlot.primary ? "主账号" : "备用账号";

  bool get requiresFreshSession =>
      requiresFreshKuaishouLoginSession(targetSlot);

  bool get _usesManagedFreshSession =>
      requiresFreshSession && !Utils.isOhos;

  @override
  void onInit() {
    super.onInit();
    if (Utils.isOhos) {
      _initializeOhosWebView();
    }
    _sessionPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        if (_loginPageReady) {
          unawaited(_tryAutoCompleteLogin());
        }
      },
    );
  }

  @override
  void onClose() {
    _closing = true;
    _sessionPollTimer?.cancel();
    if (_usesManagedFreshSession && !_freshSession.cleaned) {
      unawaited(_clearKuaishouCookiesAfterClose());
    }
    super.onClose();
  }

  Future<void> _clearKuaishouCookiesAfterClose() async {
    try {
      await _clearKuaishouCookies();
    } catch (e) {
      Log.d("关闭快手备用账号登录页时清理 Cookie 失败：$e");
    }
  }

  void _initializeOhosWebView() {
    final controller = ohos_webview.WebViewController()
      ..setJavaScriptMode(ohos_webview.JavaScriptMode.unrestricted)
      ..setUserAgent(userAgent)
      ..setNavigationDelegate(
        ohos_webview.NavigationDelegate(
          onProgress: (value) => progress.value = value / 100,
          onPageStarted: (_) {
            _loginPageReady = false;
            progress.value = 0;
            errorMessage.value = '';
          },
          onPageFinished: (_) => unawaited(_handleOhosPageFinished()),
          onUrlChange: (_) {
            if (_loginPageReady && !_freshOhosStorageResetPending) {
              unawaited(_tryAutoCompleteLogin());
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              progress.value = 1;
              errorMessage.value = error.description;
            }
          },
        ),
      );
    ohosWebViewController = controller;
    unawaited(_openOhosLoginPage());
  }

  Future<void> _openOhosLoginPage() async {
    final controller = ohosWebViewController;
    if (controller == null) {
      return;
    }
    try {
      if (requiresFreshSession && !_freshOhosSessionPrepared) {
        await _ohosWebCookieChannel.invokeMethod<void>('clearCookies');
        _freshOhosSessionPrepared = true;
        _freshOhosStorageResetPending = true;
      }
      errorMessage.value = '';
      await controller.loadRequest(Uri.parse(_loginUrl));
      _ohosLoginRequestLoaded = true;
    } catch (e) {
      progress.value = 1;
      errorMessage.value =
          requiresFreshSession ? '无法创建备用账号独立登录会话' : '无法打开快手登录页面';
      Log.e('准备鸿蒙快手登录会话失败：$e', StackTrace.current);
    }
  }

  Future<void> _handleOhosPageFinished() async {
    progress.value = 1;
    final controller = ohosWebViewController;
    if (_freshOhosStorageResetPending && controller != null) {
      try {
        await controller.runJavaScript(
          'window.localStorage.clear(); window.sessionStorage.clear();',
        );
        _freshOhosStorageResetPending = false;
        _loginPageReady = false;
        await controller.loadRequest(Uri.parse(_loginUrl));
      } catch (e) {
        errorMessage.value = '无法清理主账号网页登录状态';
        Log.e('清理鸿蒙快手主账号网页登录状态失败：$e', StackTrace.current);
      }
      return;
    }
    _loginPageReady = true;
    await _prepareOhosLoginPage();
    await _tryAutoCompleteLogin();
  }

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    unawaited(_openLoginPage());
  }

  Future<void> _openLoginPage() async {
    final controller = webViewController;
    if (controller == null) {
      return;
    }
    try {
      if (_usesManagedFreshSession) {
        await _freshSession.prepare(clearCookies: _clearKuaishouCookies);
        if (_closing) {
          return;
        }
      }
      errorMessage.value = "";
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(_loginUrl)),
      );
    } catch (e) {
      _loginPageReady = false;
      progress.value = 1;
      errorMessage.value = requiresFreshSession
          ? "无法创建备用账号独立登录会话"
          : "无法打开快手登录页面";
      Log.e("准备快手登录会话失败：$e", StackTrace.current);
    }
  }

  void onProgressChanged(InAppWebViewController controller, int value) {
    progress.value = value / 100;
  }

  void onLoadStart(InAppWebViewController controller, Uri? uri) {
    _loginPageReady = false;
    progress.value = 0;
    errorMessage.value = "";
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) {
    unawaited(_handlePageFinished(controller));
  }

  Future<void> _handlePageFinished(
    InAppWebViewController controller,
  ) async {
    progress.value = 1;
    if (_usesManagedFreshSession && _freshSession.storageResetPending) {
      _loginPageReady = false;
      try {
        await _freshSession.finishBootstrap(
          clearPageStorage: () => _clearPageStorage(controller),
          clearCookies: _clearKuaishouCookies,
          reload: () => controller.loadUrl(
            urlRequest: URLRequest(url: WebUri(_loginUrl)),
          ),
        );
      } catch (e) {
        errorMessage.value = "无法清理主账号网页登录状态";
        Log.e("清理快手主账号网页登录状态失败：$e", StackTrace.current);
      }
      return;
    }
    _loginPageReady = true;
    await _tryAutoCompleteLogin();
  }

  void onReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (request.isForMainFrame == true) {
      progress.value = 1;
      errorMessage.value = error.description;
    }
  }

  void onReceivedHttpError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceResponse response,
  ) {
    if (request.isForMainFrame == true) {
      progress.value = 1;
      errorMessage.value = "HTTP ${response.statusCode ?? "-"}";
    }
  }

  Future<void> reload() async {
    if (_closing) {
      return;
    }
    errorMessage.value = "";
    if (Utils.isOhos) {
      if (_ohosLoginRequestLoaded) {
        await ohosWebViewController?.reload();
      } else {
        await _openOhosLoginPage();
      }
    } else {
      if (_usesManagedFreshSession && !_freshSession.prepared) {
        await _openLoginPage();
      } else {
        await webViewController?.reload();
      }
    }
  }

  Future<void> saveCookie({
    bool silent = false,
    bool autoClose = true,
  }) async {
    if (_closing ||
        (_usesManagedFreshSession && _freshSession.blocksAutoCheck)) {
      if (!silent && !_closing) {
        SmartDialog.showToast("备用账号登录会话正在准备，请稍后重试");
      }
      return;
    }
    if (checking.value) {
      return;
    }
    checking.value = true;
    try {
      final snapshot = await _readCookie();
      var cookie = snapshot.cookie;
      final localStorageKww = await _readKww();
      if (localStorageKww.isNotEmpty &&
          _readCookieValue(cookie, 'kwfv1').isEmpty) {
        final encodedKww = Uri.encodeComponent(localStorageKww);
        cookie =
            cookie.isEmpty ? 'kwfv1=$encodedKww' : '$cookie; kwfv1=$encodedKww';
      }
      final kww = localStorageKww.isNotEmpty
          ? localStorageKww
          : _readCookieValue(cookie, 'kwfv1');
      if (cookie.isEmpty) {
        if (!silent) {
          SmartDialog.showToast("未读取到快手 Cookie");
        }
        return;
      }
      if (!hasKuaishouAuthenticatedSession(cookie)) {
        if (!silent) {
          SmartDialog.showToast("尚未检测到快手登录状态，请先完成扫码或手机号登录");
        }
        return;
      }
      final saved = KuaishouAccountService.instance.setCookieForSlot(
        targetSlot,
        cookie,
        kww: kww,
        expiresAt: snapshot.expiresAt,
      );
      if (!saved) {
        if (!silent || autoClose) {
          SmartDialog.showToast("主账号和备用账号不能使用相同 Cookie 或 UID");
        }
        return;
      }
      if (kww.isEmpty) {
        if (!silent || autoClose) {
          SmartDialog.showToast("Cookie 已保存，但未获取到 kwfv1；请刷新页面或完成验证后再保存");
        }
        return;
      }
      if (autoClose) {
        if (!await prepareToClose()) {
          return;
        }
      }
      if (!silent || autoClose) {
        SmartDialog.showToast("快手$targetSlotName Cookie 已保存，可用于搜索和弹幕");
      }
      if (autoClose) {
        Get.back();
      }
    } catch (e) {
      Log.e("保存快手 Cookie 失败：$e", StackTrace.current);
      if (!silent) {
        SmartDialog.showToast("保存失败：$e");
      }
    } finally {
      checking.value = false;
    }
  }

  Future<_KuaishouCookieSnapshot> _readCookie() async {
    if (Utils.isOhos) {
      return _readOhosCookie();
    }
    final manager = cookieManager ??= CookieManager.instance();
    final values = <String, String>{};
    final expiryDatesByName = <String, List<int>>{};
    for (final url in _cookieUrls) {
      final cookies = await manager.getCookies(
        url: WebUri(url),
        webViewController: webViewController,
      );
      for (final item in cookies) {
        final name = item.name.trim();
        final value = item.value.trim();
        if (name.isNotEmpty && value.isNotEmpty) {
          values.putIfAbsent(name, () => value);
        }
        final expiresDate = item.expiresDate;
        if (_kuaishouAuthCookiePriority.contains(name) &&
            expiresDate != null &&
            expiresDate > 0) {
          expiryDatesByName.putIfAbsent(name, () => <int>[]).add(expiresDate);
        }
      }
    }
    return _KuaishouCookieSnapshot(
      cookie: values.entries.map((e) => "${e.key}=${e.value}").join("; "),
      expiresAt: resolveKuaishouAuthCookieExpiry(expiryDatesByName),
    );
  }

  Future<void> _tryAutoCompleteLogin() async {
    if (checking.value ||
        _autoChecking ||
        _freshOhosStorageResetPending ||
        _closing ||
        (_usesManagedFreshSession && _freshSession.blocksAutoCheck)) {
      return;
    }
    _autoChecking = true;
    try {
      final snapshot = await _readCookie();
      if (!hasKuaishouAuthenticatedSession(snapshot.cookie)) {
        return;
      }
      await saveCookie(silent: true, autoClose: true);
    } catch (e) {
      Log.d("自动读取快手登录状态失败：$e");
    } finally {
      _autoChecking = false;
    }
  }

  Future<void> _prepareOhosLoginPage() async {
    try {
      // The current OHOS WebView implementation disables multiple windows.
      // Keep links and window.open based flows inside the login WebView.
      await ohosWebViewController?.runJavaScript('''
        (() => {
          if (!window.__simpleLiveLoginPatched) {
            window.__simpleLiveLoginPatched = true;
            const nativeOpen = window.open;
            window.open = (url, ...args) => {
              if (typeof url === 'string' && url.length > 0) {
                window.location.href = url;
                return window;
              }
              return nativeOpen.call(window, url, ...args);
            };
          }
          document.querySelectorAll('a[target="_blank"]').forEach((item) => {
            item.setAttribute('target', '_self');
          });
        })();
      ''');
    } catch (e) {
      Log.d("准备鸿蒙快手登录页面失败：$e");
    }
  }

  Future<_KuaishouCookieSnapshot> _readOhosCookie() async {
    final values = <String, String>{};
    for (final url in _cookieUrls) {
      final cookie = await _ohosWebCookieChannel.invokeMethod<String>(
            'getCookie',
            {'url': url},
          ) ??
          '';
      for (final part in cookie.split(';')) {
        final item = part.trim();
        final index = item.indexOf('=');
        if (index <= 0) {
          continue;
        }
        final name = item.substring(0, index).trim();
        final value = item.substring(index + 1).trim();
        if (name.isNotEmpty && value.isNotEmpty) {
          values.putIfAbsent(name, () => value);
        }
      }
    }
    return _KuaishouCookieSnapshot(
      cookie: values.entries.map((e) => "${e.key}=${e.value}").join("; "),
      expiresAt: null,
    );
  }

  Future<String> _readKww() async {
    if (Utils.isOhos) {
      final value = await ohosWebViewController?.runJavaScriptReturningResult(
        "window.localStorage.getItem('kwfv1') || ''",
      );
      return _normalizeJavascriptResult(value);
    }
    final value = await webViewController?.evaluateJavascript(
      source: "window.localStorage.getItem('kwfv1') || ''",
    );
    return _normalizeJavascriptResult(value);
  }

  Future<void> _clearPageStorage(InAppWebViewController controller) async {
    await controller.evaluateJavascript(
      source: "window.localStorage.clear(); window.sessionStorage.clear();",
    );
  }

  Future<void> _clearKuaishouCookies() async {
    final manager = cookieManager ??= CookieManager.instance();
    final deleted = <String>{};
    for (final url in _cookieUrls) {
      final webUri = WebUri(url);
      final cookies = await manager.getCookies(url: webUri);
      for (final cookie in cookies) {
        final domain = cookie.domain;
        final path = cookie.path ?? "/";
        final key = "${cookie.name}\u0000${domain ?? url}\u0000$path";
        if (!deleted.add(key)) {
          continue;
        }
        final removed = await manager.deleteCookie(
          url: webUri,
          name: cookie.name,
          domain: domain,
          path: path,
        );
        if (!removed) {
          throw StateError("无法清理快手网页登录 Cookie");
        }
      }
    }
  }

  Future<bool> prepareToClose() async {
    if (_closing && _freshSession.cleaned) {
      return true;
    }
    _closing = true;
    _loginPageReady = false;
    if (!_usesManagedFreshSession) {
      return true;
    }
    final controller = webViewController;
    try {
      await _freshSession.cleanup(
        clearPageStorage: () async {
          if (controller != null) {
            await _clearPageStorage(controller);
          }
        },
        clearCookies: _clearKuaishouCookies,
      );
      return true;
    } catch (e) {
      errorMessage.value = "无法清理备用账号网页登录状态，请重试返回";
      SmartDialog.showToast(errorMessage.value);
      Log.e("退出快手备用账号登录页时清理会话失败：$e", StackTrace.current);
      _closing = false;
      return false;
    }
  }

  String _normalizeJavascriptResult(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      try {
        return jsonDecode(text)?.toString().trim() ?? '';
      } catch (_) {}
    }
    return text == 'null' ? '' : text;
  }

  String get userAgent =>
      Platform.isIOS ? _desktopSafariUserAgent : _desktopChromeUserAgent;

  String _readCookieValue(String cookie, String name) {
    for (final part in cookie.split(';')) {
      final item = part.trim();
      if (item.startsWith('$name=')) {
        return item.substring(name.length + 1).trim();
      }
    }
    return '';
  }
}

bool requiresFreshKuaishouLoginSession(KuaishouAccountSlot slot) {
  return slot == KuaishouAccountSlot.secondary;
}

class KuaishouFreshLoginSessionCoordinator {
  bool _prepared = false;
  bool _storageResetPending = false;
  bool _cleaned = false;
  Future<void>? _prepareFuture;
  Future<void>? _bootstrapFuture;
  Future<void>? _cleanupFuture;

  bool get prepared => _prepared;
  bool get storageResetPending => _storageResetPending;
  bool get cleaned => _cleaned;
  bool get blocksAutoCheck => !_prepared || _storageResetPending || _cleaned;

  Future<void> prepare({
    required Future<void> Function() clearCookies,
  }) {
    if (_prepared) {
      return Future<void>.value();
    }
    return _prepareFuture ??= _runPrepare(clearCookies);
  }

  Future<void> _runPrepare(Future<void> Function() clearCookies) async {
    try {
      await clearCookies();
      _prepared = true;
      _storageResetPending = true;
    } finally {
      _prepareFuture = null;
    }
  }

  Future<void> finishBootstrap({
    required Future<void> Function() clearPageStorage,
    required Future<void> Function() clearCookies,
    required Future<void> Function() reload,
  }) {
    if (!_storageResetPending) {
      return Future<void>.value();
    }
    return _bootstrapFuture ??= _runBootstrap(
      clearPageStorage: clearPageStorage,
      clearCookies: clearCookies,
      reload: reload,
    );
  }

  Future<void> _runBootstrap({
    required Future<void> Function() clearPageStorage,
    required Future<void> Function() clearCookies,
    required Future<void> Function() reload,
  }) async {
    try {
      await clearPageStorage();
      await clearCookies();
      await reload();
      _storageResetPending = false;
    } finally {
      _bootstrapFuture = null;
    }
  }

  Future<void> cleanup({
    required Future<void> Function() clearPageStorage,
    required Future<void> Function() clearCookies,
  }) {
    if (_cleaned) {
      return Future<void>.value();
    }
    return _cleanupFuture ??= _runCleanup(
      clearPageStorage: clearPageStorage,
      clearCookies: clearCookies,
    );
  }

  Future<void> _runCleanup({
    required Future<void> Function() clearPageStorage,
    required Future<void> Function() clearCookies,
  }) async {
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await clearPageStorage();
    } catch (e, stackTrace) {
      firstError = e;
      firstStackTrace = stackTrace;
    }
    try {
      await clearCookies();
    } catch (e, stackTrace) {
      firstError ??= e;
      firstStackTrace ??= stackTrace;
    }
    try {
      if (firstError != null) {
        Error.throwWithStackTrace(firstError, firstStackTrace!);
      }
      _cleaned = true;
    } finally {
      _cleanupFuture = null;
    }
  }
}

const List<String> _kuaishouAuthCookiePriority = [
  'kuaishou.live.web_st',
  'kuaishou.server.web_st',
  'kuaishou.live.web_at',
  'passToken',
];

bool hasKuaishouAuthenticatedSession(String cookie) {
  for (final part in cookie.split(';')) {
    final item = part.trim();
    final index = item.indexOf('=');
    if (index > 0 &&
        _kuaishouAuthCookiePriority.contains(item.substring(0, index))) {
      return item.substring(index + 1).trim().isNotEmpty;
    }
  }
  return false;
}

/// Resolves the expiry of the credential that actually establishes the
/// Kuaishou session. Lower-priority companion cookies must not extend the
/// reported lifetime of the primary login token.
DateTime? resolveKuaishouAuthCookieExpiry(
  Map<String, Iterable<int>> expiryDatesByName,
) {
  for (final name in _kuaishouAuthCookiePriority) {
    final dates = expiryDatesByName[name]
        ?.where((value) => value > 0)
        .toList(growable: false);
    if (dates == null || dates.isEmpty) {
      continue;
    }
    // The same cookie name can exist on more than one Kuaishou domain. Use
    // the earliest copy so the UI never overstates the remaining lifetime.
    final expiresAtMs =
        dates.reduce((left, right) => left < right ? left : right);
    return DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
  }
  return null;
}

class _KuaishouCookieSnapshot {
  final String cookie;
  final DateTime? expiresAt;

  const _KuaishouCookieSnapshot({
    required this.cookie,
    required this.expiresAt,
  });
}
