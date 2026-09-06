// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'ohos_proxy.dart';
import 'ohos_webview.dart' as ohos_webview;
import 'ohos_webview_api_impls.dart';
import 'instance_manager.dart';
import 'platform_views_service_proxy.dart';
import 'weak_reference_utils.dart';

/// Object specifying creation parameters for creating a [OhosWebViewController].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformWebViewControllerCreationParams] for
/// more information.
@immutable
class OhosWebViewControllerCreationParams
    extends PlatformWebViewControllerCreationParams {
  /// Creates a new [OhosWebViewControllerCreationParams] instance.
  OhosWebViewControllerCreationParams({
    bool? this.isAllowFullScreenRotate = false,
    @visibleForTesting this.ohosWebViewProxy = const OhosWebViewProxy(),
    @visibleForTesting ohos_webview.WebStorage? ohosWebStorage,
  })  : ohosWebStorage =
            ohosWebStorage ?? ohos_webview.WebStorage.instance,
        super();

  /// Creates a [OhosWebViewControllerCreationParams] instance based on [PlatformWebViewControllerCreationParams].
  factory OhosWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
    // Recommended placeholder to prevent being broken by platform interface.
    // ignore: avoid_unused_constructor_parameters
    PlatformWebViewControllerCreationParams params, {
    bool? isAllowFullScreenRotate = false,
    @visibleForTesting
    OhosWebViewProxy ohosWebViewProxy = const OhosWebViewProxy(),
    @visibleForTesting ohos_webview.WebStorage? ohosWebStorage,
  }) {
    return OhosWebViewControllerCreationParams(
      isAllowFullScreenRotate: isAllowFullScreenRotate,
      ohosWebViewProxy: ohosWebViewProxy,
      ohosWebStorage:
          ohosWebStorage ?? ohos_webview.WebStorage.instance,
    );
  }

  /// Enables or disables full screen rotate within WebView.
  bool? isAllowFullScreenRotate;

  /// Handles constructing objects and calling static methods for the Ohos WebView
  /// native library.
  @visibleForTesting
  final OhosWebViewProxy ohosWebViewProxy;

  /// Manages the JavaScript storage APIs provided by the [ohos_webview.WebView].
  @visibleForTesting
  final ohos_webview.WebStorage ohosWebStorage;
}

/// Ohos-specific resources that can require permissions.
class OhosWebViewPermissionResourceType
    extends WebViewPermissionResourceType {
  const OhosWebViewPermissionResourceType._(super.name);

  /// A resource that will allow sysex messages to be sent to or received from
  /// MIDI devices.
  static const OhosWebViewPermissionResourceType midiSysex =
      OhosWebViewPermissionResourceType._('midiSysex');

  /// A resource that belongs to a protected media identifier.
  static const OhosWebViewPermissionResourceType protectedMediaId =
      OhosWebViewPermissionResourceType._('protectedMediaId');
}

/// Implementation of the [PlatformWebViewController] with the Ohos WebView API.
class OhosWebViewController extends PlatformWebViewController {
  /// Creates a new [OhosWebViewController].
  OhosWebViewController(PlatformWebViewControllerCreationParams params)
      : super.implementation(params is OhosWebViewControllerCreationParams
            ? params
            : OhosWebViewControllerCreationParams
                .fromPlatformWebViewControllerCreationParams(params)) {
    _webView.settings.setAllowFullScreenRotate(params is OhosWebViewControllerCreationParams ? params.isAllowFullScreenRotate ?? false : false);
    _webView.settings.setDomStorageEnabled(true);
    _webView.settings.setJavaScriptCanOpenWindowsAutomatically(true);
    _webView.settings.setSupportMultipleWindows(true);
    _webView.settings.setLoadWithOverviewMode(true);
    _webView.settings.setUseWideViewPort(true);
    _webView.settings.setDisplayZoomControls(false);
    _webView.settings.setBuiltInZoomControls(true);

    _webView.setWebChromeClient(_webChromeClient);
  }

  OhosWebViewControllerCreationParams get _ohosWebViewParams =>
      params as OhosWebViewControllerCreationParams;

  /// The native [ohos_webview.WebView] being controlled.
  late final ohos_webview.WebView _webView =
      _ohosWebViewParams.ohosWebViewProxy.createOhosWebView(
          onScrollChanged: withWeakReferenceTo(this,
              (WeakReference<OhosWebViewController> weakReference) {
    return (int left, int top, int oldLeft, int oldTop) async {
      final void Function(ScrollPositionChange)? callback =
          weakReference.target?._onScrollPositionChangedCallback;
      callback?.call(ScrollPositionChange(left.toDouble(), top.toDouble()));
    };
  }));

  late final ohos_webview.WebChromeClient _webChromeClient =
      _ohosWebViewParams.ohosWebViewProxy.createOhosWebChromeClient(
    onProgressChanged: withWeakReferenceTo(this,
        (WeakReference<OhosWebViewController> weakReference) {
      return (ohos_webview.WebView webView, int progress) {
        if (weakReference.target?._currentNavigationDelegate?._onProgress !=
            null) {
          weakReference
              .target!._currentNavigationDelegate!._onProgress!(progress);
        }
      };
    }),
    onGeolocationPermissionsShowPrompt: withWeakReferenceTo(this,
        (WeakReference<OhosWebViewController> weakReference) {
      return (String origin,
          ohos_webview.GeolocationPermissionsCallback callback) async {
        final OnGeolocationPermissionsShowPrompt? onShowPrompt =
            weakReference.target?._onGeolocationPermissionsShowPrompt;
        if (onShowPrompt != null) {
          final GeolocationPermissionsResponse response = await onShowPrompt(
            GeolocationPermissionsRequestParams(origin: origin),
          );
          return callback.invoke(origin, response.allow, response.retain);
        } else {
          // default don't allow
          return callback.invoke(origin, false, false);
        }
      };
    }),
    onGeolocationPermissionsHidePrompt: withWeakReferenceTo(this,
        (WeakReference<OhosWebViewController> weakReference) {
      return (ohos_webview.WebChromeClient instance) {
        final OnGeolocationPermissionsHidePrompt? onHidePrompt =
            weakReference.target?._onGeolocationPermissionsHidePrompt;
        if (onHidePrompt != null) {
          onHidePrompt();
        }
      };
    }),
    onShowCustomView: withWeakReferenceTo(this,
        (WeakReference<OhosWebViewController> weakReference) {
      return (_, ohos_webview.View view,
          ohos_webview.CustomViewCallback callback) {
        final OhosWebViewController? webViewController =
            weakReference.target;
        if (webViewController == null) {
          callback.onCustomViewHidden();
          return;
        }
        final OnShowCustomWidgetCallback? onShowCallback =
            webViewController._onShowCustomWidgetCallback;
        if (onShowCallback == null) {
          callback.onCustomViewHidden();
          return;
        }
        onShowCallback(
          OhosCustomViewWidget.private(
            controller: webViewController,
            customView: view,
          ),
          () => callback.onCustomViewHidden(),
        );
      };
    }),
    onHideCustomView: withWeakReferenceTo(this,
        (WeakReference<OhosWebViewController> weakReference) {
      return (ohos_webview.WebChromeClient instance) {
        final OnHideCustomWidgetCallback? onHideCustomViewCallback =
            weakReference.target?._onHideCustomWidgetCallback;
        if (onHideCustomViewCallback != null) {
          onHideCustomViewCallback();
        }
      };
    }),
    onShowFileChooser: withWeakReferenceTo(
      this,
      (WeakReference<OhosWebViewController> weakReference) {
        return (ohos_webview.WebView webView,
            ohos_webview.FileChooserParams params) async {
          if (weakReference.target?._onShowFileSelectorCallback != null) {
            return weakReference.target!._onShowFileSelectorCallback!(
              FileSelectorParams._fromFileChooserParams(params),
            );
          }
          return <String>[];
        };
      },
    ),
    onConsoleMessage: withWeakReferenceTo(
      this,
      (WeakReference<OhosWebViewController> weakReference) {
        return (ohos_webview.WebChromeClient webChromeClient,
            ohos_webview.ConsoleMessage consoleMessage) async {
          final void Function(JavaScriptConsoleMessage)? callback =
              weakReference.target?._onConsoleLogCallback;
          if (callback != null) {
            JavaScriptLogLevel logLevel;
            switch (consoleMessage.level) {
              // Android maps `console.debug` to `MessageLevel.TIP`, it seems
              // `MessageLevel.DEBUG` if not being used.
              case ConsoleMessageLevel.debug:
              case ConsoleMessageLevel.tip:
                logLevel = JavaScriptLogLevel.debug;
                break;
              case ConsoleMessageLevel.error:
                logLevel = JavaScriptLogLevel.error;
                break;
              case ConsoleMessageLevel.warning:
                logLevel = JavaScriptLogLevel.warning;
                break;
              case ConsoleMessageLevel.unknown:
              case ConsoleMessageLevel.log:
                logLevel = JavaScriptLogLevel.log;
                break;
            }

            callback(JavaScriptConsoleMessage(
              level: logLevel,
              message: consoleMessage.message,
            ));
          }
        };
      },
    ),
    onPermissionRequest: withWeakReferenceTo(
      this,
      (WeakReference<OhosWebViewController> weakReference) {
        return (_, ohos_webview.PermissionRequest request) async {
          final void Function(PlatformWebViewPermissionRequest)? callback =
              weakReference.target?._onPermissionRequestCallback;
          if (callback == null) {
            return request.deny();
          } else {
            final Set<WebViewPermissionResourceType> types = request.resources
                .map<WebViewPermissionResourceType?>((String type) {
                  switch (type) {
                    case ohos_webview.PermissionRequest.videoCapture:
                      return WebViewPermissionResourceType.camera;
                    case ohos_webview.PermissionRequest.audioCapture:
                      return WebViewPermissionResourceType.microphone;
                    case ohos_webview.PermissionRequest.midiSysex:
                      return OhosWebViewPermissionResourceType.midiSysex;
                    case ohos_webview.PermissionRequest.protectedMediaId:
                      return OhosWebViewPermissionResourceType
                          .protectedMediaId;
                  }

                  // Type not supported.
                  return null;
                })
                .whereType<WebViewPermissionResourceType>()
                .toSet();

            // If the request didn't contain any permissions recognized by the
            // implementation, deny by default.
            if (types.isEmpty) {
              return request.deny();
            }

            callback(OhosWebViewPermissionRequest._(
              types: types,
              request: request,
            ));
          }
        };
      },
    ),
    onJsAlert: withWeakReferenceTo(this,
        (WeakReference<OhosWebViewController> weakReference) {
      return (String url, String message) async {
        final Future<void> Function(JavaScriptAlertDialogRequest)? callback =
            weakReference.target?._onJavaScriptAlert;
        if (callback != null) {
          final JavaScriptAlertDialogRequest request =
              JavaScriptAlertDialogRequest(message: message, url: url);

          await callback.call(request);
        }
        return;
      };
    }),
    onJsConfirm: withWeakReferenceTo(this,
        (WeakReference<OhosWebViewController> weakReference) {
      return (String url, String message) async {
        final Future<bool> Function(JavaScriptConfirmDialogRequest)? callback =
            weakReference.target?._onJavaScriptConfirm;
        if (callback != null) {
          final JavaScriptConfirmDialogRequest request =
              JavaScriptConfirmDialogRequest(message: message, url: url);
          final bool result = await callback.call(request);
          return result;
        }
        return false;
      };
    }),
    onJsPrompt: withWeakReferenceTo(this,
        (WeakReference<OhosWebViewController> weakReference) {
      return (String url, String message, String defaultValue) async {
        final Future<String> Function(JavaScriptTextInputDialogRequest)?
            callback = weakReference.target?._onJavaScriptPrompt;
        if (callback != null) {
          final JavaScriptTextInputDialogRequest request =
              JavaScriptTextInputDialogRequest(
                  message: message, url: url, defaultText: defaultValue);
          final String result = await callback.call(request);
          return result;
        }
        return '';
      };
    }),
  );

  /// The native [ohos_webview.FlutterAssetManager] allows managing assets.
  late final ohos_webview.FlutterAssetManager _flutterAssetManager =
      _ohosWebViewParams.ohosWebViewProxy.createFlutterAssetManager();

  final Map<String, OhosJavaScriptChannelParams> _javaScriptChannelParams =
      <String, OhosJavaScriptChannelParams>{};

  OhosNavigationDelegate? _currentNavigationDelegate;

  Future<List<String>> Function(FileSelectorParams)?
      _onShowFileSelectorCallback;

  OnGeolocationPermissionsShowPrompt? _onGeolocationPermissionsShowPrompt;

  OnGeolocationPermissionsHidePrompt? _onGeolocationPermissionsHidePrompt;

  OnShowCustomWidgetCallback? _onShowCustomWidgetCallback;

  OnHideCustomWidgetCallback? _onHideCustomWidgetCallback;

  void Function(PlatformWebViewPermissionRequest)? _onPermissionRequestCallback;

  void Function(JavaScriptConsoleMessage consoleMessage)? _onConsoleLogCallback;

  Future<void> Function(JavaScriptAlertDialogRequest request)?
      _onJavaScriptAlert;
  Future<bool> Function(JavaScriptConfirmDialogRequest request)?
      _onJavaScriptConfirm;
  Future<String> Function(JavaScriptTextInputDialogRequest request)?
      _onJavaScriptPrompt;

  void Function(ScrollPositionChange scrollPositionChange)?
      _onScrollPositionChangedCallback;

  /// Whether to enable the platform's webview content debugging tools.
  ///
  /// Defaults to false.
  static Future<void> enableDebugging(
    bool enabled, {
    @visibleForTesting
    OhosWebViewProxy webViewProxy = const OhosWebViewProxy(),
  }) {
    return webViewProxy.setWebContentsDebuggingEnabled(enabled);
  }

  /// Identifier used to retrieve the underlying native `WKWebView`.
  ///
  /// This is typically used by other plugins to retrieve the native `WebView`
  /// from an `InstanceManager`.
  ///
  /// See TS method `WebViewFlutterPlugin.getWebView`.
  int get webViewIdentifier =>
      // ignore: invalid_use_of_visible_for_testing_member
      ohos_webview.WebView.api.instanceManager.getIdentifier(_webView)!;

  @override
  Future<void> loadFile(
    String absoluteFilePath,
  ) {
    final String url = absoluteFilePath.startsWith('file://')
        ? absoluteFilePath
        : Uri.file(absoluteFilePath).toString();

    _webView.settings.setAllowFileAccess(true);
    return _webView.loadUrl(url, <String, String>{});
  }

  @override
  Future<void> loadFlutterAsset(
    String key,
  ) async {
    final String assetFilePath =
        await _flutterAssetManager.getAssetFilePathByName(key);
    final List<String> pathElements = assetFilePath.split('/');
    final String fileName = pathElements.removeLast();
    final List<String?> paths =
        await _flutterAssetManager.list(pathElements.join('/'));

    if (!paths.contains(fileName)) {
      throw ArgumentError(
        'Asset for key "$key" not found.',
        'key',
      );
    }
    _webView.settings.setAllowFileAccess(true);
    final String url = "resources/rawfile/" + assetFilePath;
    return _webView.loadUrl(url, <String, String>{});
  }

  @override
  Future<void> loadHtmlString(
    String html, {
    String? baseUrl,
  }) {
    return _webView.loadDataWithBaseUrl(
        baseUrl: baseUrl, data: html, mimeType: 'text/html', encoding: 'UTF-8');
  }

  @override
  Future<void> loadRequest(
    LoadRequestParams params,
  ) {
    if (!params.uri.hasScheme) {
      throw ArgumentError('WebViewRequest#uri is required to have a scheme.');
    }
    switch (params.method) {
      case LoadRequestMethod.get:
        return _webView.loadUrl(params.uri.toString(), params.headers);
      case LoadRequestMethod.post:
        return _webView.postUrl(
            params.uri.toString(), params.body ?? Uint8List(0));
    }
    // The enum comes from a different package, which could get a new value at
    // any time, so a fallback case is necessary. Since there is no reasonable
    // default behavior, throw to alert the client that they need an updated
    // version. This is deliberately outside the switch rather than a `default`
    // so that the linter will flag the switch as needing an update.
    // ignore: dead_code
    throw UnimplementedError(
        'This version of `OhosWebViewController` currently has no '
        'implementation for HTTP method ${params.method.serialize()} in '
        'loadRequest.');
  }

  @override
  Future<String?> currentUrl() => _webView.getUrl();

  @override
  Future<bool> canGoBack() => _webView.canGoBack();

  @override
  Future<bool> canGoForward() => _webView.canGoForward();

  @override
  Future<void> goBack() => _webView.goBack();

  @override
  Future<void> goForward() => _webView.goForward();

  @override
  Future<void> reload() => _webView.reload();

  @override
  Future<void> clearCache() => _webView.clearCache(true);

  @override
  Future<void> clearLocalStorage() =>
      _ohosWebViewParams.ohosWebStorage.deleteAllData();

  @override
  Future<void> setPlatformNavigationDelegate(
      covariant OhosNavigationDelegate handler) async {
    _currentNavigationDelegate = handler;
    await Future.wait(<Future<void>>[
      handler.setOnLoadRequest(loadRequest),
      _webView.setWebViewClient(handler.ohosWebViewClient),
      _webView.setDownloadListener(handler.ohosDownloadListener),
    ]);
  }

  @override
  Future<void> runJavaScript(String javaScript) {
    return _webView.evaluateJavascript(javaScript);
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    final String? result = await _webView.evaluateJavascript(javaScript);

    if (result == null) {
      return '';
    } else if (result == 'true') {
      return true;
    } else if (result == 'false') {
      return false;
    }

    return num.tryParse(result) ?? result;
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) {
    final OhosJavaScriptChannelParams ohosJavaScriptParams =
        javaScriptChannelParams is OhosJavaScriptChannelParams
            ? javaScriptChannelParams
            : OhosJavaScriptChannelParams.fromJavaScriptChannelParams(
                javaScriptChannelParams);

    // When JavaScript channel with the same name exists make sure to remove it
    // before registering the new channel.
    if (_javaScriptChannelParams.containsKey(ohosJavaScriptParams.name)) {
      _webView.removeJavaScriptChannel(ohosJavaScriptParams._javaScriptChannel);
    }

    _javaScriptChannelParams[ohosJavaScriptParams.name] = ohosJavaScriptParams;

    return _webView
        .addJavaScriptChannel(ohosJavaScriptParams._javaScriptChannel);
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    final OhosJavaScriptChannelParams? javaScriptChannelParams =
        _javaScriptChannelParams[javaScriptChannelName];
    if (javaScriptChannelParams == null) {
      return;
    }

    _javaScriptChannelParams.remove(javaScriptChannelName);
    return _webView
        .removeJavaScriptChannel(javaScriptChannelParams._javaScriptChannel);
  }

  @override
  Future<String?> getTitle() => _webView.getTitle();

  @override
  Future<void> scrollTo(int x, int y) => _webView.scrollTo(x, y);

  @override
  Future<void> scrollBy(int x, int y) => _webView.scrollBy(x, y);

  @override
  Future<Offset> getScrollPosition() {
    return _webView.getScrollPosition();
  }

  @override
  Future<void> enableZoom(bool enabled) =>
      _webView.settings.setSupportZoom(enabled);

  @override
  Future<void> setBackgroundColor(Color color) =>
      _webView.settings.setBackgroundColor(color);

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) =>
      _webView.settings
          .setJavaScriptEnabled(javaScriptMode == JavaScriptMode.unrestricted);

  @override
  Future<void> setUserAgent(String? userAgent) =>
      _webView.settings.setUserAgentString(userAgent);

  @override
  Future<void> setOnScrollPositionChange(
      void Function(ScrollPositionChange scrollPositionChange)?
          onScrollPositionChange) async {
    _onScrollPositionChangedCallback = onScrollPositionChange;
  }

  /// Sets the restrictions that apply on automatic media playback.
  Future<void> setMediaPlaybackRequiresUserGesture(bool require) {
    return _webView.settings.setMediaPlaybackRequiresUserGesture(require);
  }

  /// Sets the text zoom of the page in percent.
  ///
  /// The default is 100.
  Future<void> setTextZoom(int textZoom) =>
      _webView.settings.setTextZoom(textZoom);

  /// Sets the callback that is invoked when the client should show a file
  /// selector.
  Future<void> setOnShowFileSelector(
    Future<List<String>> Function(FileSelectorParams params)?
        onShowFileSelector,
  ) {
    _onShowFileSelectorCallback = onShowFileSelector;
    return _webChromeClient.setSynchronousReturnValueForOnShowFileChooser(
      onShowFileSelector != null,
    );
  }

  /// Sets a callback that notifies the host application that web content is
  /// requesting permission to access the specified resources.
  ///
  /// Only invoked on Ohos versions 21+.
  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(
      PlatformWebViewPermissionRequest request,
    ) onPermissionRequest,
  ) async {
    _onPermissionRequestCallback = onPermissionRequest;
  }

  /// Sets the callback that is invoked when the client request handle geolocation permissions.
  ///
  /// Param [onShowPrompt] notifies the host application that web content from the specified origin is attempting to use the Geolocation API,
  /// but no permission state is currently set for that origin.
  ///
  /// The host application should invoke the specified callback with the desired permission state.
  /// See GeolocationPermissions for details.
  ///
  /// Note that for applications targeting Ohos N and later SDKs (API level > Build.VERSION_CODES.M)
  /// this method is only called for requests originating from secure origins such as https.
  /// On non-secure origins geolocation requests are automatically denied.
  ///
  /// Param [onHidePrompt] notifies the host application that a request for Geolocation permissions,
  /// made with a previous call to onGeolocationPermissionsShowPrompt() has been canceled.
  /// Any related UI should therefore be hidden.
  Future<void> setGeolocationPermissionsPromptCallbacks({
    OnGeolocationPermissionsShowPrompt? onShowPrompt,
    OnGeolocationPermissionsHidePrompt? onHidePrompt,
  }) async {
    _onGeolocationPermissionsShowPrompt = onShowPrompt;
    _onGeolocationPermissionsHidePrompt = onHidePrompt;
  }

  /// Sets the callbacks that are invoked when the host application wants to
  /// show or hide a custom widget.
  ///
  /// The most common use case these methods are invoked a video element wants
  /// to be displayed in fullscreen.
  ///
  /// The [onShowCustomWidget] notifies the host application that web content
  /// from the specified origin wants to be displayed in a custom widget. After
  /// this call, web content will no longer be rendered in the `WebViewWidget`,
  /// but will instead be rendered in the custom widget. The application may
  /// explicitly exit fullscreen mode by invoking `onCustomWidgetHidden` in the
  /// [onShowCustomWidget] callback (ex. when the user presses the back
  /// button). However, this is generally not necessary as the web page will
  /// often show its own UI to close out of fullscreen. Regardless of how the
  /// WebView exits fullscreen mode, WebView will invoke [onHideCustomWidget],
  /// signaling for the application to remove the custom widget. If this value
  /// is `null` when passed to an `AndroidWebViewWidget`, a default handler
  /// will be set.
  ///
  /// The [onHideCustomWidget] notifies the host application that the custom
  /// widget must be hidden. After this call, web content will render in the
  /// original `WebViewWidget` again.
  Future<void> setCustomWidgetCallbacks({
    required OnShowCustomWidgetCallback? onShowCustomWidget,
    required OnHideCustomWidgetCallback? onHideCustomWidget,
  }) async {
    _onShowCustomWidgetCallback = onShowCustomWidget;
    _onHideCustomWidgetCallback = onHideCustomWidget;
  }

  /// Sets a callback that notifies the host application of any log messages
  /// written to the JavaScript console.
  @override
  Future<void> setOnConsoleMessage(
      void Function(JavaScriptConsoleMessage consoleMessage)
          onConsoleMessage) async {
    _onConsoleLogCallback = onConsoleMessage;

    return _webChromeClient.setSynchronousReturnValueForOnConsoleMessage(
        _onConsoleLogCallback != null);
  }

  @override
  Future<String?> getUserAgent() => _webView.settings.getUserAgentString();

  @override
  Future<void> setOnJavaScriptAlertDialog(
      Future<void> Function(JavaScriptAlertDialogRequest request)
          onJavaScriptAlertDialog) async {
    _onJavaScriptAlert = onJavaScriptAlertDialog;
    return _webChromeClient.setSynchronousReturnValueForOnJsAlert(true);
  }

  @override
  Future<void> setOnJavaScriptConfirmDialog(
      Future<bool> Function(JavaScriptConfirmDialogRequest request)
          onJavaScriptConfirmDialog) async {
    _onJavaScriptConfirm = onJavaScriptConfirmDialog;
    return _webChromeClient.setSynchronousReturnValueForOnJsConfirm(true);
  }

  @override
  Future<void> setOnJavaScriptTextInputDialog(
      Future<String> Function(JavaScriptTextInputDialogRequest request)
          onJavaScriptTextInputDialog) async {
    _onJavaScriptPrompt = onJavaScriptTextInputDialog;
    return _webChromeClient.setSynchronousReturnValueForOnJsPrompt(true);
  }
}

/// Ohos implementation of [PlatformWebViewPermissionRequest].
class OhosWebViewPermissionRequest extends PlatformWebViewPermissionRequest {
  const OhosWebViewPermissionRequest._({
    required super.types,
    required ohos_webview.PermissionRequest request,
  }) : _request = request;

  final ohos_webview.PermissionRequest _request;

  @override
  Future<void> grant() {
    return _request
        .grant(types.map<String>((WebViewPermissionResourceType type) {
      switch (type) {
        case WebViewPermissionResourceType.camera:
          return ohos_webview.PermissionRequest.videoCapture;
        case WebViewPermissionResourceType.microphone:
          return ohos_webview.PermissionRequest.audioCapture;
        case OhosWebViewPermissionResourceType.midiSysex:
          return ohos_webview.PermissionRequest.midiSysex;
        case OhosWebViewPermissionResourceType.protectedMediaId:
          return ohos_webview.PermissionRequest.protectedMediaId;
      }

      throw UnsupportedError(
        'Resource of type `${type.name}` is not supported.',
      );
    }).toList());
  }

  @override
  Future<void> deny() {
    return _request.deny();
  }
}

/// Signature for the `setGeolocationPermissionsPromptCallbacks` callback responsible for request the Geolocation API.
typedef OnGeolocationPermissionsShowPrompt
    = Future<GeolocationPermissionsResponse> Function(
        GeolocationPermissionsRequestParams request);

/// Signature for the `setGeolocationPermissionsPromptCallbacks` callback responsible for request the Geolocation API is cancel.
typedef OnGeolocationPermissionsHidePrompt = void Function();

/// Signature for the `setCustomWidgetCallbacks` callback responsible for showing the custom view.
typedef OnShowCustomWidgetCallback = void Function(
    Widget widget, void Function() onCustomWidgetHidden);

/// Signature for the `setCustomWidgetCallbacks` callback responsible for hiding the custom view.
typedef OnHideCustomWidgetCallback = void Function();

/// A request params used by the host application to set the Geolocation permission state for an origin.
@immutable
class GeolocationPermissionsRequestParams {
  /// [origin]: The origin for which permissions are set.
  const GeolocationPermissionsRequestParams({
    required this.origin,
  });

  /// [origin]: The origin for which permissions are set.
  final String origin;
}

/// A response used by the host application to set the Geolocation permission state for an origin.
@immutable
class GeolocationPermissionsResponse {
  /// [allow]: Whether or not the origin should be allowed to use the Geolocation API.
  ///
  /// [retain]: Whether the permission should be retained beyond the lifetime of
  /// a page currently being displayed by a WebView.
  const GeolocationPermissionsResponse({
    required this.allow,
    required this.retain,
  });

  /// Whether or not the origin should be allowed to use the Geolocation API.
  final bool allow;

  /// Whether the permission should be retained beyond the lifetime of
  /// a page currently being displayed by a WebView.
  final bool retain;
}

/// Mode of how to select files for a file chooser.
enum FileSelectorMode {
  /// Open single file and requires that the file exists before allowing the
  /// user to pick it.
  open,

  /// Similar to [open] but allows multiple files to be selected.
  openMultiple,

  /// Allows picking a nonexistent file and saving it.
  save,
}

/// Parameters received when the `WebView` should show a file selector.
@immutable
class FileSelectorParams {
  /// Constructs a [FileSelectorParams].
  const FileSelectorParams({
    required this.isCaptureEnabled,
    required this.acceptTypes,
    this.filenameHint,
    required this.mode,
  });

  factory FileSelectorParams._fromFileChooserParams(
    ohos_webview.FileChooserParams params,
  ) {
    final FileSelectorMode mode;
    switch (params.mode) {
      case ohos_webview.FileChooserMode.open:
        mode = FileSelectorMode.open;
        break;
      case ohos_webview.FileChooserMode.openMultiple:
        mode = FileSelectorMode.openMultiple;
        break;
      case ohos_webview.FileChooserMode.save:
        mode = FileSelectorMode.save;
        break;
    }

    return FileSelectorParams(
      isCaptureEnabled: params.isCaptureEnabled,
      acceptTypes: params.acceptTypes,
      mode: mode,
      filenameHint: params.filenameHint,
    );
  }

  /// Preference for a live media captured value (e.g. Camera, Microphone).
  final bool isCaptureEnabled;

  /// A list of acceptable MIME types.
  final List<String> acceptTypes;

  /// The file name of a default selection if specified, or null.
  final String? filenameHint;

  /// Mode of how to select files for a file selector.
  final FileSelectorMode mode;
}

/// An implementation of [JavaScriptChannelParams] with the Ohos WebView API.
///
/// See [OhosWebViewController.addJavaScriptChannel].
@immutable
class OhosJavaScriptChannelParams extends JavaScriptChannelParams {
  /// Constructs a [OhosJavaScriptChannelParams].
  OhosJavaScriptChannelParams({
    required super.name,
    required super.onMessageReceived,
    @visibleForTesting OhosWebViewProxy webViewProxy = const OhosWebViewProxy(),
  })  : assert(name.isNotEmpty),
        _javaScriptChannel = webViewProxy.createJavaScriptChannel(
          name,
          postMessage: withWeakReferenceTo(
            onMessageReceived,
            (WeakReference<void Function(JavaScriptMessage)> weakReference) {
              return (
                String message,
              ) {
                if (weakReference.target != null) {
                  weakReference.target!(
                    JavaScriptMessage(message: message),
                  );
                }
              };
            },
          ),
        );

  /// Constructs a [OhosJavaScriptChannelParams] using a
  /// [JavaScriptChannelParams].
  OhosJavaScriptChannelParams.fromJavaScriptChannelParams(
    JavaScriptChannelParams params, {
    @visibleForTesting OhosWebViewProxy webViewProxy = const OhosWebViewProxy(),
  }) : this(
          name: params.name,
          onMessageReceived: params.onMessageReceived,
          webViewProxy: webViewProxy,
        );

  final ohos_webview.JavaScriptChannel _javaScriptChannel;
}

/// Object specifying creation parameters for creating a [OhosWebViewWidget].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformWebViewWidgetCreationParams] for
/// more information.
@immutable
class OhosWebViewWidgetCreationParams
    extends PlatformWebViewWidgetCreationParams {
  /// Creates [OhosWebWidgetCreationParams].
  OhosWebViewWidgetCreationParams({
    super.key,
    required super.controller,
    super.layoutDirection,
    super.gestureRecognizers,
    this.displayWithHybridComposition = false,
    @visibleForTesting InstanceManager? instanceManager,
    @visibleForTesting
    this.platformViewsServiceProxy = const PlatformViewsServiceProxy(),
  }) : instanceManager =
            instanceManager ?? ohos_webview.OhosObject.globalInstanceManager;

  /// Constructs a [WebKitWebViewWidgetCreationParams] using a
  /// [PlatformWebViewWidgetCreationParams].
  OhosWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
    PlatformWebViewWidgetCreationParams params, {
    bool displayWithHybridComposition = false,
    @visibleForTesting InstanceManager? instanceManager,
    @visibleForTesting PlatformViewsServiceProxy platformViewsServiceProxy =
        const PlatformViewsServiceProxy(),
  }) : this(
          key: params.key,
          controller: params.controller,
          layoutDirection: params.layoutDirection,
          gestureRecognizers: params.gestureRecognizers,
          displayWithHybridComposition: displayWithHybridComposition,
          instanceManager: instanceManager,
          platformViewsServiceProxy: platformViewsServiceProxy,
        );

  /// Maintains instances used to communicate with the native objects they
  /// represent.
  ///
  /// This field is exposed for testing purposes only and should not be used
  /// outside of tests.
  @visibleForTesting
  final InstanceManager instanceManager;

  /// Proxy that provides access to the platform views service.
  ///
  /// This service allows creating and controlling platform-specific views.
  @visibleForTesting
  final PlatformViewsServiceProxy platformViewsServiceProxy;

  /// Whether the [WebView] will be displayed using the Hybrid Composition
  /// PlatformView implementation.
  ///
  /// For most use cases, this flag should be set to false. Hybrid Composition
  /// can have performance costs but doesn't have the limitation of rendering to
  /// an Ohos SurfaceTexture. See
  /// * https://flutter.dev/docs/development/platform-integration/platform-views#performance
  /// * https://github.com/flutter/flutter/issues/104889
  /// * https://github.com/flutter/flutter/issues/116954
  ///
  /// Defaults to false.
  final bool displayWithHybridComposition;

  @override
  int get hashCode => Object.hash(
        controller,
        layoutDirection,
        displayWithHybridComposition,
        platformViewsServiceProxy,
        instanceManager,
      );

  @override
  bool operator ==(Object other) {
    return other is OhosWebViewWidgetCreationParams &&
        controller == other.controller &&
        layoutDirection == other.layoutDirection &&
        displayWithHybridComposition == other.displayWithHybridComposition &&
        platformViewsServiceProxy == other.platformViewsServiceProxy &&
        instanceManager == other.instanceManager;
  }
}

/// An implementation of [PlatformWebViewWidget] with the Ohos WebView API.
class OhosWebViewWidget extends PlatformWebViewWidget {
  /// Constructs a [WebKitWebViewWidget].
  OhosWebViewWidget(PlatformWebViewWidgetCreationParams params)
      : super.implementation(
          params is OhosWebViewWidgetCreationParams
              ? params
              : OhosWebViewWidgetCreationParams
                  .fromPlatformWebViewWidgetCreationParams(params),
        );

  OhosWebViewWidgetCreationParams get _ohosParams =>
      params as OhosWebViewWidgetCreationParams;

  @override
  Widget build(BuildContext context) {
    _trySetDefaultOnShowCustomWidgetCallbacks(context);
    return PlatformViewLink(
      // Setting a default key using `params` ensures the `PlatformViewLink`
      // recreates the PlatformView when changes are made.
      key: _ohosParams.key ??
          ValueKey<OhosWebViewWidgetCreationParams>(
              params as OhosWebViewWidgetCreationParams),
      viewType: 'plugins.flutter.io/webview',
      surfaceFactory: (
          BuildContext context,
          PlatformViewController controller,
          ) {
        return OhosViewSurface(
          controller: controller as OhosViewController,
          gestureRecognizers: _ohosParams.gestureRecognizers,
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (PlatformViewCreationParams params) {
        return _initOhosView(
          params,
          displayWithHybridComposition:
          _ohosParams.displayWithHybridComposition,
        )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create();
      },
    );
  }

  OhosViewController _initOhosView(
      PlatformViewCreationParams params, {
        required bool displayWithHybridComposition,
      }) {
    if (displayWithHybridComposition) {
      return _ohosParams.platformViewsServiceProxy.initExpensiveOhosView(
        id: params.id,
        viewType: 'plugins.flutter.io/webview',
        layoutDirection: _ohosParams.layoutDirection,
        creationParams: _ohosParams.instanceManager.getIdentifier(
            (_ohosParams.controller as OhosWebViewController)._webView),
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else {
      return _ohosParams.platformViewsServiceProxy.initSurfaceOhosView(
        id: params.id,
        viewType: 'plugins.flutter.io/webview',
        layoutDirection: _ohosParams.layoutDirection,
        creationParams: _ohosParams.instanceManager.getIdentifier(
            (_ohosParams.controller as OhosWebViewController)._webView),
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
  }


  // Attempt to handle custom views with a default implementation if it has not
  // been set.
  void _trySetDefaultOnShowCustomWidgetCallbacks(BuildContext context) {
        final OhosWebViewController controller =
        _ohosParams.controller as OhosWebViewController;

    if (controller._onShowCustomWidgetCallback == null) {
      controller.setCustomWidgetCallbacks(
        onShowCustomWidget:
            (Widget widget, OnHideCustomWidgetCallback callback) {
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (BuildContext context) => widget,
            fullscreenDialog: true,
          ));
        },
        onHideCustomWidget: () {
          Navigator.of(context).pop();
        },
      );
    }
  }
}

/// Represents a Flutter implementation of the Android [View](https://developer.android.com/reference/android/view/View)
/// that is created by the host platform when web content needs to be displayed
/// in fullscreen mode.
///
/// The [OhosCustomViewWidget] cannot be manually instantiated and is
/// provided to the host application through the callbacks specified using the
/// [OhosWebViewController.setCustomWidgetCallbacks] method.
///
/// The [OhosCustomViewWidget] is initialized internally and should only be
/// exposed as a [Widget] externally. The type [OhosCustomViewWidget] is
/// visible for testing purposes only and should never be called externally.
@visibleForTesting
class OhosCustomViewWidget extends StatelessWidget {
  /// Creates a [OhosCustomViewWidget].
  ///
  /// The [OhosCustomViewWidget] should only be instantiated internally.
  /// This constructor is visible for testing purposes only and should
  /// never be called externally.
  @visibleForTesting
  OhosCustomViewWidget.private({
    super.key,
    required this.controller,
    required this.customView,
    @visibleForTesting InstanceManager? instanceManager,
    @visibleForTesting
    this.platformViewsServiceProxy = const PlatformViewsServiceProxy(),
  }) : instanceManager =
            instanceManager ?? ohos_webview.OhosObject.globalInstanceManager;

  /// The reference to the Android native view that should be shown.
  final ohos_webview.View customView;

  /// The [PlatformWebViewController] that allows controlling the native web
  /// view.
  final PlatformWebViewController controller;

  /// Maintains instances used to communicate with the native objects they
  /// represent.
  ///
  /// This field is exposed for testing purposes only and should not be used
  /// outside of tests.
  @visibleForTesting
  final InstanceManager instanceManager;

  /// Proxy that provides access to the platform views service.
  ///
  /// This service allows creating and controlling platform-specific views.
  @visibleForTesting
  final PlatformViewsServiceProxy platformViewsServiceProxy;

  OhosWebViewWidgetCreationParams get _ohosParams =>
      controller.params as OhosWebViewWidgetCreationParams;

  @override
  Widget build(BuildContext context) {
    return OhosView(
      key: _ohosParams.key ??
          ValueKey<OhosWebViewWidgetCreationParams>(_ohosParams),
      viewType: 'plugins.flutter.io/webview',
      layoutDirection: _ohosParams.layoutDirection,
      creationParams: _ohosParams.instanceManager.getIdentifier(
          (_ohosParams.controller as OhosWebViewController)._webView),
      creationParamsCodec: const StandardMessageCodec(),
      gestureRecognizers: _ohosParams.gestureRecognizers,
    );
  }

}

/// Signature for the `loadRequest` callback responsible for loading the [url]
/// after a navigation request has been approved.
typedef LoadRequestCallback = Future<void> Function(LoadRequestParams params);

/// Error returned in `WebView.onWebResourceError` when a web resource loading error has occurred.
@immutable
class OhosWebResourceError extends WebResourceError {
  /// Creates a new [OhosWebResourceError].
  OhosWebResourceError._({
    required super.errorCode,
    required super.description,
    super.isForMainFrame,
    super.url,
  })  : failingUrl = url,
        super(
          errorType: _errorCodeToErrorType(errorCode),
        );

  /// Gets the URL for which the failing resource request was made.
  @Deprecated('Please use `url`.')
  final String? failingUrl;

  static WebResourceErrorType? _errorCodeToErrorType(int errorCode) {
    switch (errorCode) {
      case ohos_webview.WebViewClient.errorAuthentication:
        return WebResourceErrorType.authentication;
      case ohos_webview.WebViewClient.errorBadUrl:
        return WebResourceErrorType.badUrl;
      case ohos_webview.WebViewClient.errorConnect:
        return WebResourceErrorType.connect;
      case ohos_webview.WebViewClient.errorFailedSslHandshake:
        return WebResourceErrorType.failedSslHandshake;
      case ohos_webview.WebViewClient.errorFile:
        return WebResourceErrorType.file;
      case ohos_webview.WebViewClient.errorFileNotFound:
        return WebResourceErrorType.fileNotFound;
      case ohos_webview.WebViewClient.errorHostLookup:
        return WebResourceErrorType.hostLookup;
      case ohos_webview.WebViewClient.errorIO:
        return WebResourceErrorType.io;
      case ohos_webview.WebViewClient.errorProxyAuthentication:
        return WebResourceErrorType.proxyAuthentication;
      case ohos_webview.WebViewClient.errorRedirectLoop:
        return WebResourceErrorType.redirectLoop;
      case ohos_webview.WebViewClient.errorTimeout:
        return WebResourceErrorType.timeout;
      case ohos_webview.WebViewClient.errorTooManyRequests:
        return WebResourceErrorType.tooManyRequests;
      case ohos_webview.WebViewClient.errorUnknown:
        return WebResourceErrorType.unknown;
      case ohos_webview.WebViewClient.errorUnsafeResource:
        return WebResourceErrorType.unsafeResource;
      case ohos_webview.WebViewClient.errorUnsupportedAuthScheme:
        return WebResourceErrorType.unsupportedAuthScheme;
      case ohos_webview.WebViewClient.errorUnsupportedScheme:
        return WebResourceErrorType.unsupportedScheme;
    }

    if (errorCode < 0) {
      return WebResourceErrorType.unknown;
    }

    throw ArgumentError(
      'Could not find a WebResourceErrorType for errorCode: $errorCode',
    );
  }
}

/// Object specifying creation parameters for creating a [OhosNavigationDelegate].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformNavigationDelegateCreationParams] for
/// more information.
@immutable
class OhosNavigationDelegateCreationParams
    extends PlatformNavigationDelegateCreationParams {
  /// Creates a new [OhosNavigationDelegateCreationParams] instance.
  const OhosNavigationDelegateCreationParams._({
    @visibleForTesting this.ohosWebViewProxy = const OhosWebViewProxy(),
  }) : super();

  /// Creates a [OhosNavigationDelegateCreationParams] instance based on [PlatformNavigationDelegateCreationParams].
  factory OhosNavigationDelegateCreationParams.fromPlatformNavigationDelegateCreationParams(
    // Recommended placeholder to prevent being broken by platform interface.
    // ignore: avoid_unused_constructor_parameters
    PlatformNavigationDelegateCreationParams params, {
    @visibleForTesting
    OhosWebViewProxy ohosWebViewProxy = const OhosWebViewProxy(),
  }) {
    return OhosNavigationDelegateCreationParams._(
      ohosWebViewProxy: ohosWebViewProxy,
    );
  }

  /// Handles constructing objects and calling static methods for the Ohos WebView
  /// native library.
  @visibleForTesting
  final OhosWebViewProxy ohosWebViewProxy;
}

/// Ohos details of the change to a web view's url.
class OhosUrlChange extends UrlChange {
  /// Constructs an [OhosUrlChange].
  const OhosUrlChange({required super.url, required this.isReload});

  /// Whether the url is being reloaded.
  final bool isReload;
}

/// A place to register callback methods responsible to handle navigation events
/// triggered by the [ohos_webview.WebView].
class OhosNavigationDelegate extends PlatformNavigationDelegate {
  /// Creates a new [OhosNavigationDelegate].
  OhosNavigationDelegate(PlatformNavigationDelegateCreationParams params)
      : super.implementation(params is OhosNavigationDelegateCreationParams
            ? params
            : OhosNavigationDelegateCreationParams
                .fromPlatformNavigationDelegateCreationParams(params)) {
    final WeakReference<OhosNavigationDelegate> weakThis =
        WeakReference<OhosNavigationDelegate>(this);

    _webViewClient = (this.params as OhosNavigationDelegateCreationParams)
        .ohosWebViewProxy
        .createOhosWebViewClient(
      onPageFinished: (ohos_webview.WebView webView, String url) {
        final PageEventCallback? callback = weakThis.target?._onPageFinished;
        if (callback != null) {
          callback(url);
        }
      },
      onPageStarted: (ohos_webview.WebView webView, String url) {
        final PageEventCallback? callback = weakThis.target?._onPageStarted;
        if (callback != null) {
          callback(url);
        }
      },
      onReceivedRequestError: (
        ohos_webview.WebView webView,
        ohos_webview.WebResourceRequest request,
        ohos_webview.WebResourceError error,
      ) {
        final WebResourceErrorCallback? callback =
            weakThis.target?._onWebResourceError;
        if (callback != null) {
          callback(OhosWebResourceError._(
            errorCode: error.errorCode,
            description: error.description,
            url: request.url,
            isForMainFrame: request.isForMainFrame,
          ));
        }
      },
      onReceivedError: (
        ohos_webview.WebView webView,
        int errorCode,
        String description,
        String failingUrl,
      ) {
        final WebResourceErrorCallback? callback =
            weakThis.target?._onWebResourceError;
        if (callback != null) {
          callback(OhosWebResourceError._(
            errorCode: errorCode,
            description: description,
            url: failingUrl,
            isForMainFrame: true,
          ));
        }
      },
      requestLoading: (
        ohos_webview.WebView webView,
        ohos_webview.WebResourceRequest request,
      ) {
        weakThis.target?._handleNavigation(
          request.url,
          headers: request.requestHeaders,
          isForMainFrame: request.isForMainFrame,
        );
      },
      urlLoading: (ohos_webview.WebView webView, String url) {
        weakThis.target?._handleNavigation(url, isForMainFrame: true);
      },
      doUpdateVisitedHistory: (
        ohos_webview.WebView webView,
        String url,
        bool isReload,
      ) {
        final UrlChangeCallback? callback = weakThis.target?._onUrlChange;
        if (callback != null) {
          callback(OhosUrlChange(url: url, isReload: isReload));
        }
      },
      onReceivedHttpAuthRequest: (
        ohos_webview.WebView webView,
        ohos_webview.HttpAuthHandler httpAuthHandler,
        String host,
        String realm,
      ) {
        final void Function(HttpAuthRequest)? callback =
            weakThis.target?._onHttpAuthRequest;
        if (callback != null) {
          callback(
            HttpAuthRequest(
              onProceed: (WebViewCredential credential) {
                httpAuthHandler.proceed(credential.user, credential.password);
              },
              onCancel: () {
                httpAuthHandler.cancel();
              },
              host: host,
              realm: realm,
            ),
          );
        } else {
          httpAuthHandler.cancel();
        }
      },
    );

    _downloadListener = (this.params as OhosNavigationDelegateCreationParams)
        .ohosWebViewProxy
        .createDownloadListener(
      onDownloadStart: (
        String url,
        String userAgent,
        String contentDisposition,
        String mimetype,
        int contentLength,
      ) {
        if (weakThis.target != null) {
          weakThis.target?._handleNavigation(url, isForMainFrame: true);
        }
      },
    );
  }

  OhosNavigationDelegateCreationParams get _ohosParams =>
      params as OhosNavigationDelegateCreationParams;

  late final ohos_webview.WebChromeClient _webChromeClient =
      _ohosParams.ohosWebViewProxy.createOhosWebChromeClient();

  /// Gets the native [ohos_webview.WebChromeClient] that is bridged by this [OhosNavigationDelegate].
  ///
  /// Used by the [OhosWebViewController] to set the `ohos_webview.WebView.setWebChromeClient`.
  @Deprecated(
    'This value is not used by `OhosWebViewController` and has no effect on the `WebView`.',
  )
  ohos_webview.WebChromeClient get ohosWebChromeClient => _webChromeClient;

  late final ohos_webview.WebViewClient _webViewClient;

  /// Gets the native [ohos_webview.WebViewClient] that is bridged by this [OhosNavigationDelegate].
  ///
  /// Used by the [OhosWebViewController] to set the `ohos_webview.WebView.setWebViewClient`.
  ohos_webview.WebViewClient get ohosWebViewClient => _webViewClient;

  late final ohos_webview.DownloadListener _downloadListener;

  /// Gets the native [ohos_webview.DownloadListener] that is bridged by this [OhosNavigationDelegate].
  ///
  /// Used by the [OhosWebViewController] to set the `ohos_webview.WebView.setDownloadListener`.
  ohos_webview.DownloadListener get ohosDownloadListener => _downloadListener;

  PageEventCallback? _onPageFinished;
  PageEventCallback? _onPageStarted;
  ProgressCallback? _onProgress;
  WebResourceErrorCallback? _onWebResourceError;
  NavigationRequestCallback? _onNavigationRequest;
  LoadRequestCallback? _onLoadRequest;
  UrlChangeCallback? _onUrlChange;
  HttpAuthRequestCallback? _onHttpAuthRequest;

  void _handleNavigation(
    String url, {
    required bool isForMainFrame,
    Map<String, String> headers = const <String, String>{},
  }) {
    final LoadRequestCallback? onLoadRequest = _onLoadRequest;
    final NavigationRequestCallback? onNavigationRequest = _onNavigationRequest;

    if (onNavigationRequest == null || onLoadRequest == null) {
      return;
    }

    final FutureOr<NavigationDecision> returnValue = onNavigationRequest(
      NavigationRequest(
        url: url,
        isMainFrame: isForMainFrame,
      ),
    );

    if (returnValue is NavigationDecision &&
        returnValue == NavigationDecision.navigate) {
      onLoadRequest(LoadRequestParams(
        uri: Uri.parse(url),
        headers: headers,
      ));
    } else if (returnValue is Future<NavigationDecision>) {
      returnValue.then((NavigationDecision shouldLoadUrl) {
        if (shouldLoadUrl == NavigationDecision.navigate) {
          onLoadRequest(LoadRequestParams(
            uri: Uri.parse(url),
            headers: headers,
          ));
        }
      });
    }
  }

  /// Invoked when loading the url after a navigation request is approved.
  Future<void> setOnLoadRequest(
    LoadRequestCallback onLoadRequest,
  ) async {
    _onLoadRequest = onLoadRequest;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    _onNavigationRequest = onNavigationRequest;
    return _webViewClient
        .setSynchronousReturnValueForShouldOverrideUrlLoading(true);
  }

  @override
  Future<void> setOnPageStarted(
    PageEventCallback onPageStarted,
  ) async {
    _onPageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(
    PageEventCallback onPageFinished,
  ) async {
    _onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnProgress(
    ProgressCallback onProgress,
  ) async {
    _onProgress = onProgress;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    _onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {
    _onUrlChange = onUrlChange;
  }

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {
    _onHttpAuthRequest = onHttpAuthRequest;
  }
}
