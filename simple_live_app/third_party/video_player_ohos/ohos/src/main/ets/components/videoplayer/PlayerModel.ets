// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.

import { CommonConstants } from './constants/CommonConstants';
import { PlayConstants } from './constants/PlayConstants';


@Observed
export class PlayerModel {
  videoHeight: string = PlayConstants.PLAY_PLAYER_HEIGHT;
  videoWidth: string = CommonConstants.FULL_PERCENT;
  videoMargin: string = PlayConstants.MARGIN_ZERO;
  videoPosition: FlexAlign = FlexAlign.Center;
  playSpeed: number = PlayConstants.PLAY_SPEED;
  volume: number = PlayConstants.VOLUME;
  volumeShow: boolean = PlayConstants.VOLUME_SHOW;
  bright: number = PlayConstants.BRIGHT;
  brightShow: boolean = PlayConstants.BRIGHT_SHOW;
  currentTime: string = PlayConstants.PROGRESS_CURRENT_TIME;
  totalTime: string = PlayConstants.PROGRESS_TOTAL_TIME;
  progressVal: number = PlayConstants.PROGRESS_PROGRESS_VAL;
}