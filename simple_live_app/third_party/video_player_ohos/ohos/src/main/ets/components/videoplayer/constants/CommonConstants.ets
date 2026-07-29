// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.

import resourceManager from '@ohos.resourceManager';
import { VideoItem } from '../VideoItem';
import { VideoSpeed } from '../VideoSpeed';

/**
 * Common constants for all features.
 */
export class CommonConstants {
  /**
   * Full percent.
   */
  static readonly FULL_PERCENT: string = '100%';
  /**
   * Ninety percent.
   */
  static readonly NINETY_PERCENT: string = '90%';
  /**
   * Fifty percent.
   */
  static readonly FIFTY_PERCENT: string = '50%';
  /**
   * Playback page path.
   */
  static readonly PAGE: string = 'pages/PlayPage';
  /**
   * Local video ID.
   */
  static readonly TYPE_LOCAL: number = 0;
  /**
   * Network video ID.
   */
  static readonly TYPE_INTERNET: number = 1;
  /**
   * Start playing.
   */
  static readonly STATUS_START: number = 1;
  /**
   * Playing Pause.
   */
  static readonly STATUS_PAUSE: number = 2;
  /**
   * Stop Playing.
   */
  static readonly STATUS_STOP: number = 3;
  /**
   * Width-height ratio.
   */
  static readonly ASPECT_RATIO: number = 1;
  /**
   * One hundred.
   */
  static readonly ONE_HUNDRED: number = 100;
  /**
   * A thousand.
   */
  static readonly A_THOUSAND: number = 1000;
  /**
   * Attribute Value is 'yes'
   */
  static readonly YES: string = 'yes';
  /**
   * Speed set.
   */
  static readonly SPEED_ARRAY: VideoSpeed[] = [
    new VideoSpeed('0.75X', 0),
    new VideoSpeed('1.0X', 1),
    new VideoSpeed('1.25X', 2),
    new VideoSpeed('1.75X', 3),
    new VideoSpeed('2.0X', 4)
  ];
  /**
   * time system, Hour-minute-second conversion.
   */
  static readonly TIME_UNIT: number = 60;
  /**
   * Initial Time UNIT.
   */
  static readonly INITIAL_TIME_UNIT: string = '00';
  /**
   * Zero padding, 2 bits.
   */
  static readonly PADDING_LENGTH: number = 2;
  /**
   * String zero padding.
   */
  static readonly PADDING_STR: string = '0';
  /**
   * Breath screen status.
   */
  static readonly SCREEN_OFF: string = 'usual.event.SCREEN_OFF';
  /**
   * Operation status of video player 4.
   */
  static readonly OPERATE_STATE: Array<string> = ['prepared', 'playing', 'paused', 'completed'];
}

/**
 * Player component status.
 */
export enum AvplayerStatus {
  IDLE = 'idle',
  INITIALIZED = 'initialized',
  PREPARED = 'prepared',
  PLAYING = 'playing',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  STOPPED = 'stopped',
  RELEASED = 'released',
  ERROR = 'error'
}

/**
 * AVPlayer binding event.
 */
export enum Events {
  STATE_CHANGE = 'stateChange',
  TIME_UPDATE = 'timeUpdate',
  BUFFER_UPDATE = 'bufferingUpdate',
  ERROR = 'error'
}

/**
 * Slider mode.
 */
export enum SliderMode {
  MOVING = 1,
  END = 2,
  CLICK = 3
}

/**
 * Video object collection.
 */
export const VIDEO_DATA: VideoItem[] = [
  new VideoItem('video1', {} as resourceManager.RawFileDescriptor, 'video1.mp4',),
  new VideoItem('video2', {} as resourceManager.RawFileDescriptor, 'video2.mp4',)
]