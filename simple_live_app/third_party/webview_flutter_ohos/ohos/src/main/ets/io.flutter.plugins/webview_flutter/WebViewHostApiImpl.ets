// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on WebViewHostApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView'
import { DVModel, DVModelParameters } from '@ohos/flutter_ohos/src/main/ets/view/DynamicView/dynamicView'
import { Result, WebViewHostApi, WebViewPoint, HttpAuthHandler } from './GeneratedOhosWebView'
import web_webview from '@ohos.web.webview'
import { WebBuilder, OhosWebView } from './OhosWebView'
import { createDVModelFromJson } from '@ohos/flutter_ohos/src/main/ets/view/DynamicView/dynamicViewJson'
import { DVModelJson } from "./DynamicUtils"
import { InstanceManager } from './InstanceManager'
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import common from '@ohos.app.ability.common'
import { WebChromeClient } from './WebChromeClientHostApiImpl'
import { WebViewClient } from './WebViewClientHostApiImpl'
import { WebSettings } from './WebSettingsHostApiImpl'
import { DynamicUtils } from "./DynamicUtils"
import { DownloadListener } from './DownloadListenerFlutterApiImpl'
import { DisplayListenerProxy } from './DisplayListenerProxy'
import { JavaScriptChannel } from './JavaScriptChannel'
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { WebViewFlutterApiImpl } from './WebViewFlutterApiImpl.ets'
import window from '@ohos.window'
import display from '@ohos.display'

const TAG: string = "WebViewHostApiImpl";

export declare class PlatformViewVisibleAreaEventOptions {
  enable: boolean // Enable variable area monitoring
  ratios: Array<number> // Ratio thresholds for visible area changes, e.g., [0.0, 1.0] means 0% to 100% visible
  expectedUpdateInterval: number // Expected interval for visible area updates in milliseconds
  onInactiveThreshold: number // Texture continuous production pause operation visible area threshold
  onActiveThreshold: number // Texture continuous production activation operation visible area threshold
}

export class WebViewHostApiImpl extends WebViewHostApi {
  private instanceManager: InstanceManager;

  private webViewProxy: WebViewProxy;

  private binaryMessenger: BinaryMessenger;

  private context: common.Context;
  private api?: WebViewFlutterApiImpl;

  constructor(
    instanceManager: InstanceManager,
    webViewProxy: WebViewProxy,
    binaryMessenger: BinaryMessenger,
    context: common.Context
  ) {
    super();
    this.instanceManager = instanceManager;
    this.webViewProxy = webViewProxy;
    this.binaryMessenger = binaryMessenger;
    this.context = context;
  }

  setContext(context: common.Context): void {
    this.context = context;
  }

  create(instanceId: number): void {
    let displayProxy: DisplayListenerProxy = new DisplayListenerProxy();
    displayProxy.onPreWebViewInitialization();
    const webView: WebViewPlatformView = this.webViewProxy.createWebView(this.binaryMessenger, this.instanceManager);
    displayProxy.onPostWebViewInitialization();
    this.instanceManager.addDartCreatedInstance(webView, instanceId);
  }

  loadData(instanceId: number, data: string, mimeType: string, encoding: string): void {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    webView.getController().loadData(data, mimeType, encoding, " ", " ");
  }

  async loadDataWithBaseUrl(
    instanceId: number, baseUrl: string, data: string, mimeType: string, encoding: string, historyUrl: string
  ): Promise<void> {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    await webView.waitControllerAttached();
    try {
      // 当baseUrl为空时，其值默认为resource://rawfile/。这样设置是为了解决<a href="">标签锚点无效问题。
      webView.getController().loadData(data, mimeType, encoding, baseUrl == null || baseUrl.trim().length === 0 ? "resource://rawfile/" : baseUrl , historyUrl == null ? " " : historyUrl);
    } catch (err) {
      Log.e(TAG, "loadDataWithBaseUrl err = " + err);
    }
  }

  async loadUrl(instanceId: number, url: string, headers: Map<string, string>): Promise<void> {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    await webView.waitControllerAttached();
    try {
      if (url.startsWith("resources/rawfile/")) {
        try {
          // 设置允许可以跨域访问的路径列表
          webView.getController().setPathAllowingUniversalAccess([
            getContext().resourceDir
          ])
        } catch (err) {
          Log.e(TAG, "setPathAllowingUniversalAccess err = " + err);
        }
        webView.getController().loadUrl($rawfile(url.replace("resources/rawfile/","")), this.toWebHeaders(headers));
      }else {
        webView.getController().loadUrl(url, this.toWebHeaders(headers));
      }
      webView.setUrl(webView.getController().getUrl());
    } catch (err) {
      Log.e(TAG, "loadUrl err = " + err);
    }
  }

  toWebHeaders(headers: Map<string, string>): Array<web_webview.WebHeader> {
    let result: Array<web_webview.WebHeader> = new Array;
    if (headers == null || headers.size == 0) {
      return result;
    }
    for (let arr of headers) {
      let key = arr[0];
      let value = arr[1];
      let header: web_webview.WebHeader = { headerKey: key, headerValue: value };
      result.push(header);
    }
    return result;
  }

  async postUrl(instanceId: number, url: string, data: Uint8Array):  Promise<void> {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    await webView.waitControllerAttached();
    try {
      webView.getController().postUrl(url,data.buffer);
    } catch (err) {
      Log.e(TAG, "postUrl err = " + err);
    }
  }

  async getUrl(instanceId: number): Promise<string> {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    await webView.waitControllerAttached();
    return webView.getController().getUrl();
  }

  canGoBack(instanceId: number): boolean {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    return webView.getController().accessBackward();
  }

  canGoForward(instanceId: number): boolean {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    return webView.getController().accessForward();
  }

  goBack(instanceId: number): void {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    webView.getController().backward();
  }

  goForward(instanceId: number): void {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    webView.getController().forward();
  }

  reload(instanceId: number): void {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    webView.getController().refresh();
  }

  clearCache(instanceId: number, includeDiskFiles: boolean): void {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    webView.waitControllerAttached().then(() => {
      webView.getController().removeCache(includeDiskFiles);
    }).catch((err: ESObject) => {
      Log.e(TAG, "clearCache failed: controller not attached, instanceId=" + instanceId + ", err=" + err);
    });
  }

  evaluateJavascript(instanceId: number, javascriptString: string, result: Result<string>): void {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    webView.getController().runJavaScript(javascriptString)
      .then(
        scriptResult => {
          result.success(scriptResult);
        }
      )
      .catch(
        (error: ESObject) => {
          result.error(error);
        }
      )
  }

  getTitle(instanceId: number): string {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    return webView.getController().getTitle();
  }

  scrollTo(instanceId: number, x: number, y: number): void {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    webView.waitControllerAttached().then(() => {
      webView.getController().scrollTo(x, y);
      webView.setScrollPosition(x, y);
    });
  }

  scrollBy(instanceId: number, x: number, y: number): void {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    webView.waitControllerAttached().then(() => {
      const currentX = webView.getScrollX();
      const currentY = webView.getScrollY();
      webView.getController().scrollBy(x, y);
      webView.setScrollPosition(currentX + x, currentY + y);
    });
  }

  getScrollX(instanceId: number): number {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    return webView.getScrollX();
  }

  getScrollY(instanceId: number): number {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    return webView.getScrollY()
  }

  getScrollPosition(instanceId: number): WebViewPoint {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    return WebViewPoint.Builder()
      .setX(webView.getScrollX())
      .setY(webView.getScrollY())
      .build();
  }

  setWebContentsDebuggingEnabled(enabled: boolean): void {
    this.webViewProxy.setWebContentsDebuggingEnabled(enabled);
  }

  setWebViewClient(instanceId: number, webViewClientInstanceId: number) {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    webView.setWebViewClient(this.instanceManager.getInstance(webViewClientInstanceId));
  }

  async addJavaScriptChannel(instanceId: number, javaScriptChannelInstanceId: number): Promise<void> {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    const javaScriptChannel: JavaScriptChannel = this.instanceManager.getInstance(javaScriptChannelInstanceId);
    await webView.waitControllerAttached();
    try {
      webView.addJavaScriptChannel(javaScriptChannel);
      webView.getController().registerJavaScriptProxy(
        {
          postMessage: (message: ESObject) => {
            javaScriptChannel.postMessage(String(message))
          },
        },
        javaScriptChannel.getJavaScriptChannelName(),
        ["postMessage"]
      )
      webView.getController().refresh()
    } catch (err) {
      Log.e(TAG, "addJavaScriptChannel err = " + err);
    }
  }

  removeJavaScriptChannel(instanceId: number, javaScriptChannelInstanceId: number): void {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    const javaScriptChannel: JavaScriptChannel = this.instanceManager.getInstance(javaScriptChannelInstanceId);
    webView.removeJavaScriptChannel(javaScriptChannel.getJavaScriptChannelName());
    webView.getController().deleteJavaScriptRegister(javaScriptChannel.getJavaScriptChannelName());
    this.instanceManager.remove(javaScriptChannelInstanceId);
  }

  setDownloadListener(instanceId: number, listenerInstanceId: number) {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    webView.setDownloadListener(this.instanceManager.getInstance(listenerInstanceId));
  }

  setWebChromeClient(instanceId: number, clientInstanceId: number) {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(instanceId);
    webView.setWebChromeClient(this.instanceManager.getInstance(clientInstanceId));
  }

  getInstanceManager(): InstanceManager {
    return this.instanceManager;
  }

  setApi(api: WebViewFlutterApiImpl) {
    this.api = api;
  }
}

export class WebViewPlatformView extends PlatformView {

  private WebCookieManager: web_webview.WebCookieManager = new web_webview.WebCookieManager();

  private controller: web_webview.WebviewController = new web_webview.WebviewController();

  private tempUrl: string = "";

  private downloadListener: DownloadListener = {} as ESObject;

  private webChromeClient: WebChromeClient | null = null;

  private webViewClint: WebViewClient | null = null;

  private webSettings: WebSettings | null = null;

  private dialogController: CustomDialogController | null = null;

  private scrollX: number = 0;

  private scrollY: number = 0;

  private returnValueForShouldOverrideUrlLoading: boolean = false;

  private controllerAttached: boolean = false;

  private onDisposeCallback?: () => void;

  private rotation: number = 0;

  userAgentString: string = '';

  isWebviewBinding: boolean = false;

  private webViewFlutterApi: WebViewFlutterApiImpl;

  private javaScriptChannels: Map<string, JavaScriptChannel> = new Map();

  private visibleAreaEventEnable: boolean = true;

  private visibleAreaEventRatios: Array<number> = [0, 0.1, 0.2, 0.5, 0.8, 1];

  private visibleAreaEventExpectedUpdateInterval: number = 1;

  private visibleAreaEventInactiveThreshold: number = 0;

  private visibleAreaEventActiveThreshold: number = 0.1;

  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    super();
    this.webViewFlutterApi = new WebViewFlutterApiImpl(binaryMessenger, instanceManager);
  }

  onDownloadStart = (event: ESObject) => {
    if (this.downloadListener && this.downloadListener.onDownloadStart) {
      this.downloadListener.onDownloadStart(
        event.url,
        event.userAgent,
        event.contentDisposition,
        event.mimetype,
        event.contentLength
      )
    }
  }

  onPageBegin = (event: ESObject) => {
    if (this.webViewClint) {
      this.webViewClint.onPageStarted(this, event.url);
    }
  }

  onPageEnd = (event: ESObject) => {
    if (this.webViewClint) {
      this.webViewClint.onPageFinished(this, event.url);
    }
  }

  onErrorReceive = (event: ESObject) => {
    if (this.webViewClint) {
      this.webViewClint.onReceivedError(this, event.request, event.error);
    }
  }

  onOverrideUrlLoading = (request: WebResourceRequest) => {
    Log.i(TAG, "onOverrideUrlLoading request = " + JSON.stringify(request))
    if(request.getRequestUrl() == 'loaded:///'){
      return true;
    }
    if (this.webViewClint) {
      return this.webViewClint.shouldOverrideUrlLoading(this, request);
    }
    return false;
  }

  onRefreshAccessedHistory = (event: ESObject) => {
    if (this.webViewClint) {
      this.webViewClint.doUpdateVisitedHistory(this, event.url, event.isRefreshed);
    }
  }

  onHttpAuthRequest = (event: ESObject): boolean => {
    Log.i(TAG, "onHttpAuthRequest host=" + event.host + " realm=" + event.realm);
    if (this.webViewClint) {
      const wrappedHandler = new OhosHttpAuthHandler(event.handler);
      this.webViewClint.onReceivedHttpAuthRequest(this, wrappedHandler, event.host, event.realm);
      return true;
    }
    return false;
  }

  onProgressChange = (event: ESObject) => {
    if (this.webChromeClient) {
      this.webChromeClient.onProgressChanged(this, event.newProgress);
    }
  }

  onGeolocationShow = (event: ESObject) => {
    if (this.webChromeClient) {
      this.webChromeClient.onGeolocationPermissionsShowPrompt(event.origin, event.geolocation);
    }
  }

  onGeolocationHide = () => {
    if (this.webChromeClient) {
      this.webChromeClient.onGeolocationPermissionsHidePrompt();
    }
  }

  onShowFileSelector = (event: ESObject) => {
    if (this.webChromeClient) {
      return this.webChromeClient.onShowFileChooser(this, event.result, event.fileSelector);
    }
    return false;
  }

  onPermissionRequest = (event: ESObject) => {
    if (this.webChromeClient) {
      this.webChromeClient.onPermissionRequest(event.request);
    }
  }

  onConsoleMessage = (event: ESObject) => {
    let message:ConsoleMessage = event.message;
    if (this.webChromeClient) {
        this.webChromeClient.onConsoleMessage(event.message);
    } else {
      Log.d(TAG, "logLevel: " + message.getMessageLevel() + " "+ message.getMessage());
    }
    return true;
  }

  onWindowNew = (event: ESObject) => {
    if (this.webChromeClient) {
      this.webChromeClient.onCreateWindow(this, event.isAlert, event.isUserTrigger, event.handler);
    }
  }

  onWindowExit = () => {
    if (this.dialogController) {
      this.dialogController.close();
    }
  }

  onScroll = (event: ESObject) => {
    this.webViewFlutterApi.onScrollChanged(this, event.xOffset, event.yOffset, this.scrollX, this.scrollY, {reply: () => {}})
    this.scrollX = event.xOffset;
    this.scrollY = event.yOffset;
  }

  aboutToAppear() {
    //   此处没有调用，说明只有controller，没有webview
    this.isWebviewBinding = true;
  }

  onControllerAttached = () => {
    Log.d(TAG, "onControllerAttached");
    if (this.userAgentString) {
      this.setCustomUserAgent(this.userAgentString);
      this.controller.refresh();
    }
    this.controllerAttached = true;
    this.reRegisterJavaScriptChannels();
  }

  aboutToDisappear() {
    // 解除绑定controller
    this.isWebviewBinding = false;
  }

  setOnDisposeCallback(callback: () => void) {
    this.onDisposeCallback = callback;
  }

  onJsAlert = (event: ESObject): boolean => {
    if (this.webChromeClient && event) {
      return this.webChromeClient.onJsAlert(this, event.url, event.message, event.result);
    }
    return true;
  }

  onJsConfirm = (event: ESObject): boolean => {
    if (this.webChromeClient && event) {
      return this.webChromeClient.onJsConfirm(this, event.url, event.message, event.result);
    }
    return true;
  }

  onJsPrompt = (event: ESObject): boolean => {
    if (this.webChromeClient && event) {
      return this.webChromeClient.onJsPrompt(this, event.url, event.message, event.value, event.result);
    }
    return true;
  }

  onFullScreenEnter = (event: ESObject) => {
    let context = getContext(this) as common.UIAbilityContext;
    let windowClass = context.windowStage.getMainWindowSync();
    windowClass.setWindowSystemBarEnable([]);
    this.rotation = windowClass.getPreferredOrientation();
    let isAllowFullScreenRotate = this.getWebSettings()?.getAllowFullScreenRotate();
    if (isAllowFullScreenRotate) {
      windowClass.setPreferredOrientation(window.Orientation.LANDSCAPE);
    }
  }

  onFullScreenExit = () => {
    let context = getContext(this) as common.UIAbilityContext;
    let windowClass = context.windowStage.getMainWindowSync();
    windowClass.setWindowSystemBarEnable(['status', 'navigation']);
    windowClass.setPreferredOrientation(this.rotation);
    this.reRegisterJavaScriptChannels();
  }

  getType(): string {
    return 'web';
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(WebBuilder);
  }

  dispose(): void {
    this.controller.stopAllMedia();
    this.onDisposeCallback && this.onDisposeCallback();
  }

  getPlatformViewVisibleAreaEventOptions(): PlatformViewVisibleAreaEventOptions {
    return {
      enable: this.visibleAreaEventEnable,
      ratios: this.visibleAreaEventRatios,
      expectedUpdateInterval: this.visibleAreaEventExpectedUpdateInterval,
      onInactiveThreshold : this.visibleAreaEventInactiveThreshold,
      onActiveThreshold : this.visibleAreaEventActiveThreshold
    } as PlatformViewVisibleAreaEventOptions;
  }

  onInactive(): void {
    this.controller.onInactive();
  }

  onActive(): void {
    this.controller.onActive();
  }

  getController(): web_webview.WebviewController {
    return this.controller;
  }

  setCustomUserAgent(userAgentString: string) {
    this.userAgentString = userAgentString;
    this.controller.setCustomUserAgent(userAgentString);
  }

  setUrl(url: string): void {
    this.tempUrl = url;
  }

  getUrl(): string {
    return this.tempUrl;
  }

  getWebCookieManager(): web_webview.WebCookieManager {
    return this.WebCookieManager;
  }

  setDownloadListener(listener: DownloadListener) {
    this.downloadListener = listener;
  }

  setWebViewClient(webViewClient: WebViewClient) {
    this.webViewClint = webViewClient;
  }

  setWebChromeClient(webChromeClient: WebChromeClient) {
    this.webChromeClient = webChromeClient;
  }

  setDialogController(dialogController: CustomDialogController) {
    this.dialogController = dialogController;
  }

  getDialogController(): CustomDialogController | null {
    return this.dialogController;
  }

  getWebSettings(): WebSettings {
    if (this.webSettings == null) {
      this.webSettings = new WebSettingsImpl(this);
    }
    return this.webSettings!;
  }

  getScrollX(): number {
    return this.scrollX;
  }

  getScrollY(): number {
    return this.scrollY;
  }

  setScrollPosition(x: number, y: number): void {
    this.scrollX = x;
    this.scrollY = y;
    this.webViewFlutterApi.onScrollChanged(this, x, y, this.scrollX, this.scrollY, {reply: () => {}});
  }

  setReturnValueForShouldOverrideUrlLoading(value: boolean) {
    this.returnValueForShouldOverrideUrlLoading = value;
  }

  async waitControllerAttached() {
    if (!this.controllerAttached) {
      await this.checkControllerAttached();
    }
  }

  checkControllerAttached(): Promise<void> {
    return new Promise((resolve, reject) => {
      try {
        let intervalId = setInterval(() => {
          if (this.controllerAttached) {
            clearInterval(intervalId);
            resolve();
          }
        }, 20)
      } catch (err) {
        reject();
      }
    })
  }

  addJavaScriptChannel(channel: JavaScriptChannel) {
    this.javaScriptChannels.set(channel.getJavaScriptChannelName(), channel);
  }

  removeJavaScriptChannel(channelName: string) {
    this.javaScriptChannels.delete(channelName);
  }

  reRegisterJavaScriptChannels() {
    if (this.javaScriptChannels.size === 0) {
      return;
    }
    try {
      this.javaScriptChannels.forEach((channel: JavaScriptChannel, channelName: string) => {
        this.controller.registerJavaScriptProxy(
          {
            postMessage: (message: string) => {
              channel.postMessage(message)
            },
          },
          channelName,
          ["postMessage"]
        )
      })
      this.controller.refresh()
    } catch (err) {
      Log.e(TAG, "reRegisterJavaScriptChannels err = " + err);
    }
  }

}

export class WebViewProxy {
  createWebView(binaryMessenger:BinaryMessenger, instanceManager:InstanceManager): WebViewPlatformView {
    return new WebViewPlatformView(binaryMessenger, instanceManager);
  }

  setWebContentsDebuggingEnabled(enabled: boolean): void {
    web_webview.WebviewController.setWebDebuggingAccess(enabled);
  }
}

class WebSettingsImpl implements WebSettings {
  private webView: WebViewPlatformView;
  private defaultUserAgent: string = '';
  params: DVModelParameters = new DVModelParameters;
  domStorageAccess: boolean = false;
  allowWindowOpenMethod : boolean = false;
  multiWindowAccess : boolean = false;
  backgroundColor : string = "";
  javaScriptAccess : boolean = false;
  mediaPlayGestureAccess : boolean = false;
  zoomAccess : boolean = true;
  overviewModeAccess : boolean = false;
  wideViewModeAccess: boolean = false;
  fileAccess : boolean = true;
  textZoomRatio : number = 0;
  textZoomRatioCallback?: (ratio: number) => void;
  isAllowFullScreenRotate: boolean = false;

  constructor(webView: WebViewPlatformView) {
    this.webView = webView;
    //this.params = webView.getView().params;
  }

  setDomStorageEnabled(flag: boolean) {
    this.domStorageAccess = flag;
  }

  getDomStorageEnabled() : boolean{
    return this.domStorageAccess;
  }

  setJavaScriptCanOpenWindowsAutomatically(flag: boolean) {
    this.allowWindowOpenMethod = flag;
  }

  getJavaScriptCanOpenWindowsAutomatically() : boolean{
    return this.allowWindowOpenMethod;
  }

  setSupportMultipleWindows(support: boolean) {
    this.multiWindowAccess = support;
  }

  getSupportMultipleWindows()  : boolean{
    return this.multiWindowAccess;
  }

  setBackgroundColor(color: number) {
    // number 无法实现透明度，所以转成 string
    let colorStr = `#${color.toString(16).padStart(8, '0')}`;
    this.backgroundColor = colorStr;
  }

  getBackgroundColor() : string{
    return this.backgroundColor;
  }

  setJavaScriptEnabled(flag: boolean) {
    this.javaScriptAccess = flag;
  }

  getJavaScriptEnabled() : boolean {
    return this.javaScriptAccess;
  }

  async setUserAgentString(userAgentString: string) {
    await this.webView.waitControllerAttached();
    this.webView.setCustomUserAgent(userAgentString);
  }

  setMediaPlaybackRequiresUserGesture(require: boolean) {
    this.mediaPlayGestureAccess = require;
  }

  getMediaPlaybackRequiresUserGesture() : boolean{
    return this.mediaPlayGestureAccess;
  }

  setSupportZoom(support: boolean) {
    this.zoomAccess = support;
  }

  getSupportZoom() : boolean{
    return this.zoomAccess;
  }

  setLoadWithOverviewMode(overview: boolean) {
    this.overviewModeAccess = overview;
  }

  getLoadWithOverviewMode() : boolean {
    return this.overviewModeAccess;
  }

  setUseWideViewPort(use: boolean) {
    this.wideViewModeAccess = use;
  }

  getUseWideViewPort() : boolean {
    return this.wideViewModeAccess;
  }

  setDisplayZoomControls(enabled: boolean) {
    //TODO:确认是否支持
  }

  setBuiltInZoomControls(enabled: boolean) {
    //TODO:确认是否支持
  }

  setAllowFileAccess(enabled: boolean) {
    this.fileAccess = enabled;
  }

  getAllowFileAccess() : boolean {
    return this.fileAccess;
  }

  setTextZoom(textZoom: number) {
    this.textZoomRatio = textZoom;
    this.textZoomRatioCallback && this.textZoomRatioCallback(textZoom);
  }

  /**
   * 正常从getCustomUserAgent获取userAgent，需要先绑定webview
   * 如果没有绑定webview或者解绑，需要从缓存中获取，或者获取默认的useragent
   * 获取默认的时候，需要先initializeWebEngine，整个APP仅需调用一次
   *
   * */

  async getUserAgentString(): Promise<string> {
    try {
      await this.webView.waitControllerAttached();
    } catch(err) {
      Log.e(TAG, "getUserAgentString err = " + err)
    }
    if (this.webView.userAgentString) {
      return this.webView.userAgentString;
    }

    if (this.webView.isWebviewBinding) {
      return this.webView.getController().getCustomUserAgent();
    }

    if (this.defaultUserAgent) {
      //  整个app只需要一次initializeWebEngine。
      return this.defaultUserAgent;
    }

    if (typeof (web_webview.WebviewController as ESObject)?.getDefaultUserAgent === 'function') {
    web_webview.WebviewController.initializeWebEngine();
      this.defaultUserAgent = (web_webview.WebviewController as ESObject)?.getDefaultUserAgent();
    }

    return this.defaultUserAgent;
  }

  getTextZoom() : number{
    return this.textZoomRatio;
  }

  onTextZoomChanged(callback: (ratio: number) => void): void {
    this.textZoomRatioCallback = callback;
  }

  setAllowFullScreenRotate(enabled: boolean) {
    this.isAllowFullScreenRotate = enabled;
  }

  getAllowFullScreenRotate() : boolean {
    return this.isAllowFullScreenRotate;
  }
}

class OhosHttpAuthHandler implements HttpAuthHandler {
  private nativeHandler: ESObject;
  private savedUsername: string = '';
  private savedPassword: string = '';

  constructor(handler: ESObject) {
    this.nativeHandler = handler;
  }

  cancel(): void {
    this.nativeHandler.cancel();
  }

  proceed(username: string, password: string): void {
    this.savedUsername = username;
    this.savedPassword = password;
    this.nativeHandler.confirm(username, password);
  }

  useHttpAuthUsernamePassword(): boolean {
    return this.nativeHandler.isHttpAuthInfoSaved?.() ?? false;
  }
}