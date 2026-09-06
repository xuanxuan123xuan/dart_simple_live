// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on JavaScriptChannelFlutterApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import {InstanceManager} from './InstanceManager'
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import {Reply, JavaScriptChannelFlutterApi} from "./GeneratedOhosWebView"
import { JavaScriptChannel } from './JavaScriptChannel';

export class JavaScriptChannelFlutterApiImpl extends JavaScriptChannelFlutterApi {
  private  instanceManager : InstanceManager;
  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    super(binaryMessenger);
    this.instanceManager = instanceManager;
  }


  postMessage(
    javaScriptChannel:JavaScriptChannel,
    messageArg:string,
    callback:Reply<void>) {
    super.postMessageT(this.getIdentifierForJavaScriptChannel(javaScriptChannel), messageArg, callback);
  }

  private getIdentifierForJavaScriptChannel( javaScriptChannel:JavaScriptChannel) :number{
    const identifier:number = this.instanceManager.getIdentifier(javaScriptChannel);
    if (identifier == null) {
      throw new Error("Could not find identifier for JavaScriptChannel.");
    }
    return identifier;
  }
}
