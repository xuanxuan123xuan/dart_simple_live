// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on WebSettingsHostApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import { WebSettingsHostApi } from './GeneratedOhosWebView';
import { InstanceManager } from './InstanceManager';
import { WebViewPlatformView } from './WebViewHostApiImpl';

export interface WebSettings {
  setDomStorageEnabled(flag: boolean): void;

  getDomStorageEnabled(): boolean;

  setJavaScriptCanOpenWindowsAutomatically(flag: boolean): void;

  getJavaScriptCanOpenWindowsAutomatically(): boolean;

  setSupportMultipleWindows(support: boolean): void;

  getSupportMultipleWindows(): boolean;

  setBackgroundColor(color: number): void;

  getBackgroundColor(): string;

  setJavaScriptEnabled(flag: boolean): void;

  getJavaScriptEnabled(): boolean;

  setUserAgentString(userAgentString: string): void;

  setMediaPlaybackRequiresUserGesture(require: boolean): void;

  getMediaPlaybackRequiresUserGesture(): boolean;

  setSupportZoom(support: boolean): void;

  getSupportZoom(): boolean;

  setLoadWithOverviewMode(overview: boolean): void;

  getLoadWithOverviewMode(): boolean;

  setUseWideViewPort(use: boolean): void;

  getUseWideViewPort(): boolean;

  setDisplayZoomControls(enabled: boolean): void;

  setBuiltInZoomControls(enabled: boolean): void;

  setAllowFileAccess(enabled: boolean): void;

  getAllowFileAccess(): boolean;

  setTextZoom(textZoom: number): void;

  getTextZoom(): number;

  getUserAgentString(): Promise<string>;
  
  onTextZoomChanged(callback: (ratio: number) => void): void;

  setAllowFullScreenRotate(enabled: boolean): void;
  
  getAllowFullScreenRotate(): boolean;
}

export class WebSettingsCreator {
  createWebSettings(webView: WebViewPlatformView): WebSettings {
    return webView.getWebSettings();
  }
}

export class WebSettingsHostApiImpl extends WebSettingsHostApi {
  private instanceManager: InstanceManager;

  private webSettingsCreator: WebSettingsCreator;

  constructor(instanceManager: InstanceManager, webSettingsCreator: WebSettingsCreator) {
    super();
    this.instanceManager = instanceManager;
    this.webSettingsCreator = webSettingsCreator;
  }

  create(instanceId: number, webViewInstanceId: number) {
    const webView: WebViewPlatformView = this.instanceManager.getInstance(webViewInstanceId);
    this.instanceManager.addDartCreatedInstance(this.webSettingsCreator.createWebSettings(webView), instanceId);
  }

  setDomStorageEnabled(instanceId: number, flag: boolean) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setDomStorageEnabled(flag);
  }

  setJavaScriptCanOpenWindowsAutomatically(instanceId: number, flag: boolean) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setJavaScriptCanOpenWindowsAutomatically(flag);
  }

  setSupportMultipleWindows(instanceId: number, support: boolean) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setSupportMultipleWindows(support);
  }

  setBackgroundColor(instanceId: number, color: number) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setBackgroundColor(color);
  }

  setJavaScriptEnabled(instanceId: number, flag: boolean) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setJavaScriptEnabled(flag);
  }

  setUserAgentString(instanceId: number, userAgentString: string) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setUserAgentString(userAgentString);
  }

  setMediaPlaybackRequiresUserGesture(instanceId: number, require: boolean) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setMediaPlaybackRequiresUserGesture(require);
  }

  setSupportZoom(instanceId: number, support: boolean) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setSupportZoom(support);
  }

  setLoadWithOverviewMode(instanceId: number, overview: boolean) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setLoadWithOverviewMode(overview);
  }

  setUseWideViewPort(instanceId: number, use: boolean) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setUseWideViewPort(use);
  }

  setDisplayZoomControls(instanceId: number, enabled: boolean) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setDisplayZoomControls(enabled);
  }

  setBuiltInZoomControls(instanceId: number, enabled: boolean) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setBuiltInZoomControls(enabled);
  }

  setAllowFileAccess(instanceId: number, enabled: boolean) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setAllowFileAccess(enabled);
  }

  setTextZoom(instanceId: number, textZoom: number) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setTextZoom(textZoom);
  }

  getUserAgentString(instanceId: number): Promise<string> {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    return webSettings.getUserAgentString();
  }

  setAllowFullScreenRotate(instanceId: number, enabled: boolean) {
    const webSettings:WebSettings = this.instanceManager.getInstance(instanceId);
    webSettings.setAllowFullScreenRotate(enabled);
  }
}