// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on WebChromeClientHostApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { Reply, WebChromeClientHostApi, CustomViewCallback, HttpAuthHandler } from './GeneratedOhosWebView';
import { InstanceManager } from './InstanceManager';
import { OhosWebView } from './OhosWebView';
import { WebChromeClientFlutterApiImpl } from './WebChromeClientFlutterApiImpl';
import { WebViewPlatformView } from './WebViewHostApiImpl'
import { WebViewClient } from './WebViewClientHostApiImpl';
import { BuilderParams, DVModelParameters, DVModel } from '@ohos/flutter_ohos/src/main/ets/view/DynamicView/dynamicView'
import web_webview from '@ohos.web.webview'

const TAG: string = "WebChromeClientHostApiImpl";

export interface WebChromeClient {
  onProgressChanged(view: WebViewPlatformView, progress: number): void;

  onGeolocationPermissionsShowPrompt(origin: string, callback: JsGeolocation): void;

  onGeolocationPermissionsHidePrompt(): void;

  onShowFileChooser(
    webView: WebViewPlatformView, filePathCallback: FileSelectorResult, fileChooserParams: FileSelectorParam
  ): boolean;

  onPermissionRequest(request: PermissionRequest): void;

  onConsoleMessage(message: ConsoleMessage): void;

  onCreateWindow(webView: WebViewPlatformView, isDialog: boolean, isUserGesture: boolean, handler: ControllerHandler): void;

  onJsAlert(webView: WebViewPlatformView, url: string, message: string, result: JsResult): boolean;

  onJsConfirm(webView: WebViewPlatformView, url: string, message: string, result: JsResult): boolean;

  onJsPrompt(webView: WebViewPlatformView, url: string, message: string, defaultValue: string, result: JsResult): boolean;
}

export class WebChromeClientHostApiImpl extends WebChromeClientHostApi {
  private instanceManager: InstanceManager;

  private webChromeClientCreator: WebChromeClientCreator;

  private flutterApi: WebChromeClientFlutterApiImpl;

  constructor(
    instanceManager: InstanceManager,
    webChromeClientCreator: WebChromeClientCreator,
    flutterApi: WebChromeClientFlutterApiImpl
  ) {
    super();
    this.instanceManager = instanceManager;
    this.webChromeClientCreator = webChromeClientCreator;
    this.flutterApi = flutterApi;
  }

  create(instanceId: number) {
    const webChromeClient: WebChromeClient = this.webChromeClientCreator.createWebChromeClient(this.flutterApi);
    this.instanceManager.addDartCreatedInstance(webChromeClient, instanceId);
  }

  setSynchronousReturnValueForOnShowFileChooser(instanceId: number, value: boolean) {
    const webChromeClient: WebChromeClientImpl = this.instanceManager.getInstance(instanceId);
    webChromeClient.setReturnValueForOnShowFileChooser(value);
  }

  setSynchronousReturnValueForOnConsoleMessage(instanceId: number, value: boolean) {
    const webChromeClient: WebChromeClientImpl = this.instanceManager.getInstance(instanceId);
    webChromeClient.setReturnValueForOnConsoleMessage(value);
  }

  setSynchronousReturnValueForOnJsAlert(instanceId: number, value: boolean) {
    const webChromeClient: WebChromeClientImpl = this.instanceManager.getInstance(instanceId);
    webChromeClient.setReturnValueForOnJsAlert(value);
  }

  setSynchronousReturnValueForOnJsConfirm(instanceId: number, value: boolean) {
    const webChromeClient: WebChromeClientImpl = this.instanceManager.getInstance(instanceId);
    webChromeClient.setReturnValueForOnJsConfirm(value);
  }

  setSynchronousReturnValueForOnJsPrompt(instanceId: number, value: boolean) {
    const webChromeClient: WebChromeClientImpl = this.instanceManager.getInstance(instanceId);
    webChromeClient.setReturnValueForOnJsPrompt(value);
  }
}

export class WebChromeClientCreator {
  createWebChromeClient(flutterApi: WebChromeClientFlutterApiImpl): WebChromeClientImpl {
    return new WebChromeClientImpl(flutterApi);
  }
}


@CustomDialog
struct NewWebView {
  controller?: CustomDialogController
  webViewController: web_webview.WebviewController = new web_webview.WebviewController();

  build() {
    Web({ src: "", controller: this.webViewController })
      .javaScriptAccess(true)
      .multiWindowAccess(false)
      .onWindowExit(
        () => {
          if (this.controller) {
            this.controller.close();
          }
        }
      )
  }
}

class WebChromeClientImpl implements WebChromeClient {
  private flutterApi: WebChromeClientFlutterApiImpl;
  private returnValueForOnShowFileChooser: boolean = false;
  private returnValueForOnConsoleMessage: boolean = false;

  private returnValueForOnJsAlert : boolean = false;
  private returnValueForOnJsConfirm : boolean = false;
  private returnValueForOnJsPrompt : boolean = false;

  constructor(flutterApi: WebChromeClientFlutterApiImpl) {
    this.flutterApi = flutterApi;
  }

  private emptyReply: Reply<void> = {
    reply: (reply) => {
    }
  }

  onCreateWindow(webView: WebViewPlatformView, isDialog: boolean, isUserGesture: boolean, handler: ControllerHandler) {
    if (webView.getDialogController() != null) {
      webView.getDialogController()?.close();
    }
    let newWebViewController: web_webview.WebviewController = new web_webview.WebviewController();
    let dialogController: CustomDialogController = new CustomDialogController({
      builder: NewWebView({ webViewController: newWebViewController })
    })
    dialogController.open();
    handler.setWebController(newWebViewController);
  }

  onProgressChanged(view: WebViewPlatformView, progress: number) {
    this.flutterApi.onProgressChangedImpl(
      this, view, progress, this.emptyReply
    )
  }

  onShowCustomView(view: DVModel, callback: CustomViewCallback) {
    this.flutterApi.onShowCustomViewImpl(this, view, callback, this.emptyReply);
  }

  onHideCustomView() {
    this.flutterApi.onHideCustomViewImpl(this, this.emptyReply);
  }

  onGeolocationPermissionsShowPrompt(origin: string, callback: JsGeolocation) {
    this.flutterApi.onGeolocationPermissionsShowPromptImpl(this, origin, callback, this.emptyReply);
  }

  onGeolocationPermissionsHidePrompt() {
    this.flutterApi.onGeolocationPermissionsHidePromptImpl(this, this.emptyReply);
  }

  onShowFileChooser(
    webView: WebViewPlatformView, filePathCallback: FileSelectorResult, fileChooserParams: FileSelectorParam
  ) {
    let currentReturnValueForOnShowFileChooser: boolean = this.returnValueForOnShowFileChooser;
    this.flutterApi.onShowFileChooserImpl(
      this, webView, fileChooserParams, {
      reply: (reply: Array<string> | null) => {
        if (currentReturnValueForOnShowFileChooser && reply) {
          filePathCallback.handleFileList(reply);
        }
      }
    }
    );
    return currentReturnValueForOnShowFileChooser;
  }

  onPermissionRequest(request: PermissionRequest) {
    this.flutterApi.onPermissionRequestImpl(this, request, this.emptyReply);
  }

  onConsoleMessage(consoleMessage: ConsoleMessage): boolean {
    this.flutterApi.onConsoleMessageImpl(this, consoleMessage, this.emptyReply);
    return this.returnValueForOnConsoleMessage;
  }

  setReturnValueForOnShowFileChooser(value: boolean) {
    this.returnValueForOnShowFileChooser = value;
  }

  setReturnValueForOnConsoleMessage(value: boolean) {
    this.returnValueForOnConsoleMessage = value;
  }

  setReturnValueForOnJsAlert(value: boolean) {
    this.returnValueForOnJsAlert = value;
  }

  setReturnValueForOnJsConfirm(value: boolean) {
    this.returnValueForOnJsConfirm = value;
  }

  setReturnValueForOnJsPrompt(value: boolean) {
    this.returnValueForOnJsPrompt = value;
  }

  onJsAlert(webView: WebViewPlatformView, url: string, message: string, result: JsResult) {
    if (this.returnValueForOnJsAlert) {
      this.flutterApi.onJsAlertImpl(this, url, message, {
        reply: () => {
          result.handleConfirm();
        }
      });
      return true;
    } else {
      return false;
    }
  }

  onJsConfirm(webView: WebViewPlatformView, url: string, message: string, result: JsResult) {
    if (this.returnValueForOnJsConfirm) {
      this.flutterApi.onJsConfirmImpl(this, url, message, {
        reply: (data: boolean | null) => {
          if (data) {
            result.handleConfirm();
          } else {
            result.handleCancel();
          }
        }
      })
      return true;
    } else {
      return false;
    }
  }

  onJsPrompt(webView: WebViewPlatformView, url: string, message: string, defaultValue: string, result: JsResult) {
    if (this.returnValueForOnJsPrompt) {
      this.flutterApi.onJsPromptImpl(this, url, message, defaultValue, {
        reply: (data: string | null) => {
          if (data != null) {
            result.handlePromptConfirm(data);
          } else {
            result.handleCancel();
          }
        }
      })
      return true;
    } else {
      return false;
    }
  }
}

class newWindowWebViewClient implements WebViewClient {
  onPageStarted(view: WebViewPlatformView, url: string) {
    Log.i(TAG, "onPageStarted");
  }

  onPageFinished(view: WebViewPlatformView, url: string) {
    Log.i(TAG, "onPageFinished");
  }

  onReceivedError(view: WebViewPlatformView, request: WebResourceRequest, error: WebResourceError) {
    Log.i(TAG, "onReceivedError");
  }

  doUpdateVisitedHistory(view: WebViewPlatformView, url: string, isReload: boolean) {
    Log.i(TAG, "doUpdateVisitedHistory");
  }

  shouldOverrideUrlLoading(view: WebViewPlatformView, request: WebResourceRequest): boolean {
    view.getController().loadUrl(request.getRequestUrl());
    return true;
  }

  onReceivedHttpAuthRequest(
    view: WebViewPlatformView,
    handler: HttpAuthHandler,
    host: string,
    realm: string
  ): void {
    // todo
    Log.i(TAG, "onReceivedHttpAuthRequest");
  }
}