// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on WebChromeClientFlutterApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { CustomViewCallbackFlutterApiImpl } from './CustomViewCallbackFlutterApiImpl';
import { DVModel } from '@ohos/flutter_ohos/src/main/ets/view/DynamicView/dynamicView';
import { FileChooserParamsFlutterApiImpl } from './FileChooserParamsFlutterApiImpl';
import GeneratedOhosWebView, {
  ConsoleMessageLevel,
  ConsoleMessage as FlutterConsoleMessage,
  CustomViewCallback,
  Reply,
  WebChromeClientFlutterApi
} from './GeneratedOhosWebView';
import { GeolocationPermissionsCallbackFlutterApiImpl } from './GeolocationPermissionsCallbackFlutterApiImpl';
import { InstanceManager } from './InstanceManager';
import { PermissionRequestFlutterApiImpl } from './PermissionRequestFlutterApiImpl';
import { ViewFlutterApiImpl } from './ViewFlutterApiImpl';
import { WebChromeClient } from './WebChromeClientHostApiImpl';
import { WebViewFlutterApiImpl } from './WebViewFlutterApiImpl';
import { WebViewPlatformView } from './WebViewHostApiImpl';

const TAG: string = "WebChromeClientFlutterApiImpl";

export class WebChromeClientFlutterApiImpl extends WebChromeClientFlutterApi {
  private instanceManager: InstanceManager;
  private webViewFlutterApi: WebViewFlutterApiImpl;
  private emptyReply: Reply<void> = {
    reply: (reply) => {
    }
  }

  toConsoleMessageLevel(level: MessageLevel): ConsoleMessageLevel {
    switch (level) {
      case MessageLevel.Info:
        return ConsoleMessageLevel.TIP;
      case MessageLevel.Log:
        return ConsoleMessageLevel.LOG;
      case MessageLevel.Warn:
        return ConsoleMessageLevel.WARNING;
      case MessageLevel.Error:
        return ConsoleMessageLevel.ERROR;
      case MessageLevel.Debug:
        return ConsoleMessageLevel.DEBUG;
      default:
        return ConsoleMessageLevel.UNKNOWN;
    }
  }

  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    super(binaryMessenger);
    this.instanceManager = instanceManager;
    this.webViewFlutterApi = new WebViewFlutterApiImpl(binaryMessenger, instanceManager);
  }

  onProgressChangedImpl(
    webChromeClient: WebChromeClient,
    webView: WebViewPlatformView,
    progress: number,
    callback: Reply<void>
  ): void {
    this.webViewFlutterApi.create(webView, this.emptyReply);

    const webViewIdentifier: number = this.instanceManager.getIdentifier(webView);
    this.onProgressChanged(this.getIdentifierForClient(webChromeClient), webViewIdentifier, progress, callback);
  }

  onShowFileChooserImpl(
    webChromeClient: WebChromeClient,
    webView: WebViewPlatformView,
    fileChooserParams: FileSelectorParam,
    callback: Reply<Array<string>>
  ) {
    this.webViewFlutterApi.create(webView, this.emptyReply);

    new FileChooserParamsFlutterApiImpl(
      this.binaryMessenger,
      this.instanceManager
    ).create(
      fileChooserParams,
      this.emptyReply
    );

    this.onShowFileChooser(
      this.instanceManager.getIdentifier(webChromeClient),
      this.instanceManager.getIdentifier(webView),
      this.instanceManager.getIdentifier(fileChooserParams),
      callback
    )
  }

  onGeolocationPermissionsShowPromptImpl(
    webChromeClient: WebChromeClient,
    origin: string,
    callback: JsGeolocation,
    replyCallback: Reply<void>
  ) {
    new GeolocationPermissionsCallbackFlutterApiImpl(this.binaryMessenger, this.instanceManager)
      .create(callback, this.emptyReply);
    this.onGeolocationPermissionsShowPrompt(
      this.instanceManager.getIdentifier(webChromeClient),
      this.instanceManager.getIdentifier(callback),
      origin,
      replyCallback
    )
  }

  onGeolocationPermissionsHidePromptImpl(
    instance: WebChromeClient, callback: Reply<void>
  ) {
    this.onGeolocationPermissionsHidePrompt(
      this.instanceManager.getIdentifier(instance),
      callback
    );
  }

  onPermissionRequestImpl(
    instance: WebChromeClient,
    request: PermissionRequest,
    callback: Reply<void>
  ) {
    new PermissionRequestFlutterApiImpl(this.binaryMessenger, this.instanceManager)
      .create(request, request.getAccessibleResource(), this.emptyReply);

    this.onPermissionRequest(
      this.instanceManager.getIdentifier(instance),
      this.instanceManager.getIdentifier(request),
      callback
    );
  }

  onShowCustomViewImpl(
    instance: WebChromeClient,
    view: DVModel,
    customViewCallback: CustomViewCallback,
    callback: Reply<void>
  ) {
    new ViewFlutterApiImpl(this.binaryMessenger, this.instanceManager).create(view, this.emptyReply);
    new CustomViewCallbackFlutterApiImpl(this.binaryMessenger, this.instanceManager)
      .create(customViewCallback, this.emptyReply);

    this.onShowCustomView(
      this.instanceManager.getIdentifier(instance),
      this.instanceManager.getIdentifier(view),
      this.instanceManager.getIdentifier(customViewCallback),
      callback
    );
  }

  onHideCustomViewImpl(instance: WebChromeClient, callback: Reply<void>) {
    this.onHideCustomView(
      this.instanceManager.getIdentifier(instance),
      callback
    );
  }

  onConsoleMessageImpl(
    instance: WebChromeClient,
    message: ConsoleMessage,
    callback: Reply<void>
  ) {
    this.onConsoleMessage(
      this.instanceManager.getIdentifier(instance),
      FlutterConsoleMessage.Builder()
        .setLineNumber(message.getLineNumber())
        .setMessage(message.getMessage())
        .setLevel(this.toConsoleMessageLevel(message.getMessageLevel()))
        .setSourceId(message.getSourceId())
        .build(),
      callback
    );
  }

  onJsAlertImpl(
    instance: WebChromeClient,
    url: string,
    message: string,
    callback: Reply<void>) {
    this.onJsAlert(this.getIdentifierForClient(instance), url, message, callback);
  }

  onJsConfirmImpl(
    instance: WebChromeClient,
    url: string,
    message: string,
    callback: Reply<boolean | null>) {
    this.onJsConfirm(this.getIdentifierForClient(instance), url, message, callback);
  }

  onJsPromptImpl(
    instance: WebChromeClient,
    url: string,
    message: string,
    defaultValue: string,
    callback: Reply<string | null>) {
    this.onJsPrompt(this.getIdentifierForClient(instance), url, message, defaultValue, callback);
  }

  getIdentifierForClient(webChromeClient: WebChromeClient): number {
    const identifier: number = this.instanceManager.getIdentifier(webChromeClient);
    if (identifier == null) {
      throw new Error("Could not find identifier for WebChromeClient.");
    }
    return identifier;
  }
}
