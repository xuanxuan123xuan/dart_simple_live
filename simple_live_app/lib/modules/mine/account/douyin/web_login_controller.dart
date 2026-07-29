import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:webview_flutter/webview_flutter.dart' as ohos_webview;

class DouyinWebLoginController extends BaseController {
  static const _loginUrl = 'https://www.douyin.com/';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0';
  static const _ohosWebCookieChannel =
      MethodChannel('simple_live/ohos_web_cookie');

  InAppWebViewController? webViewController;
  ohos_webview.WebViewController? ohosWebViewController;
  CookieManager? cookieManager;
  final progress = 0.0.obs;
  final checking = false.obs;
  final errorMessage = ''.obs;
  Timer? _sessionPollTimer;
  bool _pageReady = false;

  @override
  void onInit() {
    super.onInit();
    if (Utils.isOhos) {
      _initializeOhosWebView();
    }
    _sessionPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        if (_pageReady) {
          unawaited(saveCookie(silent: true));
        }
      },
    );
  }

  @override
  void onClose() {
    _sessionPollTimer?.cancel();
    super.onClose();
  }

  void _initializeOhosWebView() {
    final controller = ohos_webview.WebViewController()
      ..setJavaScriptMode(ohos_webview.JavaScriptMode.unrestricted)
      ..setUserAgent(_userAgent)
      ..setNavigationDelegate(
        ohos_webview.NavigationDelegate(
          onProgress: (value) => progress.value = value / 100,
          onPageStarted: (_) {
            _pageReady = false;
            progress.value = 0;
            errorMessage.value = '';
          },
          onPageFinished: (_) {
            _pageReady = true;
            progress.value = 1;
            unawaited(saveCookie(silent: true));
          },
          onUrlChange: (_) {
            if (_pageReady) {
              unawaited(saveCookie(silent: true));
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
    controller.loadRequest(Uri.parse(_loginUrl));
  }

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(_loginUrl)),
    );
  }

  void onLoadStart(InAppWebViewController controller, Uri? uri) {
    _pageReady = false;
    progress.value = 0;
    errorMessage.value = '';
  }

  void onProgressChanged(InAppWebViewController controller, int value) {
    progress.value = value / 100;
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) {
    _pageReady = true;
    progress.value = 1;
    unawaited(saveCookie(silent: true));
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

  Future<void> reload() async {
    errorMessage.value = '';
    if (Utils.isOhos) {
      await ohosWebViewController?.reload();
    } else {
      await webViewController?.reload();
    }
  }

  Future<void> saveCookie({bool silent = false}) async {
    if (checking.value) {
      return;
    }
    checking.value = true;
    try {
      final cookie = await _readCookie();
      if (cookie.isEmpty) {
        if (!silent) {
          SmartDialog.showToast('未读取到抖音 Cookie');
        }
        return;
      }
      if (!hasDouyinAuthenticatedSession(cookie)) {
        if (!silent) {
          SmartDialog.showToast('还没有检测到登录态，请先在页面中完成抖音登录');
        }
        return;
      }
      DouyinAccountService.instance.setCookie(cookie);
      SmartDialog.showToast('抖音登录态已保存，可用于搜索');
      Get.back();
    } catch (e) {
      Log.e('保存抖音 Cookie 失败：$e', StackTrace.current);
      if (!silent) {
        SmartDialog.showToast('保存失败：$e');
      }
    } finally {
      checking.value = false;
    }
  }

  Future<String> _readCookie() async {
    final values = <String, String>{};
    for (final url in const [
      'https://www.douyin.com',
      'https://douyin.com',
      'https://live.douyin.com',
    ]) {
      if (Utils.isOhos) {
        final cookie = await _ohosWebCookieChannel.invokeMethod<String>(
              'getCookie',
              {'url': url},
            ) ??
            '';
        _mergeCookieString(values, cookie);
      } else {
        final manager = cookieManager ??= CookieManager.instance();
        final cookies = await manager.getCookies(url: WebUri(url));
        for (final item in cookies) {
          final name = item.name.trim();
          final value = item.value.trim();
          if (name.isNotEmpty && value.isNotEmpty) {
            values[name] = value;
          }
        }
      }
    }
    return values.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void _mergeCookieString(Map<String, String> values, String cookie) {
    for (final part in cookie.split(';')) {
      final item = part.trim();
      final separator = item.indexOf('=');
      if (separator <= 0) continue;
      final name = item.substring(0, separator).trim();
      final value = item.substring(separator + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) {
        values[name] = value;
      }
    }
  }

  String get userAgent => _userAgent;
}

bool hasDouyinAuthenticatedSession(String cookie) {
  for (final part in cookie.split(';')) {
    final item = part.trim();
    final separator = item.indexOf('=');
    if (separator <= 0) continue;
    final name = item.substring(0, separator).trim().toLowerCase();
    final value = item.substring(separator + 1).trim();
    if (value.isEmpty) continue;
    if (name == 'sessionid' ||
        name == 'sid_guard' ||
        name == 'sid_tt' ||
        name == 'uid_tt' ||
        (name == 'login_status' && value == '1')) {
      return true;
    }
  }
  return false;
}
