// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on QueuingEventSink.java originally written by
// Copyright 2013 The Flutter Authors.

import { EventSink } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { ArrayList } from '@kit.ArkTS';

export class QueuingEventSink implements EventSink {
  private delegate: EventSink | null = null;
  private eventQueue: ArrayList<Object> = new ArrayList<Object>();
  private done: boolean = false;

  setDelegate(delegate: EventSink | null): void {
    this.delegate = delegate;
    this.maybeFlush();
  }
  success(event: Object): void {
    this.enqueue(event);
    this.maybeFlush();
  }

  error(code: string, message: string, details: Object): void {
    this.enqueue(new ErrorEvent(code, message, details));
    this.maybeFlush();
  }

  endOfStream(): void {
    this.enqueue(new EndOfStreamEvent());
    this.maybeFlush();
    this.done = true;
  }

  private enqueue(event: Object): void {
    if (this.done) {
      return;
    }
    this.eventQueue.add(event);
  }

  maybeFlush(): void {
    if (this.delegate == null) {
      return;
    }
    for (let event of this.eventQueue) {
      if (event instanceof EndOfStreamEvent) {
        this.delegate.endOfStream();
      } else if (event instanceof ErrorEvent) {
        let errorEvent: ErrorEvent = event as ErrorEvent;
        this.delegate.error(errorEvent.code, errorEvent.message, errorEvent.details);
      } else {
        this.delegate.success(event);
      }
    }
    this.eventQueue.clear();
  }
}

class EndOfStreamEvent {}

class ErrorEvent {
  private _code: string = '';

  public get code(): string {
    return this._code;
  }

  private _message: string = '';

  public get message(): string {
    return this._message;
  }

  private _details: Object = new Object();

  public get details(): Object {
    return this._details;
  }

  constructor(code: string, message: string, details: Object) {
    this._code = code;
    this._message = message;
    this._details = details;
  }
}
