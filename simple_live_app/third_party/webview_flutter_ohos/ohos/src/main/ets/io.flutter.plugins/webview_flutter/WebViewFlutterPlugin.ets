// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on WebViewFlutterPlugin.java originally written by
// Copyright 2013 The Flutter Authors.

import { FlutterPluginBinding, FlutterPlugin } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import PluginRegistry from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/PluginRegistry';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import PlatformViewRegistry from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformViewRegistry';
import { OhosObjectHostApiImpl } from './OhosObjectHostApiImpl';
import { CookieManagerHostApiImpl } from './CookieManagerHostApiImpl';
import { CustomViewCallbackHostApiImpl } from './CustomViewCallbackHostApiImpl';
import { DownloadListenerFlutterApiImpl } from './DownloadListenerFlutterApiImpl';
import { DownloadListenerCreator, DownloadListenerHostApiImpl } from './DownloadListenerHostApiImpl';
import { FlutterAssetManager, PluginBindingFlutterAssetManager } from './FlutterAssetManager';
import { FlutterAssetManagerHostApiImpl } from './FlutterAssetManagerHostApiImpl';
import GeneratedOhosWebView, {
  CookieManagerHostApi,
  CustomViewCallbackHostApi,
  DownloadListenerHostApi,
  FlutterAssetManagerHostApi,
  GeolocationPermissionsCallbackHostApi,
  HttpAuthHandlerHostApi,
  InstanceManagerHostApi,
  JavaScriptChannelHostApi,
  PermissionRequestHostApi,
  OhosObjectFlutterApi,
  OhosObjectHostApi,
  WebViewHostApi,
  InstanceManagerApi,
  WebViewClientHostApi,
  WebChromeClientHostApi,
  WebSettingsHostApi,
  WebStorageHostApi
} from './GeneratedOhosWebView';
import { GeolocationPermissionsCallbackHostApiImpl } from './GeolocationPermissionsCallbackHostApiImpl';
import { HttpAuthHandlerHostApiImpl } from './HttpAuthHandlerHostApiImpl';
import { InstanceManager } from './InstanceManager';
import { JavaScriptChannelCreator, JavaScriptChannelHostApiImpl } from './JavaScriptChannelHostApiImpl';
import { PermissionRequestHostApiImpl } from './PermissionRequestHostApiImpl';
import { WebViewHostApiImpl, WebViewProxy } from './WebViewHostApiImpl';
import { FlutterWebViewFactory } from './FlutterWebViewFactory';
import { JavaScriptChannelFlutterApiImpl } from './JavaScriptChannelFlutterApiImpl';
import { WebViewClientCreator, WebViewClientHostApiImpl } from './WebViewClientHostApiImpl';
import { WebViewClientFlutterApiImpl } from './WebViewClientFlutterApiImpl';
import { WebChromeClientCreator, WebChromeClientHostApiImpl } from './WebChromeClientHostApiImpl';
import { WebChromeClientFlutterApiImpl } from './WebChromeClientFlutterApiImpl';
import { WebSettingsCreator, WebSettingsHostApiImpl } from './WebSettingsHostApiImpl';
import { WebStorageHostApiImpl } from './WebStorageHostApiImpl';

const TAG:string = "WebViewFlutterPlugin";
export class WebViewFlutterPlugin implements FlutterPlugin {
  getUniqueClassName(): string {
    return TAG;
  }

  private instanceManager: InstanceManager|null = null;

  setUp(
    binaryMessenger: BinaryMessenger, viewRegistry: PlatformViewRegistry, context: Context,
    flutterAssetManager: FlutterAssetManager
  ) {
    this.instanceManager = new InstanceManager({
      onFinalize: (identifier: number) => {
        new OhosObjectFlutterApi(binaryMessenger).dispose(
          identifier, { reply: () => {
        } }
        )
      }
    })

    InstanceManagerHostApi.setup(
      binaryMessenger,
      {
        clear: () => {
          if(this.instanceManager)
            this.instanceManager.clear();
        }
      }
    );
    viewRegistry.registerViewFactory(
      "plugins.flutter.io/webview", new FlutterWebViewFactory(this.instanceManager)
    );

    let webViewHostApi: WebViewHostApi =
      new WebViewHostApiImpl(
        this.instanceManager, new WebViewProxy(), binaryMessenger, context);
    let javaScriptChannelHostApi: JavaScriptChannelHostApi =
      new JavaScriptChannelHostApiImpl(
        this.instanceManager,
        new JavaScriptChannelCreator(),
        new JavaScriptChannelFlutterApiImpl(binaryMessenger, this.instanceManager),
      );

    OhosObjectHostApi.setup(binaryMessenger, new OhosObjectHostApiImpl(this.instanceManager));

    WebViewHostApi.setup(binaryMessenger, webViewHostApi);

    JavaScriptChannelHostApi.setup(binaryMessenger, javaScriptChannelHostApi);

    WebViewClientHostApi.setup(
      binaryMessenger,
      new WebViewClientHostApiImpl(
        this.instanceManager,
        new WebViewClientCreator(),
        new WebViewClientFlutterApiImpl(binaryMessenger, this.instanceManager))
    );

    WebChromeClientHostApi.setup(
      binaryMessenger,
      new WebChromeClientHostApiImpl(
        this.instanceManager,
        new WebChromeClientCreator(),
        new WebChromeClientFlutterApiImpl(binaryMessenger, this.instanceManager))
    );

    DownloadListenerHostApi.setup(
      binaryMessenger,
      new DownloadListenerHostApiImpl(
        this.instanceManager,
        new DownloadListenerCreator(),
        new DownloadListenerFlutterApiImpl(binaryMessenger, this.instanceManager))
    );

    WebSettingsHostApi.setup(
      binaryMessenger,
      new WebSettingsHostApiImpl(
        this.instanceManager, new WebSettingsCreator())
    );

    FlutterAssetManagerHostApi.setup(
      binaryMessenger, new FlutterAssetManagerHostApiImpl(flutterAssetManager)
    );

    CookieManagerHostApi.setup(
      binaryMessenger, new CookieManagerHostApiImpl(binaryMessenger, this.instanceManager)
    );

    WebStorageHostApi.setup(
      binaryMessenger,
      new WebStorageHostApiImpl()
    );

    PermissionRequestHostApi.setup(
      binaryMessenger, new PermissionRequestHostApiImpl(binaryMessenger, this.instanceManager)
    );

    GeolocationPermissionsCallbackHostApi.setup(
      binaryMessenger,
      new GeolocationPermissionsCallbackHostApiImpl(binaryMessenger, this.instanceManager)
    );
    CustomViewCallbackHostApi.setup(
      binaryMessenger, new CustomViewCallbackHostApiImpl(binaryMessenger, this.instanceManager));
    HttpAuthHandlerHostApi.setup(
      binaryMessenger, new HttpAuthHandlerHostApiImpl(binaryMessenger, this.instanceManager));
  }

  onAttachedToEngine(binding: FlutterPluginBinding) {
    this.setUp(
      binding.getBinaryMessenger(),
      binding.getPlatformViewRegistry(),
      binding.getApplicationContext(),
      new PluginBindingFlutterAssetManager(
        binding.getApplicationContext().resourceManager, binding.getFlutterAssets())
    );
  }

  onDetachedFromEngine(binding: FlutterPluginBinding) {
    if (this.instanceManager != null) {
      this.instanceManager.stopFinalizationListener();
      this.instanceManager = null;
    }
  }

  getInstanceManager() {
    return this.instanceManager;
  }
}
