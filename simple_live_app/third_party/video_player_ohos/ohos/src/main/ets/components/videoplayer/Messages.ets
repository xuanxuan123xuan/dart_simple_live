// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on Messages.java originally written by
// Copyright 2013 The Flutter Authors.

import media from '@ohos.multimedia.media';

class FlutterError extends Error {
  /** The error code. */
  public code: string;

  /** The error details. Must be a datatype supported by the api codec. */
  public details: ESObject;

  constructor(code: string, message: string, details: ESObject) {
    super(message);
    this.code = code;
    this.details = details;
  }
}

export function wrapError(exception: Error): Array<Object> {
  let errorList = new Array<Object>();
  if (exception instanceof FlutterError) {
    let error = exception as FlutterError;
    errorList.push(error.code);
    errorList.push(error.message);
    errorList.push(error.details);
  } else {
    errorList.push(exception.toString());
    errorList.push(exception.name);
    errorList.push(
      "Cause: " + exception.message + ", Stacktrace: " + exception.stack);
  }
  return errorList;
}

export class CreateMessage {
  constructor() {
  }
  private asset: string = "";

  public getAsset(): string {
    return this.asset;
  }

  public setAsset(setterArg: string): void {
  this.asset = setterArg;
  }

  private uri: string = "";

  public getUri(): string  {
    return this.uri;
  }

  public setUri(setterArg: string): void {
    this.uri = setterArg;
  }

  private packageName: String = "";

  public getPackageName(): String{
    return this.packageName;
  }

  public setPackageName(setterArg: String): void {
    this.packageName = setterArg;
  }

  private formatHint: String = "";

  public getFormatHint(): String {
    return this.formatHint;
  }

  public setFormatHint(setterArg: String): void {
    this.formatHint = setterArg;
  }

  private  httpHeaders: Map<String, String> = new Map<String, String>();

  public getHttpHeaders(): Map<String, String> {
    return this.httpHeaders;
  }

  public setHttpHeaders(setterArg: Map<String, String>): void {
    if (setterArg == null) {
      // throw new IllegalStateException("Nonnull field \"httpHeaders\" is null.");
    }
    this.httpHeaders = setterArg;
  }


  toList(): Array<Object>  {
    let toListResult: Array<Object> = new Array<Object>(5);
    toListResult[0] = this.asset;
    toListResult[1] = this.uri;
    toListResult[2] = this.packageName;
    toListResult[3] = this.formatHint;
    toListResult[4] = this.httpHeaders;
    return toListResult;
  }


  static fromList(list: Array<Object>): CreateMessage {
    let pigeonResult: CreateMessage = new CreateMessage();
    pigeonResult.setAsset(list[0] as string);
    pigeonResult.setUri(list[1] as string);
    pigeonResult.setPackageName(list[2] as String);
    pigeonResult.setFormatHint(list[3] as String);
    pigeonResult.setHttpHeaders(list[4] as Map<String, String>);
    return pigeonResult;
  }
}

export class LoopingMessage {
  constructor() {
  }
  private textureId: Number = 0;

  public getTextureId(): Number {
    return this.textureId;
  }

  public setTextureId(setterArg: Number): void{
    if (setterArg == null) {
      // throw new IllegalStateException("Nonnull field \"textureId\" is null.");
    } else {
      this.textureId = setterArg;
    }
  }

  private isLooping: boolean = false;

  public getIsLooping(): boolean {
    return this.isLooping;
  }

  public setIsLooping(setterArg: boolean): void {
    if (setterArg == null) {
      // throw new IllegalStateException("Nonnull field \"isLooping\" is null.");
    }
    this.isLooping = setterArg;
  }

  toList(): Array<Object> {
    let toListResult: Array<Object> = new Array<Object>(2);
    toListResult[0] = this.textureId;
    toListResult[1] = this.isLooping;
    return toListResult;
  }

  static fromList(list: Array<Object> ): LoopingMessage {
    let pigeonResult: LoopingMessage = new LoopingMessage();
    let textureId = list[0] as Number ?? 0;
    pigeonResult.setTextureId(textureId);

    let isLooping = list[1] as boolean;
    pigeonResult.setIsLooping(isLooping);
    return pigeonResult;
  }

}

export class MixWithOthersMessage {
  constructor() {
  }

  private mixWithOthers: Boolean = false;

  public getMixWithOthers(): Boolean {
    return this.mixWithOthers;
  }

  public setMixWithOthers(setterArg: Boolean): void {
    if (setterArg == null) {
      // throw new IllegalStateException("Nonnull field \"mixWithOthers\" is null.");
    }
    this.mixWithOthers = setterArg;
  }

  toList(): Array<Object> {
    let toListResult: Array<Object> = new Array<Object>(1);
    toListResult[0] = this.mixWithOthers;
    return toListResult;
  }

  static fromList(list: Array<Object>): MixWithOthersMessage {
    let pigeonResult: MixWithOthersMessage = new MixWithOthersMessage();
    let mixWithOthers = list[0] as Boolean;
    pigeonResult.setMixWithOthers(mixWithOthers);
    return pigeonResult;
  }
}

export class PlaybackSpeedMessage {
  constructor() {
  }
  private textureId: Number = 0;

  public getTextureId(): Number {
    return this.textureId;
  }

  public setTextureId(setterArg: Number): void{
    if (setterArg == null) {
      // throw new IllegalStateException("Nonnull field \"textureId\" is null.");
    } else {
      this.textureId = setterArg;
    }
  }

  private speed: Number= 1.0;

  public getSpeed(): media.PlaybackSpeed | null {
    if (this.speed == 0.75) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    } else if (this.speed == 1.0) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    } else if (this.speed == 1.25) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    } else if (this.speed == 1.75) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
    } else if (this.speed == 2.0) {
      return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
    } else if (this.speed == 0.5) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_50_X;
    } else if (this.speed == 1.5) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
    } else if (this.speed == 3.0) {
      return media.PlaybackSpeed.SPEED_FORWARD_3_00_X;
    } else if (this.speed == 0.25) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_25_X;
    } else if (this.speed == 0.125) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_125_X;
    } else {
      return null;
    }
  }

  public setSpeed(setterArg: Number): void {
    this.speed = setterArg;
  }

  toList(): Array<Object>  {
      let toListResult: Array<Object>  = new Array<Object>();
      toListResult[0] = this.textureId;
      toListResult[1] = this.speed;
      return toListResult;
    }

  static fromList(list: Array<Object>): PlaybackSpeedMessage {
    let pigeonResult: PlaybackSpeedMessage = new PlaybackSpeedMessage();
    let textureId = list[0] as Number ?? 0;
    pigeonResult.setTextureId(textureId);
    let speed = list[1] as media.PlaybackSpeed;
    pigeonResult.setSpeed(speed);
    return pigeonResult;
  }
}

export class PositionMessage {
  constructor() {
  }
  private textureId: Number = 0;

  public getTextureId(): Number {
    return this.textureId;
  }

  public setTextureId(setterArg: Number): void{
    this.textureId = setterArg;
  }

  private position: Number = 0;

  public getPosition(): Number {
    return this.position;
  }

  public setPosition(setterArg: Number): void {
    this.position = setterArg;
  }

  toList(): Array<Object> {
    let toListResult: Array<Object> = new Array<Object>();
    toListResult[0] = this.textureId;
    toListResult[1] = this.position;
    return toListResult;
  }

  static fromList(list: Array<Object>): PositionMessage {
    let pigeonResult: PositionMessage = new PositionMessage();
    let textureId = list[0] as Number ?? 0;
    pigeonResult.setTextureId(textureId);
    let position = list[1] as Number ?? 0;
    pigeonResult.setPosition(position);
    return pigeonResult;
  }
}

export class TextureMessage {

  private textureId: Number = 0;

  public getTextureId(): Number {
    return this.textureId;
  }

  public setTextureId(setterArg: Number): void {
    this.textureId = setterArg;
  }

 toList(): Array<Object> {
      let toListResult: Array<Object> = new Array<Object>(1);
      toListResult[0] = this.textureId;
      return toListResult;
    }
  static fromList(list: Array<Object>): TextureMessage {
    let pigeonResult: TextureMessage = new TextureMessage();
    let textureId = list[0] as Number ?? 0;
    pigeonResult.setTextureId(textureId);
    return pigeonResult;
  }
}

export class VolumeMessage {
  constructor() {
  }
  private textureId: Number = 0;

  public getTextureId(): Number {
    return this.textureId;
  }

  public setTextureId(setterArg: Number): void {
    this.textureId = setterArg;
  }

  private volume: Number = 0;
  public getVolume(): Number {
    return this.volume;
  }

  public setVolume(setterArg: Number): void {
    this.volume = setterArg;
  }

 toList(): Array<Object> {
   let toListResult: Array<Object> = new Array<Object>(2);
   toListResult[0] = this.textureId;
   toListResult[1] = this.volume;
   return toListResult;
 }

  static fromList(list: Array<Object> ): VolumeMessage {
    let pigeonResult: VolumeMessage = new VolumeMessage();
    let textureId = list[0] as Number ?? 0;
    pigeonResult.setTextureId(textureId);
    let volume = list[1] as Number ?? 0;
    pigeonResult.setVolume(volume);
    return pigeonResult;
  }
}