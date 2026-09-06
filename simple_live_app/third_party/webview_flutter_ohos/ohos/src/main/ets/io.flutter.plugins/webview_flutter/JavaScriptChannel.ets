// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on JavaScriptChannel.java originally written by
// Copyright 2013 The Flutter Authors.

import { JavaScriptChannelFlutterApiImpl } from "./JavaScriptChannelFlutterApiImpl"

export class JavaScriptChannel {
  private javaScriptChannelName: string;

  private flutterApi: JavaScriptChannelFlutterApiImpl;

  constructor(
    flutterApi: JavaScriptChannelFlutterApiImpl,
    channelName: string,
  ) {
    this.flutterApi = flutterApi;
    this.javaScriptChannelName = channelName;
  }

  public postMessage(message: string) {
    this.flutterApi.postMessage(
      this, message,
      {
        reply: () => {
        }
      }
    )
  }

  getJavaScriptChannelName(): string {
    return this.javaScriptChannelName;
  }
}
