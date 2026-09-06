// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
// ignore: implementation_imports
import 'package:webview_flutter_platform_interface/src/webview_flutter_platform_interface_legacy.dart';

import '../ohos_webview.dart';
import 'webview_ohos.dart';
import 'webview_ohos_widget.dart';

/// Ohos [WebViewPlatform] that uses [OhosViewSurface] to build the
/// [WebView] widget.
///
/// To use this, set [WebView.platform] to an instance of this class.
///
/// This implementation uses [OhosViewSurface] to render the [WebView] on
/// Ohos. It solves multiple issues related to accessibility and interaction
/// with the [WebView] at the cost of some performance on Ohos versions below
/// 10.
///
/// To support transparent backgrounds on all Ohos devices, this
/// implementation uses hybrid composition when the opacity of
/// `CreationParams.backgroundColor` is less than 1.0. See
/// https://github.com/flutter/flutter/wiki/Hybrid-Composition for more
/// information.
class SurfaceOhosWebView extends OhosWebView {
  /// Constructs a [SurfaceOhosWebView].
  SurfaceOhosWebView({@visibleForTesting super.instanceManager});

  @override
  Widget build({
    required BuildContext context,
    required CreationParams creationParams,
    required JavascriptChannelRegistry javascriptChannelRegistry,
    WebViewPlatformCreatedCallback? onWebViewPlatformCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
    required WebViewPlatformCallbacksHandler webViewPlatformCallbacksHandler,
  }) {
    return WebViewOhosWidget(
      creationParams: creationParams,
      callbacksHandler: webViewPlatformCallbacksHandler,
      javascriptChannelRegistry: javascriptChannelRegistry,
      onBuildWidget: (WebViewOhosPlatformController controller) {
        return PlatformViewLink(
          viewType: 'plugins.flutter.io/webview',
          surfaceFactory: (
            BuildContext context,
            PlatformViewController controller,
          ) {
            return OhosViewSurface(
              controller: controller as OhosViewController,
              gestureRecognizers: gestureRecognizers ??
                  const <Factory<OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            );
          },
          onCreatePlatformView: (PlatformViewCreationParams params) {
            final Color? backgroundColor = creationParams.backgroundColor;
            return _createViewController(
              // On some Ohos devices, transparent backgrounds can cause
              // rendering issues on the non hybrid composition
              // OhosViewSurface. This switches the WebView to Hybrid
              // Composition when the background color is not 100% opaque.
              hybridComposition:
                  backgroundColor != null && backgroundColor.opacity < 1.0,
              id: params.id,
              viewType: 'plugins.flutter.io/webview',
              // WebView content is not affected by the Ohos view's layout direction,
              // we explicitly set it here so that the widget doesn't require an ambient
              // directionality.
              layoutDirection:
                  Directionality.maybeOf(context) ?? TextDirection.ltr,
              webViewIdentifier:
                  instanceManager.getIdentifier(controller.webView)!,
            )
              ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
              ..addOnPlatformViewCreatedListener((int id) {
                if (onWebViewPlatformCreated != null) {
                  onWebViewPlatformCreated(controller);
                }
              })
              ..create();
          },
        );
      },
    );
  }

  OhosViewController _createViewController({
    required bool hybridComposition,
    required int id,
    required String viewType,
    required TextDirection layoutDirection,
    required int webViewIdentifier,
  }) {
    if (hybridComposition) {
      return PlatformViewsService.initExpensiveOhosView(
        id: id,
        viewType: viewType,
        layoutDirection: layoutDirection,
        creationParams: webViewIdentifier,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return PlatformViewsService.initSurfaceOhosView(
      id: id,
      viewType: viewType,
      layoutDirection: layoutDirection,
      creationParams: webViewIdentifier,
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
