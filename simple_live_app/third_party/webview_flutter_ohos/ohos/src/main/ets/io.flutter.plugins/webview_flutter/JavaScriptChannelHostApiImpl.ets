// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on JavaScriptChannelHostApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import { JavaScriptChannelHostApi } from './GeneratedOhosWebView';
import { InstanceManager } from './InstanceManager';
import { JavaScriptChannel } from './JavaScriptChannel';
import { JavaScriptChannelFlutterApiImpl } from './JavaScriptChannelFlutterApiImpl';

export class JavaScriptChannelHostApiImpl extends JavaScriptChannelHostApi {
  private instanceManager: InstanceManager;

  private javaScriptChannelCreator: JavaScriptChannelCreator;

  private flutterApi: JavaScriptChannelFlutterApiImpl;

  /** Handles creating {@link JavaScriptChannel}s for a {@link JavaScriptChannelHostApiImpl}. */

  /**
   * Creates a host API that handles creating {@link JavaScriptChannel}s.
   *
   * @param instanceManager maintains instances stored to communicate with Dart 
   *        objects
   * @param javaScriptChannelCreator handles creating {@link JavaScriptChannel}s
   * @param flutterApi handles sending messages to Dart
   * @param platformThreadHandler handles making callbacks on the desired thread
   */
  constructor(
    instanceManager: InstanceManager, javaScriptChannelCreator: JavaScriptChannelCreator,
    flutterApi: JavaScriptChannelFlutterApiImpl
  ) {
    super()
    this.instanceManager = instanceManager;
    this.javaScriptChannelCreator = javaScriptChannelCreator;
    this.flutterApi = flutterApi;
  }

  create(instanceId: number, channelName: string) {
    const javaScriptChannel: JavaScriptChannel =
    this.javaScriptChannelCreator.createJavaScriptChannel(
      this.flutterApi, channelName
    )
    this.instanceManager.addDartCreatedInstance(javaScriptChannel, instanceId);
  }
}

export class JavaScriptChannelCreator {
  createJavaScriptChannel(
    flutterApi: JavaScriptChannelFlutterApiImpl, channelName: string
  ): JavaScriptChannel {
    return new JavaScriptChannel(flutterApi, channelName);
  }
}