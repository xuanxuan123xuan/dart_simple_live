// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'ohos_webview.dart';
import 'ohos_webview_controller.dart';

/// Object specifying creation parameters for creating a [OhosWebViewCookieManager].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformWebViewCookieManagerCreationParams] for
/// more information.
@immutable
class OhosWebViewCookieManagerCreationParams
    extends PlatformWebViewCookieManagerCreationParams {
  /// Creates a new [OhosWebViewCookieManagerCreationParams] instance.
  const OhosWebViewCookieManagerCreationParams._(
    // This parameter prevents breaking changes later.
    // ignore: avoid_unused_constructor_parameters
    PlatformWebViewCookieManagerCreationParams params,
  ) : super();

  /// Creates a [OhosWebViewCookieManagerCreationParams] instance based on [PlatformWebViewCookieManagerCreationParams].
  factory OhosWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
      PlatformWebViewCookieManagerCreationParams params) {
    return OhosWebViewCookieManagerCreationParams._(params);
  }
}

/// Handles all cookie operations for the Ohos platform.
class OhosWebViewCookieManager extends PlatformWebViewCookieManager {
  /// Creates a new [OhosWebViewCookieManager].
  OhosWebViewCookieManager(
    PlatformWebViewCookieManagerCreationParams params, {
    CookieManager? cookieManager,
  })  : _cookieManager = cookieManager ?? CookieManager.instance,
        super.implementation(
          params is OhosWebViewCookieManagerCreationParams
              ? params
              : OhosWebViewCookieManagerCreationParams
                  .fromPlatformWebViewCookieManagerCreationParams(params),
        );

  final CookieManager _cookieManager;

  @override
  Future<bool> clearCookies() {
    return _cookieManager.removeAllCookies();
  }

  @override
  Future<void> setCookie(WebViewCookie cookie) {
    if (!_isValidPath(cookie.path)) {
      throw ArgumentError(
          'The path property for the provided cookie was not given a legal value.');
    }
    return _cookieManager.setCookie(
      cookie.domain,
      '${Uri.encodeComponent(cookie.name)}=${Uri.encodeComponent(cookie.value)}; path=${cookie.path}',
    );
  }

  bool _isValidPath(String path) {
    // Permitted ranges based on RFC6265bis: https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-rfc6265bis-02#section-4.1.1
    for (final int char in path.codeUnits) {
      if ((char < 0x20 || char > 0x3A) && (char < 0x3C || char > 0x7E)) {
        return false;
      }
    }
    return true;
  }

  /// Sets whether the WebView should allow third party cookies to be set.
  ///
  /// Apps that target `Build.VERSION_CODES.KITKAT` or below default to allowing
  /// third party cookies. Apps targeting `Build.VERSION_CODES.LOLLIPOP` or
  /// later default to disallowing third party cookies.
  Future<void> setAcceptThirdPartyCookies(
    OhosWebViewController controller,
    bool accept,
  ) {
    // ignore: invalid_use_of_visible_for_testing_member
    final WebView webView = WebView.api.instanceManager
        .getInstanceWithWeakReference(controller.webViewIdentifier)!;
    return _cookieManager.setAcceptThirdPartyCookies(webView, accept);
  }
}
