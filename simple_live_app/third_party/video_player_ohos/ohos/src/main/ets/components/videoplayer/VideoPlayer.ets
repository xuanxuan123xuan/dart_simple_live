// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on VideoPlayer.java originally written by
// Copyright 2013 The Flutter Authors.

import media from '@ohos.multimedia.media';
import prompt from '@ohos.promptAction';
import resourceManager from '@ohos.resourceManager';
import window from '@ohos.window';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { SurfaceTextureEntry } from '@ohos/flutter_ohos/src/main/ets/view/TextureRegistry';
import image from '@ohos.multimedia.image';
import { AvplayerStatus, CommonConstants, Events, SliderMode } from './constants/CommonConstants';
import { PlayConstants } from './constants/PlayConstants';

import { PlayerModel } from './PlayerModel';
import DateFormatUtil from './util/DateFormatUtil';
import { GlobalContext } from './util/GlobalContext';
import { VideoItem } from './VideoItem';
import { BusinessError } from '@ohos.base';
import { EventChannel } from '@ohos/flutter_ohos';
import { EventSink, StreamHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { QueuingEventSink } from './QueuingEventSink';
import { ArrayList, HashMap } from '@kit.ArkTS';
import { audio } from '@kit.AudioKit';
import fs from '@ohos.file.fs';

const FORMAT_SS: String = 'ss';
const FORMAT_DASH: String = 'dash';
const FORMAT_HLS: String = 'hls';
const FORMAT_OTHER: String = 'other';

const SOURCE_ASSIGNMENT_IDLE: string = 'idle';
const SOURCE_ASSIGNMENT_ASSIGNING: string = 'assigning';
const SOURCE_ASSIGNMENT_ASSIGNED: string = 'assigned';
const SOURCE_ASSIGNMENT_FAILED: string = 'failed';
const SOURCE_KIND_DIRECT_URL: string = 'directUrl';
const SOURCE_KIND_MEDIA_SOURCE_WITH_HEADERS: string = 'mediaSourceWithHeaders';
const SOURCE_KIND_RAW_FILE: string = 'rawFile';
const OPERATE_ERROR: number = 801;
const AVPLAYER_STATE_ERROR: number = 5400102;

const TAG = 'VideoPlayer'
export class VideoPlayer {
  private avPlayer: media.AVPlayer | null = null;
  public playerModel: PlayerModel | null = null;
  private duration: number = 0;
  private status: number = -1;
  private loop: boolean = false;
  private index: number = 0;
  private rawFile?: resourceManager.RawFileDescriptor | null = {} as resourceManager.RawFileDescriptor;
  private url: string | null = null;
  private surfaceId: string = '';
  private seekTime: number = PlayConstants.PROGRESS_SEEK_TIME;
  private positionX: number = PlayConstants.POSITION_X;
  private positionY: number = PlayConstants.POSITION_Y;
  private textureEntry: SurfaceTextureEntry;
  private eventChannel: EventChannel | null = null;
  private eventSink: QueuingEventSink | null = null;
  private interruptMode: audio.InterruptMode = audio.InterruptMode.INDEPENDENT_MODE;
  private fd: number = -1;
  private headers: Record<string, string> | null;
  private playerGeneration: number = 0;
  private sourceAssignmentState: string = SOURCE_ASSIGNMENT_IDLE;
  private sourceKind: string = SOURCE_KIND_RAW_FILE;
  private prepared: boolean = false;
  private firstFrameRendered: boolean = false;
  private disposed: boolean = false;

  constructor(playerModel: PlayerModel, textureEntry: SurfaceTextureEntry, rawFile: resourceManager.RawFileDescriptor | null, url: string | null, eventChannel: EventChannel, AudioFocus: Boolean, headers: Record<string, string> | null) {
    this.playerModel = playerModel;
    this.textureEntry = textureEntry;
    this.playerGeneration = textureEntry.getTextureId();
    this.surfaceId = textureEntry.getSurfaceId().toString();
    this.rawFile = rawFile;
    this.url = url;
    this.eventChannel = eventChannel;
    this.headers = headers;
    this.sourceKind = this.resolveSourceKind();
    if (AudioFocus == true) {
      this.interruptMode = audio.InterruptMode.SHARE_MODE;
      Log.i(TAG, "set interruptMode : " + this.interruptMode);
    }
    Log.i(TAG, "surfaceId : " + this.surfaceId);
  }

  /**
   * Creates a videoPlayer object.
   */
  async createAVPlayer() {
    Log.i(TAG + ":" + this.textureEntry.getTextureId(), " createAVPlayer");
    if (this.avPlayer == null) {
      const creationGeneration = this.playerGeneration;
      const createdPlayer = await media.createAVPlayer();
      if (this.disposed || creationGeneration !== this.playerGeneration || this.avPlayer != null) {
        createdPlayer.release();
        return;
      }
      this.avPlayer = createdPlayer;
    }
    if (this.avPlayer != null) {
      this.eventSink = new QueuingEventSink();
      Log.i(TAG, "enter setStreamHandler");
      this.eventChannel?.setStreamHandler(
        new StreamHandlerImpl(this.eventSink)
      );

      await this.bindState();

      await this.assignMediaSourceIfNeeded(this.playerGeneration);
    }
  }

  private hasRequestHeaders(): boolean {
    return this.headers != null && Object.keys(this.headers).length > 0;
  }

  private resolveSourceKind(): string {
    if (this.url == null) {
      return SOURCE_KIND_RAW_FILE;
    }
    return this.hasRequestHeaders() ?
      SOURCE_KIND_MEDIA_SOURCE_WITH_HEADERS : SOURCE_KIND_DIRECT_URL;
  }

  private isCurrentGeneration(generation: number, player: media.AVPlayer): boolean {
    return !this.disposed && generation === this.playerGeneration && this.avPlayer === player;
  }

  private beginNewSourceGeneration(): void {
    this.playerGeneration += 1;
    this.sourceAssignmentState = SOURCE_ASSIGNMENT_IDLE;
    this.sourceKind = this.resolveSourceKind();
    this.prepared = false;
    this.firstFrameRendered = false;
  }

  private async assignMediaSourceIfNeeded(generation: number): Promise<void> {
    const player = this.avPlayer;
    if (player == null || !this.isCurrentGeneration(generation, player)) {
      return;
    }
    if (this.sourceAssignmentState === SOURCE_ASSIGNMENT_ASSIGNING ||
      this.sourceAssignmentState === SOURCE_ASSIGNMENT_ASSIGNED) {
      return;
    }
    this.sourceAssignmentState = SOURCE_ASSIGNMENT_ASSIGNING;
    this.sourceKind = this.resolveSourceKind();
    Log.i(TAG, `source assigning generation=${generation} kind=${this.sourceKind}`);
    try {
      if (this.url == null) {
        player.fdSrc = this.rawFile!;
      } else if (this.sourceKind === SOURCE_KIND_DIRECT_URL) {
        player.url = this.getIUri();
      } else {
        let mediaSource: media.MediaSource = media.createMediaSourceWithUrl(
          this.getIUri(), this.headers ?? {});
        let playbackStrategy: media.PlaybackStrategy = {};
        await player.setMediaSource(mediaSource, playbackStrategy);
      }
      if (!this.isCurrentGeneration(generation, player)) {
        return;
      }
      this.sourceAssignmentState = SOURCE_ASSIGNMENT_ASSIGNED;
      Log.i(TAG, `source assigned generation=${generation} kind=${this.sourceKind}`);
    } catch (error) {
      if (!this.isCurrentGeneration(generation, player)) {
        return;
      }
      this.sourceAssignmentState = SOURCE_ASSIGNMENT_FAILED;
      const nativeError = error as BusinessError;
      Log.e(TAG, `source failed generation=${generation} kind=${this.sourceKind} code=${nativeError.code}`);
      this.sendError(nativeError);
    }
  }

  /**
   * AVPlayer binding event.
   */
  async bindState() {
    Log.i(TAG, "enter bindState");
    if (this.avPlayer == null) {
      Log.e(TAG, "bindState, avPlayer is null");
      return;
    }
    const boundPlayer = this.avPlayer;
    this.avPlayer.on(Events.STATE_CHANGE, async (state: media.AVPlayerState) => {
      let avplayerStatus: string = state;
      Log.i(TAG, "bindState, on avPlayer, step1");
      if (this.disposed || this.avPlayer == null || this.avPlayer !== boundPlayer) {
        Log.i(TAG, "ignore stale avPlayer state callback");
        return;
      }
      Log.i(TAG, "bindState, on STATE_CHANGE, avplayerStatus=" + avplayerStatus);
      switch (avplayerStatus) {
        case AvplayerStatus.IDLE:
          this.resetProgress();
          await this.assignMediaSourceIfNeeded(this.playerGeneration);
          break;
        case AvplayerStatus.INITIALIZED:
          this.avPlayer.surfaceId = this.surfaceId;
          this.avPlayer.prepare();
          break;
        case AvplayerStatus.PREPARED:
          this.prepared = true;
          this.avPlayer.videoScaleType = 0;
          this.avPlayer.audioInterruptMode = this.interruptMode;
          this.setVideoSize();
          this.sendInitialized();
          this.duration = this.avPlayer.duration;
          break;
        case AvplayerStatus.PLAYING:
          this.status = CommonConstants.STATUS_START;
          this.watchStatus();
          Log.i(TAG, `playing generation=${this.playerGeneration}`);
          break;
        case AvplayerStatus.PAUSED:
          this.status = CommonConstants.STATUS_PAUSE;
          this.watchStatus();
          break;
        case AvplayerStatus.COMPLETED:
          if (this.playerModel != null) {
            this.playerModel.playSpeed = PlayConstants.PLAY_SPEED;
          }
          this.sendCompleted();
          this.duration = PlayConstants.PLAYER_DURATION;
          if (!this.loop) {
            let globalVideoListObj = GlobalContext.getContext().getObject('globalVideoList');
            if (globalVideoListObj != null && (globalVideoListObj as VideoItem[]).length > 0) {
              let globalVideoList = globalVideoListObj as VideoItem[];
              let curIndex = this.index + PlayConstants.PLAYER_NEXT;
              this.index = (curIndex === globalVideoList.length) ? PlayConstants.PLAYER_FIRST : curIndex;
              if (this.url) {
                this.url = globalVideoList[this.index].iSrc;
              } else {
                this.rawFile = globalVideoList[this.index].src;
              }
            }
          }
          break;
        case AvplayerStatus.RELEASED:
          this.avPlayer = null;
          this.status = CommonConstants.STATUS_STOP;
          this.watchStatus();
          Log.i(TAG, '[PlayVideoModel] state released called')
          break;
        default:
          Log.i(TAG, '[PlayVideoModel] unKnown state: ' + state);
          break;
      }
    });

    this.avPlayer.on(Events.TIME_UPDATE, (time: number) => {
      this.initProgress(time);
    });

    this.avPlayer.on(Events.BUFFER_UPDATE, (infoType: media.BufferingInfoType, value: number) => {
      this.sendBufferingUpdate(infoType, value);
    });

    this.avPlayer.on(Events.START_RENDER_FRAME, () => {
      if (this.disposed || this.avPlayer !== boundPlayer) {
        return;
      }
      this.firstFrameRendered = true;
      Log.i(TAG, `first frame generation=${this.playerGeneration}`);
    });

    this.avPlayer.on(Events.ERROR, (err: BusinessError) => {
      if (this.disposed || this.avPlayer !== boundPlayer) {
        return;
      }
      // video_player applies looping after initialization. HarmonyOS reports
      // that unsupported operation for live streams as 801, and can also emit
      // a transient state error while applying adjacent controller settings.
      // Once this source is prepared these errors do not invalidate playback;
      // the progress watchdog remains responsible for detecting a real stall.
      if (this.shouldIgnorePreparedPlaybackError(err)) {
        Log.w(TAG, `ignore non-fatal native error code=${err.code} state=${this.avPlayer?.state ?? 'released'} generation=${this.playerGeneration}`);
        return;
      }
      Log.e(TAG, `native error code=${err.code} state=${this.avPlayer?.state ?? 'released'} generation=${this.playerGeneration}`);
      this.sendError(err);
    })
  }

  private shouldIgnorePreparedPlaybackError(error: BusinessError): boolean {
    if (!this.prepared || this.sourceAssignmentState !== SOURCE_ASSIGNMENT_ASSIGNED) {
      return false;
    }
    return error.code === OPERATE_ERROR || error.code === AVPLAYER_STATE_ERROR;
  }

  /**
   * Release the video player.
   */
  release() {
    this.disposed = true;
    this.playerGeneration += 1;
    if (this.avPlayer !== null) {
      this.avPlayer.release();
      this.eventChannel?.setStreamHandler(null);
    }
    if (this.fd >= 0) {
      fs.closeSync(this.fd);
    }
  }


  play() {
    if (this.avPlayer !== null) {
      this.avPlayer.play();
    }
  }

  /**
   * Pause Playing.
   */
  pause() {
    if (this.avPlayer !== null) {
      this.avPlayer.pause();
    }
  }

  isPlaying(): boolean {
    return this.avPlayer?.state === AvplayerStatus.PLAYING;
  }

  useOutputSurface(surfaceId: string): void {
    if (this.avPlayer === null || surfaceId.length === 0) {
      throw new Error('Video output surface is unavailable.');
    }
    this.avPlayer.surfaceId = surfaceId;
  }

  restoreOutputSurface(): void {
    this.useOutputSurface(this.surfaceId);
  }

  seekTo(position: number) {
    if (this.avPlayer !== null) {
      this.avPlayer.seek(position, media.SeekMode.SEEK_CLOSEST);
    }
  }

  getPosition(): number {
    if (this.avPlayer !== null) {
      return this.avPlayer.currentTime;
    } else {
      return 0;
    }
  }

  /**
   * Playback mode. The options are as follows: true: playing a single video; false: playing a cyclic video.
   */
  setLoop() {
    this.loop = !this.loop;
  }

  setLooping(isLooping: boolean) {
    if (this.avPlayer != null && (isLooping || this.avPlayer.duration > 0)) {
      this.avPlayer.loop = isLooping;
    }
    this.loop = isLooping;
  }


  setVolume(volume: number) {
    if (this.avPlayer != null) {
      this.avPlayer.setVolume(volume);
    }
  }

  /**
   * Set the playback speed.
   *
   * @param playSpeed Current playback speed.
   */
  setSpeed(playSpeed: number) {
    if (this.avPlayer == null || this.playerModel == null) {
      return;
    }
    if (CommonConstants.OPERATE_STATE.indexOf(this.avPlayer.state) === -1) {
      return;
    }
    this.playerModel.playSpeed = playSpeed;
    this.avPlayer.setSpeed(this.playerModel.playSpeed);
  }

  /**
   * Previous video.
   */
  previousVideo() {
    if (this.avPlayer == null || this.playerModel == null || this.playerModel == null) {
      return;
    }
    if (CommonConstants.OPERATE_STATE.indexOf(this.avPlayer.state) === -1) {
      return;
    }
    this.playerModel.playSpeed = PlayConstants.PLAY_SPEED;
    let globalVideoListObj = GlobalContext.getContext().getObject('globalVideoList');
    if (globalVideoListObj == null || (globalVideoListObj as VideoItem[]).length === 0) {
      return;
    }
    let globalVideoList = globalVideoListObj as VideoItem[];
    let curIndex = this.index - PlayConstants.CONTROL_NEXT;
    this.index = (curIndex === -PlayConstants.CONTROL_NEXT) ?
      (globalVideoList.length - PlayConstants.CONTROL_NEXT) : curIndex;
    if (this.url) {
      this.url = globalVideoList[this.index].iSrc;
    } else {
      this.rawFile = globalVideoList[this.index].src;
    }
    this.beginNewSourceGeneration();
    this.avPlayer.reset();
  }

  /**
   * Next video.
   */
  nextVideo() {
    if (this.avPlayer == null || this.playerModel == null) {
      return;
    }
    if (CommonConstants.OPERATE_STATE.indexOf(this.avPlayer.state) === -1) {
      return;
    }
    this.playerModel.playSpeed = PlayConstants.PLAY_SPEED;
    let globalVideoListObj = GlobalContext.getContext().getObject('globalVideoList');
    if (globalVideoListObj == null || (globalVideoListObj as VideoItem[]).length === 0) {
      return;
    }
    let globalVideoList = globalVideoListObj as VideoItem[];
    let curIndex = this.index + PlayConstants.CONTROL_NEXT;
    this.index = (curIndex === globalVideoList.length) ?
    PlayConstants.CONTROL_FIRST : curIndex;
    if (this.url) {
      this.url = globalVideoList[this.index].iSrc;
    } else {
      this.rawFile = globalVideoList[this.index].src;
    }
    this.beginNewSourceGeneration();
    this.avPlayer.reset();
  }

  /**
   * Switching Between Video Play and Pause.
   */
  switchPlayOrPause() {
    if (this.avPlayer == null || this.playerModel == null) {
      return;
    }
    if (this.status === CommonConstants.STATUS_START) {
      this.avPlayer.pause();
    } else {
      this.avPlayer.play();
    }
  }

  /**
   * Slide the progress bar to set the playback progress.
   *
   * @param value Value of the slider component.
   * @param mode Slider component change event.
   */
  setSeekTime(value: number, mode: SliderChangeMode) {
    if (this.avPlayer == null || this.playerModel == null) {
      return;
    }
    if (mode === Number(SliderMode.MOVING)) {
      this.playerModel.progressVal = value;
      this.playerModel.currentTime = DateFormatUtil.secondToTime(Math.floor(value * this.duration /
      CommonConstants.ONE_HUNDRED / CommonConstants.A_THOUSAND));
    }
    if (mode === Number(SliderMode.END) || mode === Number(SliderMode.CLICK)) {
      this.seekTime = value * this.duration / CommonConstants.ONE_HUNDRED;
      if (this.avPlayer !== null) {
        this.avPlayer.seek(this.seekTime, media.SeekMode.SEEK_PREV_SYNC);
      }
    }
  }

  /**
   * Setting the brightness.
   */
  setBright() {
    if (this.playerModel == null) {
      return;
    }
    let windowClass = GlobalContext.getContext().getObject('windowClass') as window.Window;
    windowClass.setWindowBrightness(this.playerModel.bright);
  }

  /**
   * Obtains the current video playing status.
   */
  getStatus() {
    return this.status;
  }

  /**
   * Initialization progress bar.
   *
   * @param time Current video playback time.
   */
  initProgress(time: number) {
    if (this.playerModel == null) {
      return;
    }
    let nowSeconds = Math.floor(time / CommonConstants.A_THOUSAND);
    let totalSeconds = Math.floor(this.duration / CommonConstants.A_THOUSAND);
    this.playerModel.currentTime = DateFormatUtil.secondToTime(nowSeconds);
    this.playerModel.totalTime = DateFormatUtil.secondToTime(totalSeconds);
    // 直播流 duration 为 0 时，totalSeconds<=0 会导致除零产生 NaN，进度条直接置 0。
    if (totalSeconds <= 0) {
      this.playerModel.progressVal = 0;
      return;
    }
    this.playerModel.progressVal = Math.floor(nowSeconds * CommonConstants.ONE_HUNDRED / totalSeconds);
  }

  /**
   * Reset progress bar data.
   */
  resetProgress() {
    if (this.playerModel == null) {
      return;
    }
    this.seekTime = PlayConstants.PROGRESS_SEEK_TIME;
    this.playerModel.currentTime = PlayConstants.PROGRESS_CURRENT_TIME;
    this.playerModel.progressVal = PlayConstants.PROGRESS_PROGRESS_VAL;
  }

  /**
   * Volume gesture method onActionStart.
   *
   * @param event Gesture event.
   */
  onVolumeActionStart(event?: GestureEvent) {
    if (!event) {
      return;
    }
    this.positionX = event.offsetX;
  }

  /**
   * Bright gesture method onActionStart.
   *
   * @param event Gesture event.
   */
  onBrightActionStart(event?: GestureEvent) {
    if (!event) {
      return;
    }
    this.positionY = event.offsetY;
  }

  /**
   * Gesture method onActionUpdate.
   *
   * @param event Gesture event.
   */
  onVolumeActionUpdate(event?: GestureEvent) {
    if (!event) {
      return;
    }
    if (this.avPlayer == null || this.playerModel == null) {
      return;
    }
    if (CommonConstants.OPERATE_STATE.indexOf(this.avPlayer.state) === -1) {
      return;
    }
    if (this.playerModel.brightShow === false) {
      this.playerModel.volumeShow = true;
      let screenWidth = GlobalContext.getContext().getObject('screenWidth') as number;
      let changeVolume = (event.offsetX - this.positionX) / screenWidth;
      let volume: number = this.playerModel.volume;
      let currentVolume = volume + changeVolume;
      let volumeMinFlag = currentVolume <= PlayConstants.MIN_VALUE;
      let volumeMaxFlag = currentVolume > PlayConstants.MAX_VALUE;
      this.playerModel.volume = volumeMinFlag ? PlayConstants.MIN_VALUE :
        (volumeMaxFlag ? PlayConstants.MAX_VALUE : currentVolume);
      this.avPlayer.setVolume(this.playerModel.volume);
      this.positionX = event.offsetX;
    }
  }

  /**
   * Gesture method onActionUpdate.
   *
   * @param event Gesture event.
   */
  onBrightActionUpdate(event?: GestureEvent) {
    if (!event || this.playerModel == null) {
      return;
    }
    if (this.playerModel.volumeShow === false) {
      this.playerModel.brightShow = true;
      let screenHeight = GlobalContext.getContext().getObject('screenHeight') as number;
      let changeBright = (this.positionY - event.offsetY) / screenHeight;
      let bright: number = this.playerModel.bright;
      let currentBright = bright + changeBright;
      let brightMinFlag = currentBright <= PlayConstants.MIN_VALUE;
      let brightMaxFlag = currentBright > PlayConstants.MAX_VALUE;
      this.playerModel.bright = brightMinFlag ? PlayConstants.MIN_VALUE :
        (brightMaxFlag ? PlayConstants.MAX_VALUE : currentBright);
      this.setBright();
      this.positionY = event.offsetY;
    }
  }

  /**
   * Gesture method onActionEnd.
   */
  onActionEnd() {
    setTimeout(() => {
      if (this.playerModel) {
        this.playerModel.volumeShow = false;
        this.playerModel.brightShow = false;
      }
      this.positionX = PlayConstants.POSITION_X;
      this.positionY = PlayConstants.POSITION_Y;
    }, PlayConstants.DISAPPEAR_TIME);
  }

  /**
   * Sets whether the screen is a constant based on the playback status.
   */
  watchStatus() {
    let windowClass = GlobalContext.getContext().getObject('windowClass') as window.Window;
    if (this.status === CommonConstants.STATUS_START) {
      windowClass.setWindowKeepScreenOn(true);
    } else {
      windowClass.setWindowKeepScreenOn(false);
    }
  }

  /**
   * Sets the playback page size based on the video size.
   */
  setVideoSize() {
    if (this.avPlayer == null || this.playerModel == null) {
      return;
    }
    if (this.avPlayer.height > this.avPlayer.width) {
      this.playerModel.videoWidth = PlayConstants.PLAY_PLAYER_HEIGHT_FULL;
      this.playerModel.videoHeight = PlayConstants.PLAY_PLAYER_HEIGHT_FULL;
      this.playerModel.videoPosition = FlexAlign.Start;
      this.playerModel.videoMargin = PlayConstants.HEIGHT;
    } else {
      this.playerModel.videoWidth = CommonConstants.FULL_PERCENT;
      this.playerModel.videoHeight = PlayConstants.PLAY_PLAYER_HEIGHT;
      this.playerModel.videoPosition = FlexAlign.Center;
      this.playerModel.videoMargin = PlayConstants.MARGIN_ZERO;
    }
  }

  /**
   * An error is reported during network video playback.
   */
  playError() {
    prompt.showToast({
      duration: PlayConstants.PLAY_ERROR_TIME,
      message: $r('app.string.link_check_address_internet')
    });
  }

  sendInitialized(): void {
    Log.i(TAG, "sendInitialized")
    let event: HashMap<string, Object> = new HashMap<string, Object>();
    event.set("event", "initialized");
    event.set("duration", this.avPlayer?.duration);
    event.set("width", this.avPlayer?.width);
    event.set("height", this.avPlayer?.height);
    this.eventSink?.success(event);
  }

  sendCompleted(): void {
    let event: HashMap<string, Object> = new HashMap<string, Object>();
    event.set("event", "completed");
    this.eventSink?.success(event);
  }

  sendBufferingUpdate(infoType: media.BufferingInfoType, bufferingPosition: number): void {
    let event: HashMap<string, Object> = new HashMap<string, Object>();
    if (infoType == media.BufferingInfoType.BUFFERING_START) {
      event.set("event", "bufferingStart");
    } else if (infoType == media.BufferingInfoType.BUFFERING_END) {
      event.set("event", "bufferingEnd");
    } else if (infoType == media.BufferingInfoType.CACHED_DURATION) {
      event.set("event", "cachedDuration");
      // 与 bufferingUpdate 保持一致，带上实际缓存时长（毫秒）。
      let range: ArrayList<number> = new ArrayList<number>();
      range.add(0);
      range.add(bufferingPosition);
      let valuesList: ArrayList<ArrayList<number>> = new ArrayList<ArrayList<number>>();
      valuesList.add(range);
      event.set("values", valuesList);
    } else {
      event.set("event", "bufferingUpdate");
      let range: ArrayList<number> = new ArrayList<number>();
      range.add(0);
      range.add(bufferingPosition);
      let valuesList: ArrayList<ArrayList<number>> = new ArrayList<ArrayList<number>>();
      valuesList.add(range);
      event.set("values", valuesList);
    }
    this.eventSink?.success(event);
  }

  sendError(error: BusinessError): void {
    let details: HashMap<string, Object> = new HashMap<string, Object>();
    details.set("nativeErrorCode", error.code);
    details.set("nativeState", this.avPlayer?.state ?? AvplayerStatus.RELEASED);
    details.set("sourceAssignmentState", this.sourceAssignmentState);
    details.set("sourceKind", this.sourceKind);
    details.set("prepared", this.prepared);
    details.set("firstFrameRendered", this.firstFrameRendered);
    this.eventSink?.error("videoError", `HarmonyOS AVPlayer error ${error.code}`, details);
  }

  getIUri(): string {
    let iUrl = this.url;
    const ohosFilePrefix = 'file://';
    if (iUrl != null && iUrl.startsWith(ohosFilePrefix)) {
      if (this.fd >= 0) {
        try {
          fs.closeSync(this.fd);
        } catch (error) {
          Log.e(TAG, "close previous fd failed: " + JSON.stringify(error));
        }
        this.fd = -1;
      }
      this.fd = fs.openSync(iUrl, fs.OpenMode.READ_ONLY).fd;
      iUrl = `fd://${this.fd.toString()}`;
    }
    return iUrl ?? '';
  }
}

class StreamHandlerImpl implements StreamHandler {
  private eventSink: QueuingEventSink | null = null;

  constructor(eventSink: QueuingEventSink) {
    this.eventSink = eventSink;
  }

  onListen(args: Object, events: EventSink): void {
    this.eventSink?.setDelegate(events);
  }

  onCancel(args: Object): void {
    this.eventSink?.setDelegate(null);
  }
}
