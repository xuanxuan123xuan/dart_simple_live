// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on ViewFlutterApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { ViewFlutterApi, Reply } from './GeneratedOhosWebView';
import { InstanceManager } from './InstanceManager'

/**
 * Flutter API implementation for `View`.
 *
 * <p>This class may handle adding native instances that are attached to a Dart instance or passing
 * arguments of callbacks methods to a Dart instance.
 */
export class ViewFlutterApiImpl {
  // To ease adding additional methods, this value is added prematurely.
  binaryMessenger: BinaryMessenger;

  instanceManager: InstanceManager;
  api: ViewFlutterApi;

  /**
   * Constructs a {@link ViewFlutterApiImpl}.
   *
   * @param binaryMessenger used to communicate with Dart over asynchronous messages
   * @param instanceManager maintains instances stored to communicate with attached Dart objects
   */
  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    this.binaryMessenger = binaryMessenger;
    this.instanceManager = instanceManager;
    this.api = new ViewFlutterApi(binaryMessenger);
  }

  /**
   * Stores the `View` instance and notifies Dart to create and store a new `View` instance that is
   * attached to this one. If `instance` has already been added, this method does nothing.
   */
  create(instance: ESObject, callback: Reply<void>) {
    if (!this.instanceManager.containsInstance(instance)) {
      this.api.create(this.instanceManager.addHostCreatedInstance(instance), callback);
    }
  }

  /**
   * Sets the Flutter API used to send messages to Dart.
   *
   * <p>This is only visible for testing.
   */
  setApi(api: ViewFlutterApi) {
    this.api = api;
  }
}
