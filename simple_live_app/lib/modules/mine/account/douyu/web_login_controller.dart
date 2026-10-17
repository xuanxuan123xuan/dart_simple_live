import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/mine/account/account_controller.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:webview_flutter/webview_flutter.dart' as ohos_webview;

typedef DouyuBrowserCookieReader = Future<String> Function(String url);
typedef DouyuCookieWriter = Future<bool> Function(String cookie);
typedef DouyuCookieRevisionReader = int Function();

class DouyuWebLoginController extends BaseController {
  static const loginUrl =
      'https://passport.douyu.com/member/login?client_id=1&lang=cn';
  static const _rootUrl = 'https://douyu.com/';
  static const _wwwUrl = 'https://www.douyu.com/';
  static const _passportUrl = 'https://passport.douyu.com/';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43';
  static const _ohosWebCookieChannel =
      MethodChannel('simple_live/ohos_web_cookie');

  DouyuWebLoginController({
    DouyuBrowserCookieReader? browserCookieReader,
    DouyuCookieWriter? cookieWriter,
    DouyuCookieRevisionReader? cookieRevisionReader,
    void Function()? onSaved,
    void Function(String message)? showMessage,
  })  : _browserCookieReader = browserCookieReader,
        _cookieWriter = cookieWriter,
        _cookieRevisionReader = cookieRevisionReader,
        _onSaved = onSaved,
        _showMessage = showMessage;

  final DouyuBrowserCookieReader? _browserCookieReader;
  final DouyuCookieWriter? _cookieWriter;
  final DouyuCookieRevisionReader? _cookieRevisionReader;
  final void Function()? _onSaved;
  final void Function(String message)? _showMessage;

  InAppWebViewController? webViewController;
  ohos_webview.WebViewController? ohosWebViewController;
  CookieManager? cookieManager;
  final progress = 0.0.obs;
  final checking = false.obs;
  final errorMessage = ''.obs;
  Timer? _sessionPollTimer;
  bool _pageReady = false;
  bool _disposed = false;
  bool _flowInvalidated = false;
  int? _flowCookieRevision;

  @override
  void onInit() {
    super.onInit();
    _flowCookieRevision ??= _currentCookieRevision();
    if (Utils.isOhos) {
      _initializeOhosWebView();
    }
    _sessionPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_pageReady &&
          !checking.value &&
          _isFlowCurrent(_flowCookieRevision!)) {
        unawaited(saveCookie(silent: true));
      }
    });
  }

  @override
  void onClose() {
    _disposed = true;
    _sessionPollTimer?.cancel();
    super.onClose();
  }

  void _initializeOhosWebView() {
    final controller = ohos_webview.WebViewController()
      ..setJavaScriptMode(ohos_webview.JavaScriptMode.unrestricted)
      ..setUserAgent(userAgent)
      ..setNavigationDelegate(
        ohos_webview.NavigationDelegate(
          onProgress: (value) {
            if (!_isAlive) return;
            progress.value = value / 100;
          },
          onPageStarted: (_) => _onPageStarted(),
          onPageFinished: (_) => _onPageFinished(),
          onUrlChange: (_) {
            if (_pageReady) unawaited(saveCookie(silent: true));
          },
          onWebResourceError: (error) {
            if (!_isAlive || error.isForMainFrame != true) return;
            progress.value = 1;
            errorMessage.value = error.description;
          },
        ),
      );
    ohosWebViewController = controller;
    unawaited(controller.loadRequest(Uri.parse(loginUrl)));
  }

  void onWebViewCreated(InAppWebViewController controller) {
    if (!_isAlive) return;
    webViewController = controller;
    unawaited(
        controller.loadUrl(urlRequest: URLRequest(url: WebUri(loginUrl))));
  }

  void onLoadStart(InAppWebViewController controller, Uri? uri) {
    _onPageStarted();
  }

  void onProgressChanged(InAppWebViewController controller, int value) {
    if (_isAlive) progress.value = value / 100;
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) {
    _onPageFinished();
  }

  void onHistoryChanged() {
    if (_pageReady && _isAlive) unawaited(saveCookie(silent: true));
  }

  void onReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (!_isAlive || request.isForMainFrame != true) return;
    progress.value = 1;
    errorMessage.value = error.description;
  }

  void onReceivedHttpError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceResponse response,
  ) {
    if (!_isAlive || request.isForMainFrame != true) return;
    progress.value = 1;
    errorMessage.value = 'HTTP ${response.statusCode ?? '-'}';
  }

  void _onPageStarted() {
    if (!_isAlive) return;
    _pageReady = false;
    progress.value = 0;
    errorMessage.value = '';
  }

  void _onPageFinished() {
    if (!_isAlive) return;
    _pageReady = true;
    progress.value = 1;
    unawaited(saveCookie(silent: true));
  }

  Future<void> reload() async {
    if (!_isFlowCurrent(_flowCookieRevision!)) return;
    errorMessage.value = '';
    if (Utils.isOhos) {
      await ohosWebViewController?.reload();
    } else {
      await webViewController?.reload();
    }
    if (!_isFlowCurrent(_flowCookieRevision!)) return;
  }

  void fallbackToCookieLogin() {
    if (!_isAlive) return;
    Get.back();
    Get.find<AccountController>().doDouyuCookieConfig();
  }

  Future<bool> saveCookie({bool silent = false}) async {
    if (!_isAlive || checking.value || _flowInvalidated) return false;
    final flowRevision = _flowCookieRevision ??= _currentCookieRevision();
    if (!_isFlowCurrent(flowRevision)) {
      _notify(silent, '账号 Cookie 已发生变化，请重新打开斗鱼登录页后再试');
      return false;
    }

    checking.value = true;
    try {
      final cookie = await _readCookie();
      if (!_isFlowCurrent(flowRevision)) {
        _notify(silent, '账号 Cookie 已发生变化，请重新打开斗鱼登录页后再试');
        return false;
      }
      final normalized = DouyuCookieHelper.normalizeInput(cookie);
      if (normalized.isEmpty) {
        _notify(silent, '未读取到斗鱼 Cookie');
        return false;
      }
      if (!DouyuCookieHelper.hasAuthenticatedSession(normalized)) {
        _notify(silent, '还没有检测到斗鱼登录态，请先完成登录');
        return false;
      }

      bool saved;
      try {
        saved = await _writeCookie(normalized);
      } on DouyuCookieSaveException catch (error) {
        // Only the service can prove that this attempt owned its rollback.
        // A matching Cookie value alone could also be another user's change.
        final rollbackRevision = error.rollbackRevision;
        if (_isAlive &&
            !_flowInvalidated &&
            rollbackRevision != null &&
            _currentCookieRevision() == rollbackRevision) {
          _flowCookieRevision = rollbackRevision;
        } else {
          _isFlowCurrent(flowRevision);
        }
        rethrow;
      }
      if (!_isAlive) return false;
      if (!saved) {
        _notify(silent, '斗鱼 Cookie 格式无效，请重试');
        return false;
      }
      if (_flowInvalidated || _currentCookieRevision() != flowRevision + 1) {
        _invalidateFlow();
        _notify(silent, '账号 Cookie 已发生变化，请重新打开斗鱼登录页后再试');
        return false;
      }

      _sessionPollTimer?.cancel();
      _pageReady = false;

      final canRefresh = DouyuCookieHelper.hasRefreshCredentials(normalized);
      if (canRefresh) {
        _notify(silent, '斗鱼登录状态已保存，可自动续期');
      } else {
        _notify(false, '斗鱼登录状态已保存，但缺少 LTP0 或设备 ID，过期后需重新登录');
      }
      if (!_isAlive) return false;
      if (_onSaved != null) {
        _onSaved();
      } else {
        Get.back();
      }
      return true;
    } catch (_) {
      if (!_isAlive) return false;
      Log.e('读取或保存斗鱼网页登录状态失败', StackTrace.current);
      _notify(silent, '保存斗鱼登录状态失败，请重试');
      return false;
    } finally {
      if (_isAlive) checking.value = false;
    }
  }

  Future<String> _readCookie() async {
    final rootCookie = await _readCookieAt(_rootUrl);
    if (!_isAlive) return '';
    final passportCookie = await _readCookieAt(_passportUrl);
    if (!_isAlive) return '';
    final wwwCookie = await _readCookieAt(_wwwUrl);
    if (!_isAlive) return '';
    return DouyuCookieHelper.mergeBrowserCookies(
      rootCookie: rootCookie,
      passportCookie: passportCookie,
      wwwCookie: wwwCookie,
    );
  }

  Future<String> _readCookieAt(String url) async {
    final injectedReader = _browserCookieReader;
    if (injectedReader != null) return injectedReader(url);

    if (Utils.isOhos) {
      return await _ohosWebCookieChannel.invokeMethod<String>(
            'getCookie',
            {'url': url},
          ) ??
          '';
    }

    final cookies =
        await (cookieManager ??= CookieManager.instance()).getCookies(
      url: WebUri(url),
      webViewController: webViewController,
    );
    return cookies
        .where((cookie) => cookie.name.isNotEmpty && cookie.value.isNotEmpty)
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }

  Future<bool> _writeCookie(String cookie) {
    final injectedWriter = _cookieWriter;
    return injectedWriter != null
        ? injectedWriter(cookie)
        : DouyuAccountService.instance.setCookie(cookie);
  }

  int _currentCookieRevision() =>
      _cookieRevisionReader?.call() ??
      DouyuAccountService.instance.userCookieRevision;

  bool get _isAlive => !_disposed && !isClosed;

  bool _isFlowCurrent(int expectedRevision) {
    if (!_isAlive || _flowInvalidated) return false;
    if (_currentCookieRevision() != expectedRevision) {
      _invalidateFlow();
      return false;
    }
    return true;
  }

  void _invalidateFlow() {
    if (_flowInvalidated) return;
    _flowInvalidated = true;
    _sessionPollTimer?.cancel();
    if (_isAlive) {
      errorMessage.value = '账号 Cookie 已发生变化，请关闭此页后重新登录';
    }
  }

  void _notify(bool silent, String message) {
    if (silent || !_isAlive) return;
    final showMessage = _showMessage;
    if (showMessage != null) {
      showMessage(message);
    } else {
      SmartDialog.showToast(message);
    }
  }

  String get userAgent => _userAgent;
  bool get flowInvalidated => _flowInvalidated;
}
