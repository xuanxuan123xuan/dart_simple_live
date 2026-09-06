// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on CustomViewCallbackHostApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { CustomViewCallback, CustomViewCallbackHostApi } from './GeneratedOhosWebView';
import { InstanceManager } from './InstanceManager'

export class CustomViewCallbackHostApiImpl extends CustomViewCallbackHostApi {
  // To ease adding additional methods, this value is added prematurely.

  binaryMessenger: BinaryMessenger;

  instanceManager: InstanceManager;

  /**
   * Constructs a {@link CustomViewCallbackHostApiImpl}.
   *
   * @param binaryMessenger used to communicate with Dart over asynchronous messages
   * @param instanceManager maintains instances stored to communicate with attached Dart objects
   */
  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    super()
    this.binaryMessenger = binaryMessenger;
    this.instanceManager = instanceManager;
  }

  onCustomViewHidden(identifier: number) {
    this.getCustomViewCallbackInstance(identifier).onCustomViewHidden();
  }

  getCustomViewCallbackInstance(identifier: number) : CustomViewCallback {
    return this.instanceManager.getInstance(identifier);
  }
}