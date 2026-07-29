// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.

import image from '@ohos.multimedia.image';
import resourceManager from '@ohos.resourceManager';

@Observed export class VideoItem {
  name: string;
  src: resourceManager.RawFileDescriptor;
  iSrc: string;
  pixelMap?: image.PixelMap;

  constructor(name: string, src: resourceManager.RawFileDescriptor, iSrc: string, pixelMap?: image.PixelMap) {
    this.name = name;
    this.src = src;
    this.iSrc = iSrc;
    this.pixelMap = pixelMap;
  }
}