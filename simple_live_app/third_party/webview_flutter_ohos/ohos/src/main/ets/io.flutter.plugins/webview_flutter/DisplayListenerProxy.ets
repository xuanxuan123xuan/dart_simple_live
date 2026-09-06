// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on DisplayListenerProxy.java originally written by
// Copyright 2013 The Flutter Authors.

import display from '@ohos.display';

export class DisplayListenerProxy {
  private static TAG = "DisplayListenerProxy";

  private listenersBeforeWebView: mDisplay[] = new Array<mDisplay>();

  async onPreWebViewInitialization(): Promise<void> {
    this.listenersBeforeWebView = (await this.yoinkDisplayListeners()) as mDisplay[];
  }

  private async yoinkDisplayListeners(): Promise<display.Display[]> {
    const res = await display.getAllDisplays()
    return res
  }

  async onPostWebViewInitialization() {
    let webViewListeners: mDisplay[] = (await this.yoinkDisplayListeners()) as mDisplay[];

    webViewListeners = webViewListeners.filter((item: ESObject) => this.listenersBeforeWebView.indexOf(item) === -1)

    if (webViewListeners.length === 0) {
      return;
    }

    const onDisplayAdded = (displayId: number) => {
      for (let display of webViewListeners) {
        display.addCallback(displayId);
      }
    }

    const onDisplayRemoved = (displayId: number) => {
      for (let display of webViewListeners) {
        display.removeCallback(displayId);
      }
    }

    const onDisplayChanged = (displayId: number) => {
      if (webViewListeners.filter(item => item.id === displayId).length === 0) {
        return;
      }
      for (let display of webViewListeners) {
        display.changeCallback(displayId);
      }
    }

    for (let display of webViewListeners) {
      display.changeCallback = onDisplayChanged;
      display.addCallback = onDisplayAdded;
      display.removeCallback = onDisplayRemoved
    }

    for (let display of webViewListeners) {
      display.off("remove");
      display.off("add");
      display.off("change");

      display.on("remove", onDisplayRemoved)
      display.on("add", onDisplayAdded)
      display.on("change", onDisplayChanged)
    }
  }
}

interface mDisplay extends display.Display {
  on: ESObject,
  off: ESObject,
  changeCallback,
  removeCallback,
  addCallback,
}