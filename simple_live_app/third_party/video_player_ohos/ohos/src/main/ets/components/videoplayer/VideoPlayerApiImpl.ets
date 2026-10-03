// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.

import { FlutterPlugin, FlutterPluginBinding} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import BasicMessageChannel, { Reply } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BasicMessageChannel';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { FlutterRenderer } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/renderer/FlutterRenderer';
import { SurfaceTextureEntry } from '@ohos/flutter_ohos/src/main/ets/view/TextureRegistry';
import { VideoPlayer } from './VideoPlayer';
import { VideoItem } from './VideoItem';
import { VideoPlayerApi } from './VideoPlayerApi';
import { CommonConstants } from './constants/CommonConstants';
import { CreateMessage, LoopingMessage,
  MixWithOthersMessage,
  PlaybackSpeedMessage,
  PositionMessage,
  TextureMessage, VolumeMessage,
  wrapError } from './Messages';
import { PlayerModel } from './PlayerModel';
import HashMap from '@ohos.util.HashMap';
import { VideoPlayerApiCodec } from './VideoPlayerApiCodec';
import { FlutterState } from './VideoPlayerPlugin';
import resourceManager from '@ohos.resourceManager';
import common from '@ohos.app.ability.common';
import { media } from '@kit.MediaKit';
import { EventChannel } from '@ohos/flutter_ohos';
import { GlobalContext } from './util/GlobalContext';
import { window } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { OhosPipManager } from './OhosPipManager';

const TAG: string = "VideoPlayerApiImpl";
export class VideoPlayerApiImpl {
  private videoPlayers: HashMap<String, VideoPlayer> = new HashMap<String, VideoPlayer>();
  private flutterState: FlutterState | null = null;
  private binding: AbilityPluginBinding | null = null;
  private AudioFocus: Boolean = false;
  private pixelMaps: HashMap<string, image.PixelMap> = new HashMap();
  private pipManager: OhosPipManager | null = null;

  constructor(flutterState: FlutterState | null, binding: AbilityPluginBinding | null) {
    this.flutterState = flutterState;
    this.binding = binding;
    if (binding != null) {
      this.pipManager = new OhosPipManager(binding.getAbility().context);
    }
  }

  private disposeAllPlayers(): void {
    this.videoPlayers.forEach(videoPlayer => {
      if (videoPlayer != null) {
        this.pipManager?.clearPlayer(videoPlayer);
        videoPlayer.release();
      }
    });
    this.videoPlayers.clear();
    this.releasePixelMaps();
  }

  private releasePixelMaps(): void {
    this.pixelMaps.forEach((pixelMap: image.PixelMap) => {
      try {
        pixelMap.release();
      } catch (error) {
        Log.w(TAG, `Failed to release pixelMap: ${error}`);
      }
    });
    this.pixelMaps.clear();
  }

  initialize(): void {
    Log.i(TAG, "enter initialize")
    this.disposeAllPlayers();
  }

  detach(): void {
    Log.i(TAG, "enter detach")
    this.disposeAllPlayers();
    this.pipManager?.detach();
  }

  getContext(): common.UIAbilityContext {
    if (this.binding == null) {
      throw Error("Illegal binding or context state.");
    }
    return this.binding.getAbility().context;
  }

  async create(arg: CreateMessage): Promise<TextureMessage> {
    let windowClass = await window.getLastWindow(this.getContext())
    GlobalContext.getContext().setObject("windowClass", windowClass)
    GlobalContext.getContext().setObject("globalVideoList", new Array<VideoItem>())
    Log.i(TAG, "enter create");
    if (this.flutterState == null) {
      throw new Error("Illegal flutterState null.");
    }
    let playerModel = new PlayerModel();
    let flutterRenderer = this.flutterState.getTextureRegistry();
    let uri: string = arg.getUri();
    let asset: string = arg.getAsset();
    let playbackProfile: string = arg.getPlaybackProfile().toString();
    let appPlayerGeneration: number | null =
      arg.getAppPlayerGeneration()?.valueOf() ?? null;
    let header: Record<string, string> | null = null;
    arg.getHttpHeaders().forEach((value, key) => {
      if (!header) {
        header = {}
      }
      header[key.toString()] = value.toString();
    })
    let textureId: number = flutterRenderer.getTextureId();
    Log.i(TAG, "create textureId=" + textureId +
      " profile=" + playbackProfile +
      " appGeneration=" + (appPlayerGeneration ?? "none"));
    let surfaceTextureEntry: SurfaceTextureEntry = flutterRenderer.registerTexture(textureId);
    if (asset != null) {
      Log.i(TAG, "asset create called");
      let avMetaExtractor = await media.createAVMetadataExtractor();
      try {
        avMetaExtractor.fdSrc = await this.getContext().resourceManager.getRawFd("flutter_assets/" + asset);
        let mateData = await avMetaExtractor.fetchMetadata();
        if (mateData.hasVideo == CommonConstants.YES) {
          let avImageGenerator = await media.createAVImageGenerator();
          try {
             Log.i(TAG, "asset video create");
            avImageGenerator.fdSrc = await this.getContext().resourceManager.getRawFd("flutter_assets/" + asset);
            let pixelMap = await avImageGenerator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC, {
              width: -1,
              height: -1
            });
            this.pixelMaps.set(JSON.stringify(arg), pixelMap);
            flutterRenderer.setTextureBackGroundPixelMap(textureId, this.pixelMaps.get(JSON.stringify(arg)));
          } finally {
            avImageGenerator.release();
          }
        }
      } finally {
        avMetaExtractor.release();
      }
    } else if (uri != null && uri.startsWith("fd://")) {
      Log.i(TAG, "local create called");
      let avMetaExtractor = await media.createAVMetadataExtractor();
      try {
        avMetaExtractor.fdSrc = {
          fd: Number.parseInt(uri.replace("fd://", ""))
        };
        let mateData = await avMetaExtractor.fetchMetadata();
        if (mateData.hasVideo == CommonConstants.YES) {
          let avImageGenerator = await media.createAVImageGenerator();
          try {
             Log.i(TAG, "local video create");
            avImageGenerator.fdSrc = {
              fd: Number.parseInt(uri.replace("fd://", ""))
            };
            let pixelMap = await avImageGenerator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC, {
              width: -1,
              height: -1
            });
            this.pixelMaps.set(JSON.stringify(arg), pixelMap);
            flutterRenderer.setTextureBackGroundPixelMap(textureId, this.pixelMaps.get(JSON.stringify(arg)));
          } finally {
            avImageGenerator.release();
          }
        }
      } finally {
        avMetaExtractor.release();
      }
    }
    let eventChannel: EventChannel = new EventChannel(this.flutterState.getBinaryMessenger(), "flutter.io/videoPlayer/videoEvents" + textureId.toString());
    if (asset != null) {
      let rawFileDescriptor: resourceManager.RawFileDescriptor = await this.getContext().resourceManager.getRawFd("flutter_assets/" + asset);
      let videoPlayer = new VideoPlayer(playerModel, surfaceTextureEntry, rawFileDescriptor, null, eventChannel, this.AudioFocus, null, playbackProfile, appPlayerGeneration);
      await videoPlayer.createAVPlayer();
      this.videoPlayers.set(textureId.toString(), videoPlayer);
      this.pipManager?.setActivePlayer(videoPlayer);
    } else if (uri != null) {
      let videoPlayer = new VideoPlayer(playerModel, surfaceTextureEntry, null, uri, eventChannel, this.AudioFocus, header, playbackProfile, appPlayerGeneration);
      await videoPlayer.createAVPlayer();
      this.videoPlayers.set(textureId.toString(), videoPlayer);
      this.pipManager?.setActivePlayer(videoPlayer);
    }

    let textureMessage = new TextureMessage();
    textureMessage.setTextureId(textureId);
    return textureMessage;
  }

  dispose(arg: TextureMessage): void {
    let videoPlayer = this.videoPlayers.get(arg.getTextureId().toString());
    if (videoPlayer != null) {
      this.pipManager?.clearPlayer(videoPlayer);
    }
    videoPlayer?.release();
    this.flutterState?.getTextureRegistry().unregisterTexture(arg.getTextureId().valueOf());
    this.videoPlayers.remove(arg.getTextureId().toString());
    this.releasePixelMaps();
  }

  setLooping(arg: LoopingMessage) {
    let videoPlayer = this.videoPlayers.get(arg.getTextureId().toString());
    Log.d(TAG, "setLooping, id=" + arg.getTextureId() + ", videoPlayer=" + videoPlayer);
    videoPlayer?.setLooping(arg.getIsLooping());
  }

  setVolume(arg: VolumeMessage) {
    let videoPlayer = this.videoPlayers.get(arg.getTextureId().toString());
    Log.d(TAG, "setVolume, id=" + arg.getTextureId() + ", videoPlayer=" + videoPlayer);
    videoPlayer?.setVolume(arg.getVolume().valueOf());
  }

  setPlaybackSpeed(arg: PlaybackSpeedMessage) {
    let videoPlayer = this.videoPlayers.get(arg.getTextureId().toString());
    Log.d(TAG, "setPlaybackSpeed, id=" + arg.getTextureId() + ", videoPlayer=" + videoPlayer);
    let speed: media.PlaybackSpeed | null = arg.getSpeed();
    if (speed != null) {
      videoPlayer?.setSpeed(speed);
    } else {
      Log.w(TAG, "unsupported playBackSpeed!");
    }
  }

  play(arg: TextureMessage) {
    let videoPlayer = this.videoPlayers.get(arg.getTextureId().toString());
    Log.d(TAG, "play, id=" + arg.getTextureId() + ", videoPlayer=" + videoPlayer);
    if (videoPlayer != null) {
      videoPlayer.play();
      this.pipManager?.syncPlaybackState(videoPlayer);
    } else {
      Log.e(TAG, "play  videoPlayer is null");
    }
  }

  position(arg: TextureMessage): PositionMessage {
    let videoPlayer = this.videoPlayers.get(arg.getTextureId().toString());
    Log.d(TAG, "position, id=" + arg.getTextureId() + ", videoPlayer=" + videoPlayer);
    let positionMessage = new PositionMessage();
    positionMessage.setTextureId(arg.getTextureId());
    positionMessage.setPosition(videoPlayer?.getPosition() ?? 0);
    return positionMessage;
  }

  seekTo(arg: PositionMessage) {
    let videoPlayer = this.videoPlayers.get(arg.getTextureId().toString());
    Log.d(TAG, "seekTo, id=" + arg.getTextureId() + ", videoPlayer=" + videoPlayer);
    videoPlayer?.seekTo(arg.getPosition().valueOf());
  }

  pause(arg: TextureMessage) {
    let videoPlayer = this.videoPlayers.get(arg.getTextureId().toString());
    Log.d(TAG, "pause, id=" + arg.getTextureId() + ", videoPlayer=" + videoPlayer);
    videoPlayer?.pause();
    if (videoPlayer != null) {
      this.pipManager?.syncPlaybackState(videoPlayer);
    }
  }

  setMixWithOthers(arg: MixWithOthersMessage) {
    Log.d(TAG, "set MixWithOthers:" + arg.getMixWithOthers());
    this.AudioFocus = arg.getMixWithOthers();
  }

  setup(binaryMessenger: BinaryMessenger): void {
    let api = this;
    if (this.flutterState == null) {
      return;
    }
    this.pipManager?.setup(binaryMessenger);
    {
      const channel: BasicMessageChannel<Object> = new BasicMessageChannel<Object>(
        binaryMessenger, "dev.flutter.pigeon.OhosVideoPlayerApi.initialize", VideoPlayerApiCodec.INSTANCE);
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          let wrapped = new Array<Object>();
          try {
            api.initialize();
            wrapped.push(new TextureMessage());
            reply.reply(wrapped);
          } catch (err) {
            let wrappedError = wrapError(err);
            reply.reply(wrappedError);
          }
        }
      });
    }
    {
      const channel: BasicMessageChannel<Object> = new BasicMessageChannel<Object>(
        binaryMessenger, "dev.flutter.pigeon.OhosVideoPlayerApi.create", VideoPlayerApiCodec.INSTANCE);
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          let wrapped = new Array<Object>();
          let args = msg as Array<Object>;
          let createMsg = args[0] as CreateMessage;
          try {
            api.create(createMsg).then((textureMessage: TextureMessage) => {
              wrapped.push(textureMessage);
              reply.reply(wrapped);
            }).catch((err: Error) => {
              let wrappedError = wrapError(err);
              reply.reply(wrappedError);
            });
          } catch (err) {
            let wrappedError = wrapError(err);
            reply.reply(wrappedError);
          }
        }
      });
    }
    {
      const channel: BasicMessageChannel<Object> = new BasicMessageChannel<Object>(
        binaryMessenger, "dev.flutter.pigeon.OhosVideoPlayerApi.dispose", VideoPlayerApiCodec.INSTANCE);
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          let wrapped = new Array<Object>();
          let args = msg as Array<Object>;
          let textureMsg = args[0] as TextureMessage;
          try {
            api.dispose(textureMsg);
            wrapped.push(new TextureMessage());
            reply.reply(wrapped);
          } catch (err) {
            let wrappedError = wrapError(err);
            reply.reply(wrappedError);
          }
        }
      });
    }
    {
      const channel: BasicMessageChannel<Object> = new BasicMessageChannel<Object>(
        binaryMessenger, "dev.flutter.pigeon.OhosVideoPlayerApi.setLooping", VideoPlayerApiCodec.INSTANCE);
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          let wrapped = new Array<Object>();
          let args = msg as Array<Object>;
          let loopMsg = args[0] as LoopingMessage;
          try {
            api.setLooping(loopMsg);
            wrapped.push(new TextureMessage());
            reply.reply(wrapped);
          } catch (err) {
            let wrappedError = wrapError(err);
            reply.reply(wrappedError);
          }
        }
      });
    }
    {
      const channel: BasicMessageChannel<Object> = new BasicMessageChannel<Object>(
        binaryMessenger, "dev.flutter.pigeon.OhosVideoPlayerApi.setVolume", VideoPlayerApiCodec.INSTANCE);
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          let wrapped = new Array<Object>();
          let args = msg as Array<Object>;
          let volumeMsg = args[0] as VolumeMessage;
          try {
            api.setVolume(volumeMsg);
            wrapped.push(new TextureMessage());
            reply.reply(wrapped);
          } catch (err) {
            let wrappedError = wrapError(err);
            reply.reply(wrappedError);
          }
        }
      });
    }
    {
      const channel: BasicMessageChannel<Object> = new BasicMessageChannel<Object>(
        binaryMessenger, "dev.flutter.pigeon.OhosVideoPlayerApi.setPlaybackSpeed", VideoPlayerApiCodec.INSTANCE);
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          let wrapped = new Array<Object>();
          let args = msg as Array<Object>;
          let playbackSpeedMsg = args[0] as PlaybackSpeedMessage;
          try {
            api.setPlaybackSpeed(playbackSpeedMsg);
            wrapped.push(new TextureMessage());
            reply.reply(wrapped);
          } catch (err) {
            let wrappedError = wrapError(err);
            reply.reply(wrappedError);
          }
        }
      });
    }
    {
      const channel: BasicMessageChannel<Object> = new BasicMessageChannel<Object>(
        binaryMessenger, "dev.flutter.pigeon.OhosVideoPlayerApi.play", VideoPlayerApiCodec.INSTANCE);
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          let wrapped = new Array<Object>();
          let args = msg as Array<Object>;
          let textureMsg = args[0] as TextureMessage;
          try {
            api.play(textureMsg);
            wrapped.push(new TextureMessage());
            reply.reply(wrapped);
          } catch (err) {
            let wrappedError = wrapError(err);
            reply.reply(wrappedError);
          }
        }
      });
    }
    {
      const channel: BasicMessageChannel<Object> = new BasicMessageChannel<Object>(
        binaryMessenger, "dev.flutter.pigeon.OhosVideoPlayerApi.position", VideoPlayerApiCodec.INSTANCE);
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          let wrapped = new Array<Object>();
          let args = msg as Array<Object>;
          let textureMsg = args[0] as TextureMessage;
          try {
            let positionMessage: PositionMessage = api.position(textureMsg);
            wrapped.push(positionMessage);
            reply.reply(wrapped);
          } catch (err) {
            let wrappedError = wrapError(err);
            reply.reply(wrappedError);
          }
        }
      });
    }
    {
      const channel: BasicMessageChannel<Object> = new BasicMessageChannel<Object>(
        binaryMessenger, "dev.flutter.pigeon.OhosVideoPlayerApi.seekTo", VideoPlayerApiCodec.INSTANCE);
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          let wrapped = new Array<Object>();
          let args = msg as Array<Object>;
          let positionMsg = args[0] as PositionMessage;
          try {
            api.seekTo(positionMsg);
            wrapped.push(new TextureMessage());
            reply.reply(wrapped);
          } catch (err) {
            let wrappedError = wrapError(err);
            reply.reply(wrappedError);
          }
        }
      });
    }
    {
      const channel: BasicMessageChannel<Object> = new BasicMessageChannel<Object>(
        binaryMessenger, "dev.flutter.pigeon.OhosVideoPlayerApi.pause", VideoPlayerApiCodec.INSTANCE);
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          let wrapped = new Array<Object>();
          let args = msg as Array<Object>;
          let textureMsg = args[0] as TextureMessage;
          try {
            api.pause(textureMsg);
            wrapped.push(new TextureMessage());
            reply.reply(wrapped);
          } catch (err) {
            let wrappedError = wrapError(err);
            reply.reply(wrappedError);
          }
        }
      });
    }
    {
      const channel: BasicMessageChannel<Object> = new BasicMessageChannel<Object>(
        binaryMessenger, "dev.flutter.pigeon.OhosVideoPlayerApi.setMixWithOthers", VideoPlayerApiCodec.INSTANCE);
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          let wrapped = new Array<Object>();
          let args = msg as Array<Object>;
          let mixWithOthersMsg = args[0] as MixWithOthersMessage;
          try {
            api.setMixWithOthers(mixWithOthersMsg);
            wrapped.push(new TextureMessage());
            reply.reply(wrapped);
          } catch (err) {
            let wrappedError = wrapError(err);
            reply.reply(wrappedError);
          }
        }
      });
    }
  }

}
