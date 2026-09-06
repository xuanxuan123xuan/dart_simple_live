// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on DownloadListenerFlutterApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import { InstanceManager } from './InstanceManager'
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { Reply, DownloadListenerFlutterApi, FileChooserMode } from "./GeneratedOhosWebView"

export class DownloadListenerFlutterApiImpl extends DownloadListenerFlutterApi {
  private instanceManager: InstanceManager;

  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    super(binaryMessenger);
    this.instanceManager = instanceManager;
  }

  /** Passes arguments from {@link DownloadListener#onDownloadStart} to Dart. */
  onDownloadStart(
    downloadListener: WebviewController | ESObject,
    url: string,
    userAgent: string,
    contentDisposition: string,
    mimetype: string, contentLength: number, callback: Reply<void>
  ) {
    super.onDownloadStartT(
      this.getIdentifierForListener(downloadListener),
      url,
      userAgent,
      contentDisposition,
      mimetype,
      contentLength,
      callback
    );
  }

  getIdentifierForListener(listener: DownloadListener): number {
    const identifier = this.instanceManager.getIdentifier(listener);
    if (identifier == null) {
      throw new Error("Could not find identifier for DownloadListener.");
    }
    return identifier;
  }
}

export interface DownloadListener {
  onDownloadStart(url: string, userAgent: string, contentDisposition: string, mimeType: string, contentLength: number): void;
}
