// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on PermissionRequestFlutterApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import {InstanceManager} from './InstanceManager'
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import {PermissionRequestFlutterApi,Reply} from "./GeneratedOhosWebView"
export class PermissionRequestFlutterApiImpl {
  private binaryMessenger:BinaryMessenger ;
  private instanceManager:InstanceManager;
  private  api:PermissionRequestFlutterApi;


  constructor(binaryMessenger:BinaryMessenger, instanceManager:InstanceManager) {
    this.binaryMessenger = binaryMessenger;
    this.instanceManager = instanceManager;
    this.api = new PermissionRequestFlutterApi(binaryMessenger);
  }

  create(instance:PermissionRequest,resources:string[],callback:Reply<void>):void {
    if (!this.instanceManager.containsInstance(instance)) {
      this.api.create(this.instanceManager.addHostCreatedInstance(instance), resources, callback);
    }
  }
}
