// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on FileChooserParamsFlutterApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import { InstanceManager } from './InstanceManager'
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { Reply, FileChooserParamsFlutterApi, FileChooserMode } from "./GeneratedOhosWebView"

export class FileChooserParamsFlutterApiImpl extends FileChooserParamsFlutterApi {
  private instanceManager: InstanceManager;

  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    super(binaryMessenger);
    this.instanceManager = instanceManager;
  }

  private toFileChooserEnumData(mode: number): FileChooserMode {
    switch (mode) {
      case FileSelectorMode.FileOpenMode:
        return FileChooserMode.OPEN;

      case FileSelectorMode.FileOpenMultipleMode:
        return FileChooserMode.OPEN_MULTIPLE;

      case FileSelectorMode.FileSaveMode:
        return FileChooserMode.SAVE;

      default:
        throw new Error(`Unsupported FileChooserMode: ${mode}`);
    }
  }

  /**
   * Stores the FileChooserParams instance and notifies Dart to create a new FileChooserParams
   * instance that is attached to this one.
   */

  create(instance: FileSelectorParam, callback: Reply<void>) {
    if (!this.instanceManager.containsInstance(instance)) {
      super.tCreate(
        this.instanceManager.addHostCreatedInstance(instance),
        instance.isCapture(),
        instance.getAcceptType(),
        this.toFileChooserEnumData(instance.getMode()),
        instance.getTitle(),
        callback
      );
    }
  }
}
