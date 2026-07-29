import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:webview_flutter/webview_flutter.dart' as ohos_webview;

class BiliBiliWebLoginController extends BaseController {
  static const _loginUrl = 'https://passport.bilibili.com/login';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  static const _ohosWebCookieChannel =
      MethodChannel('simple_live/ohos_web_cookie');

  InAppWebViewController? webViewController;
  ohos_webview.WebViewController? ohosWebViewController;
  final CookieManager cookieManager = CookieManager.instance();
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
          unawaited(logined(silent: true));
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
            unawaited(logined(silent: true));
          },
          onUrlChange: (_) {
            if (_pageReady) {
              unawaited(logined(silent: true));
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
    controller.loadUrl(urlRequest: URLRequest(url: WebUri(_loginUrl)));
  }

  void onLoadStart(InAppWebViewController controller, Uri? uri) {
    _pageReady = false;
    progress.value = 0;
    errorMessage.value = '';
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) {
    _pageReady = true;
    progress.value = 1;
    unawaited(logined(silent: true));
  }

  void onProgressChanged(InAppWebViewController controller, int value) {
    progress.value = value / 100;
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

  void toQRLogin() async {
    await Get.toNamed(RoutePath.kBiliBiliQRLogin);
    if (Get.currentRoute == RoutePath.kBiliBiliWebLogin) {
      Get.back();
    }
  }

  Future<bool> logined({bool silent = false}) async {
    if (checking.value) {
      return false;
    }
    checking.value = true;
    try {
      final cookieStr = await _readCookie();
      if (cookieStr.isEmpty || !hasBilibiliAuthenticatedSession(cookieStr)) {
        if (!silent) {
          SmartDialog.showToast('尚未检测到哔哩哔哩登录状态');
        }
        return false;
      }
      Log.i('已读取哔哩哔哩登录 Cookie');
      BiliBiliAccountService.instance.setCookie(cookieStr);
      await BiliBiliAccountService.instance.loadUserInfo();
      if (!BiliBiliAccountService.instance.logined.value) {
        return false;
      }
      SmartDialog.showToast('哔哩哔哩账号登录成功');
      Get.back();
      return true;
    } catch (e, stackTrace) {
      Log.e('读取哔哩哔哩登录状态失败：$e', stackTrace);
      if (!silent) {
        SmartDialog.showToast('保存登录状态失败：$e');
      }
      return false;
    } finally {
      checking.value = false;
    }
  }

  Future<String> _readCookie() async {
    final values = <String, String>{};
    for (final url in const [
      'https://bilibili.com',
      'https://www.bilibili.com',
      'https://passport.bilibili.com',
    ]) {
      if (Utils.isOhos) {
        final cookie = await _ohosWebCookieChannel.invokeMethod<String>(
              'getCookie',
              {'url': url},
            ) ??
            '';
        _mergeCookieString(values, cookie);
      } else {
        final cookies = await cookieManager.getCookies(url: WebUri(url));
        for (final cookie in cookies) {
          if (cookie.name.isNotEmpty && cookie.value.isNotEmpty) {
            values[cookie.name] = cookie.value;
          }
        }
      }
    }
    return values.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  void _mergeCookieString(Map<String, String> values, String cookie) {
    for (final part in cookie.split(';')) {
      final item = part.trim();
      final separator = item.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final name = item.substring(0, separator).trim();
      final value = item.substring(separator + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) {
        values[name] = value;
      }
    }
  }
}

bool hasBilibiliAuthenticatedSession(String cookie) {
  return cookie.split(';').any((part) {
    final item = part.trim();
    return item.startsWith('SESSDATA=') && item.length > 'SESSDATA='.length;
  });
}
