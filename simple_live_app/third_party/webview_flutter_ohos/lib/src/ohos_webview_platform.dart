// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'ohos_webview_controller.dart';
import 'ohos_webview_cookie_manager.dart';

/// Implementation of [WebViewPlatform] using the WebKit API.
class OhosWebViewPlatform extends WebViewPlatform {
  /// Registers this class as the default instance of [WebViewPlatform].
  static void registerWith() {
    WebViewPlatform.instance = OhosWebViewPlatform();
  }

  @override
  OhosWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return OhosWebViewController(params);
  }

  @override
  OhosNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return OhosNavigationDelegate(params);
  }

  @override
  OhosWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return OhosWebViewWidget(params);
  }

  @override
  OhosWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return OhosWebViewCookieManager(params);
  }
}
