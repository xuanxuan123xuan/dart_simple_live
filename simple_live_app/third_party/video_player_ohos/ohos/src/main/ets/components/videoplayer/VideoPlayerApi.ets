// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.

import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { CreateMessage, LoopingMessage,
  MixWithOthersMessage,
  PlaybackSpeedMessage,
  PositionMessage,
  TextureMessage, VolumeMessage } from './Messages';
import { FlutterState } from './VideoPlayerPlugin';

export interface  VideoPlayerApi {
  initialize(): void;

  create(arg: CreateMessage) : TextureMessage;

  dispose(arg: TextureMessage): void;

  setLooping(arg: LoopingMessage): void;

  setVolume(arg: VolumeMessage): void;

  setPlaybackSpeed(arg: PlaybackSpeedMessage): void;

  play(arg: TextureMessage): void;

  position(arg: TextureMessage): PositionMessage;

  seekTo(arg: PositionMessage): void;

  pause(arg: TextureMessage): void;

  setMixWithOthers(arg: MixWithOthersMessage): void;

  setUp(flutterState: FlutterState): void;
}