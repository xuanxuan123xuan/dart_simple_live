// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on FlutterWebViewFactory.java originally written by
// Copyright 2013 The Flutter Authors.

import common from '@ohos.app.ability.common';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import PlatformView from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import PlatformViewFactory from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformViewFactory';
import { InstanceManager } from './InstanceManager';

const TAG :string = "FlutterWebViewFactory";
export class FlutterWebViewFactory extends PlatformViewFactory {
  private instanceManager:InstanceManager;

  constructor(instanceManager:InstanceManager) {
    super(StandardMessageCodec.INSTANCE);
    this.instanceManager = instanceManager;
  }

  create(context: common.Context, viewId: number, args: ESObject): PlatformView {
    Log.i(TAG, "params " + args)
    const identifier : number = args;
    if (identifier == null) {
      throw new Error("An identifier is required to retrieve WebView instance.");
    }
    const view : PlatformView = this.instanceManager.getInstance(identifier);
    if (view == null) {
      throw new Error("Unable to find WebView instance: " + args);
    }
    return view;
  }
}