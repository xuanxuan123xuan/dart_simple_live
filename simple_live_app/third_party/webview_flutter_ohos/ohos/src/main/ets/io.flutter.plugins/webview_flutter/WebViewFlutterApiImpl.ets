// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on WebViewFlutterApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { Reply, WebViewFlutterApi, WebViewHostApi } from './GeneratedOhosWebView';
import { InstanceManager } from './InstanceManager';
import { WebViewPlatformView } from './WebViewHostApiImpl';

export class WebViewFlutterApiImpl {
  private binaryMessenger: BinaryMessenger;
  private instanceManager: InstanceManager;
  private api: WebViewFlutterApi;

  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    this.binaryMessenger = binaryMessenger;
    this.instanceManager = instanceManager;
    this.api = new WebViewFlutterApi(binaryMessenger);
  }

  create(instance: WebViewPlatformView, callback: Reply<void>): void {
    if (!this.instanceManager.containsInstance(instance)) {
      this.api.create(this.instanceManager.addHostCreatedInstance(instance), callback);
    }
  }

  setApi(api: WebViewFlutterApi): void {
    this.api = api;
  }

  onScrollChanged(
    instance: WebViewPlatformView,
    left: number,
    top: number,
    oldLeft: number,
    oldTop: number,
    callback: Reply<void>): void {
    this.api.onScrollChanged(
        this.instanceManager.getIdentifier(instance),
        left,
        top,
        oldLeft,
        oldTop,
        callback);
  }
}