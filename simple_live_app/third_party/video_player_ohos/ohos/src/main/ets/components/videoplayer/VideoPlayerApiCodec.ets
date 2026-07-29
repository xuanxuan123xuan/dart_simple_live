// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.

import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import { CreateMessage, LoopingMessage, MixWithOthersMessage, PlaybackSpeedMessage, PositionMessage,
  TextureMessage,
  VolumeMessage
} from './Messages';
import { ByteBuffer } from '@ohos/flutter_ohos/src/main/ets/util/ByteBuffer';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

const TAG = "VideoPlayerApiCodec";

export class VideoPlayerApiCodec extends StandardMessageCodec {
  public static INSTANCE = new VideoPlayerApiCodec();

  readValueOfType(type: number, buffer: ByteBuffer): ESObject {
    switch (type) {
      case 128:
        let res0 =  CreateMessage.fromList(super.readValue(buffer) as Array<ESObject>);
        return res0;
      case 129:
        let res1 =  LoopingMessage.fromList(super.readValue(buffer) as Array<ESObject>);
        return res1;
      case 130:
        let res2 =  MixWithOthersMessage.fromList(super.readValue(buffer) as Array<ESObject>);
        return res2;
      case 131:
        let res3 =  PlaybackSpeedMessage.fromList(super.readValue(buffer) as Array<ESObject>);
        return res3;
      case 132:
        let res4 =  PositionMessage.fromList(super.readValue(buffer) as Array<ESObject>);
        return res4;
      case 133:
        let res5 =  TextureMessage.fromList(super.readValue(buffer) as Array<ESObject>);
        return res5;
      case 134:
        let res6 =  VolumeMessage.fromList(super.readValue(buffer) as Array<ESObject>);
        return res6;
      default:
        let res7: ESObject = super.readValueOfType(type, buffer);
        return res7;
    }
  }

  writeValue(stream: ByteBuffer, value: ESObject): ESObject {
    if (value instanceof CreateMessage) {
      stream.writeInt8(-128);
      return this.writeValue(stream, (value as CreateMessage).toList());
    } else if (value instanceof LoopingMessage) {
      stream.writeInt8(-127);
      return this.writeValue(stream, (value as LoopingMessage).toList());
    } else if (value instanceof MixWithOthersMessage) {
      stream.writeInt8(-126);
      return this.writeValue(stream, (value as MixWithOthersMessage).toList());
    } else if (value instanceof PlaybackSpeedMessage) {
      stream.writeInt8(-125);
      return this.writeValue(stream, (value as PlaybackSpeedMessage).toList());
    } else if (value instanceof PositionMessage) {
      stream.writeInt8(-124);
      return this.writeValue(stream, (value as PositionMessage).toList());
    } else if (value instanceof TextureMessage) {
      stream.writeInt8(-123);
      return this.writeValue(stream, (value as TextureMessage).toList());
    } else if (value instanceof VolumeMessage) {
      stream.writeInt8(-122);
      return this.writeValue(stream, (value as VolumeMessage).toList());
    } else {
      return super.writeValue(stream, value);
    }
  }
}