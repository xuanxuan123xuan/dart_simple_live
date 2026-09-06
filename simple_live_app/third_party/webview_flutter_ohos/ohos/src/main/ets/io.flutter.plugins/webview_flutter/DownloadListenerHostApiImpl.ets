// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on DownloadListenerHostApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import { DownloadListenerFlutterApiImpl } from './DownloadListenerFlutterApiImpl';
import { DownloadListenerHostApi } from './GeneratedOhosWebView';
import { InstanceManager } from './InstanceManager';

export class DownloadListenerHostApiImpl extends DownloadListenerHostApi {
  private instanceManager: InstanceManager;

  private downloadListenerCreator: DownloadListenerCreator;

  private flutterApi: DownloadListenerFlutterApiImpl;

  constructor(
    instanceManager: InstanceManager, downloadListenerCreator: DownloadListenerCreator,
    flutterApi: DownloadListenerFlutterApiImpl
  ) {
    super()
    this.instanceManager = instanceManager;
    this.downloadListenerCreator = downloadListenerCreator;
    this.flutterApi = flutterApi;
  }

  create(instanceId: number) {
    const downloadListener = DownloadListenerHostApiImpl.createDownloadListener(this.flutterApi);
    this.instanceManager.addDartCreatedInstance(downloadListener, instanceId);
  }

  static createDownloadListener(flutterApi: DownloadListenerFlutterApiImpl): DownloadListenerImpl {
    return new DownloadListenerImpl(flutterApi);
  }
}

export class DownloadListenerCreator {
  createDownloadListener(flutterApi: DownloadListenerFlutterApiImpl): DownloadListenerImpl {
    return new DownloadListenerImpl(flutterApi);
  }
}

class DownloadListenerImpl implements DownloadListener {
  private flutterApi: DownloadListenerFlutterApiImpl;

  constructor(flutterApi: DownloadListenerFlutterApiImpl) {
    this.flutterApi = flutterApi;
  }

  onDownloadStart(url: string, userAgent: string, contentDisposition: string, mimetype: string, contentLength: number) {
    this.flutterApi.onDownloadStart(
      this, url, userAgent, contentDisposition, mimetype, contentLength, { reply: () => {
    } }
    );
  }
}

export interface DownloadListener {
  onDownloadStart(url: string, userAgent: string, contentDisposition: string, mimeType: string, contentLength: number): void;
}
