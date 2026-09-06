// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on WebStorageHostApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import { WebStorageHostApi } from './GeneratedOhosWebView';
import web_webview from '@ohos.web.webview'
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

const TAG:string = "WebStorageHostApiImpl";
export class WebStorageHostApiImpl extends WebStorageHostApi {
  create(instanceId: number) {
    Log.i(TAG, "WebStorage no need to create");
  }

  deleteAllData(instanceId: number) {
    web_webview.WebStorage.deleteAllData();
  }
}