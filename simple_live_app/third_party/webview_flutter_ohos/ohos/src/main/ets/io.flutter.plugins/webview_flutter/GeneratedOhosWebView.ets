// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on GeneratedAndroidWebView.java originally written by
// Copyright 2013 The Flutter Authors.

import ArrayList from '@ohos.util.ArrayList';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import { ByteBuffer } from '@ohos/flutter_ohos/src/main/ets/util/ByteBuffer';
import MessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/MessageCodec';
import { BinaryMessenger } from "@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger"
import BasicMessageChannel, { MessageHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BasicMessageChannel';
import { CookieManagerHostApiImpl } from './CookieManagerHostApiImpl';

export default class GeneratedOhosWebView {
  static wrapError(exception: Error): ArrayList<ESObject> {
    const errorList: ArrayList<ESObject> = new ArrayList<ESObject>();
    if (exception instanceof FlutterError) {
      const error = exception;
      errorList.add(error.code);
      errorList.add(error.message);
      errorList.add(error.details);
    } else {
      errorList.add(exception.name);
      errorList.add(exception.message);
      errorList.add(exception.stack);
    }
    return errorList;
  }
}

export class FlutterError extends Error {
  code: string;

  details: ESObject;

  constructor(code: string, message: string, details: ESObject) {
    super(message);
    this.code = code;
    this.details = details;
  }
}

export interface Result<T> {
  success: (result: T) => void;
  error: (error: Error) => void;
}

class ResultBuilder <T> {
  success: (result: T) => void;
  error: (error: Error) => void;

  constructor(success: (result: T) => void, error: (error: Error) => void) {
    this.success = success
    this.error = error
  }
}

export enum FileChooserMode {
  OPEN,
  OPEN_MULTIPLE,
  SAVE
}

interface FileChooserModeEnumDataBuilder {
  value: FileChooserMode;
  setValue: (setterArg: FileChooserMode) => FileChooserModeEnumDataBuilder;
  build: () => FileChooserModeEnumData;
}

export class FileChooserModeEnumData {
  private value: FileChooserMode = 0;

  private constructor() {
  }

  getValue(): FileChooserMode {
    return this.value;
  }

  setValue(setterArg: FileChooserMode) {
    if (setterArg == null) {
      throw new Error("Nonnull field \"value\" is null.")
    }
    this.value = setterArg;
  }

  public static Builder(): FileChooserModeEnumDataBuilder {
    const builder: FileChooserModeEnumDataBuilder = {
      value: FileChooserMode.OPEN,
      setValue(setterArg: FileChooserMode): FileChooserModeEnumDataBuilder {
        builder.value = setterArg;
        return builder;
      },
      build(): FileChooserModeEnumData {
        const pigeonReturn = new FileChooserModeEnumData();
        pigeonReturn.setValue(builder.value);
        return pigeonReturn;
      }
    }

    return builder;
  }

  toArray(): Array<ESObject> {
    const toArrayResult: Array<ESObject> = new Array<ESObject>();
    toArrayResult.push(this.value);
    return toArrayResult;
  }

  static fromArray(list: Array<ESObject>): FileChooserModeEnumData {
    const pigeonResult = new FileChooserModeEnumData();
    const value: number = list[0];
    pigeonResult.setValue(value);
    return pigeonResult;
  }
}

interface WebViewPointBuilder {
  x: number;
  y: number;
  setX: (setterArg: number) => WebViewPointBuilder;
  setY: (setterArg: number) => WebViewPointBuilder;
  build: () => WebViewPoint;
}

export class WebViewPoint {
  private x: number = 0;

  private y: number = 0;

  getX(): number {
    return this.x;
  }

  setX(setterArg: number): void {
    if (setterArg == null) {
      throw new Error("Nonnull field \"x\" is null.")
    }
    this.x = setterArg;
  }

  getY(): number {
    return this.y;
  }

  setY(setterArg: number): void {
    if (setterArg == null) {
      throw new Error("Nonnull field \"y\" is null.")
    }
    this.y = setterArg;
  }

  private constructor() {
  }

  public static Builder(): WebViewPointBuilder {
    const builder: WebViewPointBuilder = {
      x: 0,
      y: 0,
      setX(setterArg: number): WebViewPointBuilder {
        builder.x = setterArg;
        return builder;
      },

      setY(setterArg: number): WebViewPointBuilder {
        builder.y = setterArg;
        return builder;
      },
      build(): WebViewPoint {
        const pigeonReturn = new WebViewPoint();
        pigeonReturn.setX(builder.x);
        pigeonReturn.setY(builder.y);
        return pigeonReturn;
      }
    };
    return builder;
  }

  toArray(): Array<ESObject> {
    const toArrayResult: Array<ESObject> = new Array<ESObject>();
    toArrayResult.push(this.x);
    toArrayResult.push(this.y);
    return toArrayResult;
  }

  static fromArray(list: Array<ESObject>): WebViewPoint {
    const pigeonResult = new WebViewPoint();
    const x: number = list[0];
    pigeonResult.setX(x);
    const y: number = list[1];
    pigeonResult.setY(y);
    return pigeonResult;
  }
}

class WebViewHostApiCodec extends StandardMessageCodec {
  public static INSTANCE: WebViewHostApiCodec = new WebViewHostApiCodec();

  private constructor() {
    super();
  }

  readValueOfType(type: number, buffer: ByteBuffer): ESObject {
    switch (type) {
      case 128:
        return WebViewPoint.fromArray(this.readValue(buffer));
      default:
        return super.readValueOfType(type, buffer);
    }
  }

  writeValue(stream: ByteBuffer, value: ESObject): ESObject {
    if (value instanceof WebViewPoint) {
      stream.writeInt8(128);
      super.writeValue(stream, value.toArray());
    } else {
      super.writeValue(stream, value);
    }
  }
}

export abstract class WebViewHostApi {
  abstract create(instanceId: number): void;

  abstract loadData(
    instanceId: number,
    data: string,
    mimeType: string,
    encoding: string
  ): void;

  abstract loadDataWithBaseUrl(
    instanceId: number,
    baseUrl: string,
    data: string,
    mimeType: string,
    encoding: string,
    historyUrl: string
  ): void;

  abstract loadUrl(
    instanceId: number,
    url: string,
    headers: Map<string, string>
  ): void;

  abstract postUrl(
    instanceId: number,
    url: string,
    data: Uint8Array
  ): void;

  abstract getUrl(instanceId: number): Promise<string>;

  abstract canGoBack(instanceId: number): boolean;

  abstract canGoForward(instanceId: number): boolean;

  abstract goBack(instanceId: number): void;

  abstract goForward(instanceId: number): void;

  abstract reload(instanceId: number): void;

  abstract clearCache(instanceId: number, includeDiskFiles: boolean): void;

  abstract evaluateJavascript(
    instanceId: number, javascriptString: string, result: Result<string>
  ): void;

  abstract getTitle(instanceId: number): string;

  abstract scrollTo(instanceId: number, x: number, y: number): void;

  abstract scrollBy(instanceId: number, x: number, y: number): void;

  abstract getScrollX(instanceId: number): number;

  abstract getScrollY(instanceId: number): number;

  abstract getScrollPosition(instanceId: number): WebViewPoint;

  abstract setWebContentsDebuggingEnabled(enabled: boolean): void;

  abstract setWebViewClient(instanceId: number, webViewClientInstanceId: number): void;

  abstract addJavaScriptChannel(instanceId: number, javaScriptChannelInstanceId: number): void;

  abstract removeJavaScriptChannel(instanceId: number, javaScriptChannelInstanceId: number): void;

  abstract setDownloadListener(instanceId: number, listenerInstanceId: number);

  abstract setWebChromeClient(instanceId: number, clientInstanceId: number);

  static getCodec(): MessageCodec<ESObject> {
    return WebViewHostApiCodec.INSTANCE;
  }

  static setup(binaryMessenger: BinaryMessenger, api: WebViewHostApi) {
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.create", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                api.create(instanceIdArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.loadData", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const dataArg: string = args[1];
              const mimeTypeArg: string = args[2];
              const encodingArg: string = args[3];
              try {
                api.loadData(instanceIdArg, dataArg, mimeTypeArg, encodingArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.loadDataWithBaseUrl",
        WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const baseUrlArg: string = args[1];
              const dataArg: string = args[2];
              const mimeTypeArg: string = args[3];
              const encodingArg: string = args[4];
              const historyUrlArg: string = args[5];
              try {
                api.loadDataWithBaseUrl(
                  instanceIdArg,
                  baseUrlArg,
                  dataArg,
                  mimeTypeArg,
                  encodingArg,
                  historyUrlArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.loadUrl", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const urlArg: string = args[1];
              const headersArg: Map<string, string> = args[2];
              try {
                api.loadUrl(
                  instanceIdArg,
                  urlArg,
                  headersArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.postUrl", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const urlArg: string = args[1];
              const dataArg: Uint8Array = args[2];
              try {
                api.postUrl(instanceIdArg, urlArg, dataArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.getUrl", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: async (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                await api.getUrl(instanceIdArg).then(output => {
                  wrapped.insert(output, 0);
                });
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.canGoBack", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                const output: boolean = api.canGoBack(instanceIdArg);
                wrapped.insert(output, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.canGoForward",
        WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                const output: boolean = api.canGoForward(instanceIdArg);
                wrapped.insert(output, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.goBack", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                api.goBack(instanceIdArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.goForward", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                api.goForward(instanceIdArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.reload", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                api.reload(instanceIdArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.clearCache", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const includeDiskFilesArg: boolean = args[1];
              try {
                api.clearCache(instanceIdArg, includeDiskFilesArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.evaluateJavascript",
        WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const javascriptStringArg: string = args[1];
              const resultCallback: Result<string> =
                {
                  success: (result: string): void => {
                    wrapped.insert(result, 0);
                    reply.reply(wrapped.convertToArray());
                  },

                  error: (error: Error): void => {
                    const wrappedError: ArrayList<ESObject>
                      = GeneratedOhosWebView.wrapError(error);
                    reply.reply(wrappedError.convertToArray());
                  }
                };
              api.evaluateJavascript(instanceIdArg, javascriptStringArg, resultCallback);
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.getTitle", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                const output: string = api.getTitle(instanceIdArg);
                wrapped.insert(output, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.scrollTo", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const xArg: number = args[1];
              const yArg: number = args[2];
              try {
                api.scrollTo(
                  instanceIdArg,
                  xArg,
                  yArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.scrollBy", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const xArg: number = args[1];
              const yArg: number = args[2];
              try {
                api.scrollBy(
                  instanceIdArg,
                  xArg,
                  yArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.getScrollX", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                const output: number = api.getScrollX(instanceIdArg);
                wrapped.insert(output, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.getScrollY", WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                const output: number = api.getScrollY(instanceIdArg);
                wrapped.insert(output, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.getScrollPosition",
        WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                const output: WebViewPoint = api.getScrollPosition(instanceIdArg);
                wrapped.insert(output, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.setWebContentsDebuggingEnabled",
        WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const enabledArg: boolean = args[0];
              try {
                api.setWebContentsDebuggingEnabled(enabledArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.setWebViewClient",
        WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const webViewClientInstanceIdArg: number = args[1];
              try {
                api.setWebViewClient(
                  instanceIdArg,
                  webViewClientInstanceIdArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.addJavaScriptChannel",
        WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const javaScriptChannelInstanceIdArg: number = args[1];
              try {
                api.addJavaScriptChannel(
                  instanceIdArg,
                  javaScriptChannelInstanceIdArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.removeJavaScriptChannel",
        WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const javaScriptChannelInstanceIdArg: number = args[1];
              try {
                api.removeJavaScriptChannel(
                  instanceIdArg,
                  javaScriptChannelInstanceIdArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.setDownloadListener",
        WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const listenerInstanceIdArg: number = args[1];
              try {
                api.setDownloadListener(
                  instanceIdArg,
                  listenerInstanceIdArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebViewHostApi.setWebChromeClient",
        WebViewHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const clientInstanceIdArg: number = args[1];
              try {
                api.setWebChromeClient(
                  instanceIdArg,
                  clientInstanceIdArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
  }
}

export interface Reply<T> {
  /**
   * Handles the specified message reply.
   *
   * @param reply the reply, possibly null.
   */
  reply: (reply: T | null) => void;
}

export class WebViewFlutterApi {
  private binaryMessenger: BinaryMessenger;

  constructor(argBinaryMessenger: BinaryMessenger) {
    this.binaryMessenger = argBinaryMessenger;
  }

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  create(identifierArg: number, callback: Reply<void>): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebViewFlutterApi.create",
      WebViewFlutterApi.getCodec()
    );
    channel.send(
      [identifierArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

  onScrollChanged(
    webViewInstanceIdArg: number,
    leftArg: number,
    topArg: number,
    oldLeftArg: number,
    oldTopArg: number,
    callback: Reply<void>,
  ) {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        this.binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebViewFlutterApi.onScrollChanged",
        WebViewFlutterApi.getCodec());
    channel.send(
      [webViewInstanceIdArg, leftArg, topArg, oldLeftArg, oldTopArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }
}

export enum ConsoleMessageLevel {
  DEBUG,
  ERROR,
  LOG,
  TIP,
  WARNING,
  UNKNOWN
}

interface ConsoleMessageBuilder {
  lineNumber: number;
  message: string;
  level: ConsoleMessageLevel;
  sourceId: string;
  setLineNumber: (setterArg: number) => ConsoleMessageBuilder;
  setMessage: (setterArg: string) => ConsoleMessageBuilder;
  setLevel: (setterArg: ConsoleMessageLevel) => ConsoleMessageBuilder;
  setSourceId: (setterArg: string) => ConsoleMessageBuilder;
  build: () => ConsoleMessage;
}

export class ConsoleMessage {
  private lineNumber: number = 0;

  getLineNumber(): number {
    return this.lineNumber;
  }

  setLineNumber(setterArg: number): void {
    if (setterArg == null) {
      throw new Error("Nonnull field \"lineNumber\" is null.")
    }
    this.lineNumber = setterArg;
  }

  private message: string = "";

  getMessage(): string {
    return this.message;
  }

  setMessage(setterArg: string): void {
    if (setterArg == null) {
      throw new Error("Nonnull field \"message\" is null.")
    }
    this.message = setterArg;
  }

  private level: ConsoleMessageLevel = 0;

  getLevel(): ConsoleMessageLevel {
    return this.level;
  }

  setLevel(setterArg: ConsoleMessageLevel): void {
    if (setterArg == null) {
      throw new Error("Nonnull field \"level\" is null.")
    }
    this.level = setterArg;
  }

  private sourceId: string = "";

  getSourceId(): string {
    return this.sourceId;
  }

  setSourceId(setterArg: string): void {
    if (setterArg == null) {
      throw new Error("Nonnull field \"sourceId\" is null.")
    }
    this.sourceId = setterArg;
  }

  private constructor() {
  }

  public static Builder(): ConsoleMessageBuilder {
    const builder: ConsoleMessageBuilder = {
      lineNumber: 0,
      message: "",
      level: ConsoleMessageLevel.DEBUG,
      sourceId: "",
      setLineNumber(setterArg: number): ConsoleMessageBuilder {
        builder.lineNumber = setterArg;
        return builder;
      },
      setMessage(setterArg: string): ConsoleMessageBuilder {
        builder.message = setterArg;
        return builder;
      },
      setLevel(setterArg: ConsoleMessageLevel): ConsoleMessageBuilder {
        builder.level = setterArg;
        return builder;
      },
      setSourceId(setterArg: string): ConsoleMessageBuilder {
        builder.sourceId = setterArg;
        return builder;
      },
      build(): ConsoleMessage {
        const pigeonReturn = new ConsoleMessage();
        pigeonReturn.setLineNumber(builder.lineNumber);
        pigeonReturn.setMessage(builder.message);
        pigeonReturn.setLevel(builder.level);
        pigeonReturn.setSourceId(builder.sourceId);
        return pigeonReturn;
      }
    };
    return builder;
  }

  toArray(): Array<ESObject> {
    const toArrayResult: Array<ESObject> = new Array<ESObject>();
    toArrayResult.push(this.lineNumber);
    toArrayResult.push(this.message);
    toArrayResult.push(this.level);
    toArrayResult.push(this.sourceId);
    return toArrayResult;
  }

  static fromArray(array: Array<ESObject>): ConsoleMessage {
    const pigeonResult = new ConsoleMessage();
    const lineNumber: number = array[0];
    pigeonResult.setLineNumber(lineNumber);
    const message: string = array[1];
    pigeonResult.setMessage(message);
    const level: ConsoleMessageLevel = array[2];
    pigeonResult.setLevel(level);
    const sourceId: string = array[3];
    pigeonResult.setSourceId(sourceId);
    return pigeonResult;
  }
}

class WebChromeClientFlutterApiCodec extends StandardMessageCodec {
  public static INSTANCE: WebChromeClientFlutterApiCodec = new WebChromeClientFlutterApiCodec();

  private constructor() {
    super();
  }

  readValueOfType(type: number, buffer: ByteBuffer): ESObject {
    switch (type) {
      case 128:
        return ConsoleMessage.fromArray(this.readValue(buffer));
      default:
        return super.readValueOfType(type, buffer);
    }
  }

  writeValue(stream: ByteBuffer, value: ESObject): ESObject {
    if (value instanceof ConsoleMessage) {
      stream.writeInt8(128);
      super.writeValue(stream, value.toArray());
    } else {
      super.writeValue(stream, value);
    }
  }
}

export abstract class WebChromeClientFlutterApi {
  protected binaryMessenger: BinaryMessenger;

  constructor(binaryMessenger: BinaryMessenger) {
    this.binaryMessenger = binaryMessenger;
  }

  static getCodec(): MessageCodec<ESObject> {
    return WebChromeClientFlutterApiCodec.INSTANCE;
  }

  onProgressChanged(
    instanceIdArg: number,
    webViewInstanceIdArg: number,
    progressArg: number,
    callback: Reply<void>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientFlutterApi.onProgressChanged",
      WebChromeClientFlutterApi.getCodec()
    )
    channel.send(
      [instanceIdArg, webViewInstanceIdArg, progressArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

  onShowFileChooser(
    instanceIdArg: number,
    webViewInstanceIdArg: number,
    paramsInstanceIdArg: number,
    callback: Reply<Array<string>>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientFlutterApi.onShowFileChooser",
      WebChromeClientFlutterApi.getCodec()
    )
    channel.send(
      [instanceIdArg, webViewInstanceIdArg, paramsInstanceIdArg],
      (channelReply: ESObject) => {
        const output: Array<string> = channelReply;
        callback.reply(output);
      }
    );
  }

  onPermissionRequest(
    instanceIdArg: number,
    requestInstanceIdArg: number,
    callback: Reply<void>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientFlutterApi.onPermissionRequest",
      WebChromeClientFlutterApi.getCodec()
    )
    channel.send(
      [instanceIdArg, requestInstanceIdArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

  onShowCustomView(
    instanceIdArg: number,
    viewIdentifierArg: number,
    callbackIdentifierArg: number,
    callback: Reply<void>
  ) {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientFlutterApi.onShowCustomView",
      WebChromeClientFlutterApi.getCodec()
    )
    channel.send(
      [instanceIdArg, viewIdentifierArg, callbackIdentifierArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

  onHideCustomView(
    instanceIdArg: number,
    callback: Reply<void>
  ) {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientFlutterApi.onHideCustomView",
      WebChromeClientFlutterApi.getCodec()
    )
    channel.send(
      [instanceIdArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

  onGeolocationPermissionsShowPrompt(
    instanceIdArg: number,
    paramsInstanceIdArg: number,
    originArg: string,
    callback: Reply<void>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientFlutterApi.onGeolocationPermissionsShowPrompt",
      WebChromeClientFlutterApi.getCodec()
    )
    channel.send(
      [instanceIdArg, paramsInstanceIdArg, originArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

  onGeolocationPermissionsHidePrompt(
    instanceIdArg: number, callback: Reply<void>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientFlutterApi.onGeolocationPermissionsHidePrompt",
      WebChromeClientFlutterApi.getCodec()
    )
    channel.send(
      [instanceIdArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

  onConsoleMessage(
    instanceIdArg: number,
    messageArg: ConsoleMessage,
    callback: Reply<void>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientFlutterApi.onConsoleMessage",
      WebChromeClientFlutterApi.getCodec()
    )
    channel.send(
      [instanceIdArg, messageArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

  onJsAlert(
    instanceIdArg: number,
    urlArg: string,
    messageArg: string,
    callback: Reply<void>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientFlutterApi.onJsAlert",
      WebChromeClientFlutterApi.getCodec()
    )
    channel.send(
      [instanceIdArg, urlArg, messageArg],
      (channelReply: ESObject) => {
        callback.reply(null);
      }
    );
  }

  onJsConfirm(
    instanceIdArg: number,
    urlArg: string,
    messageArg: string,
    callback: Reply<boolean>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientFlutterApi.onJsConfirm",
      WebChromeClientFlutterApi.getCodec()
    )
    channel.send(
      [instanceIdArg, urlArg, messageArg],
      (channelReply: ESObject) => {
        let output: boolean = channelReply as boolean;
        callback.reply(output);
      }
    );
  }

  onJsPrompt(
    instanceIdArg: number,
    urlArg: string,
    messageArg: string,
    defaultValueArg: string,
    callback: Reply<string>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientFlutterApi.onJsPrompt",
      WebChromeClientFlutterApi.getCodec()
    )
    channel.send(
      [instanceIdArg, urlArg, messageArg, defaultValueArg],
      (channelReply: ESObject) => {
        let output: string = channelReply as string;
        callback.reply(output);
      }
    );
  }
}

export abstract class WebChromeClientHostApi {
  abstract create(instanceId: number): void;

  abstract setSynchronousReturnValueForOnShowFileChooser(instanceId: number, value: boolean): void;

  abstract setSynchronousReturnValueForOnConsoleMessage(instanceId: number, value: boolean): void;

  abstract setSynchronousReturnValueForOnJsAlert(instanceId: number, value: boolean): void;

  abstract setSynchronousReturnValueForOnJsConfirm(instanceId: number, value: boolean): void;

  abstract setSynchronousReturnValueForOnJsPrompt(instanceId: number, value: boolean): void;

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  static setup(binaryMessenger: BinaryMessenger, api: WebChromeClientHostApi) {
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientHostApi.create",
        WebChromeClientHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                api.create(instanceIdArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientHostApi.setSynchronousReturnValueForOnShowFileChooser",
        WebChromeClientHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const valueArg: boolean = args[1];
              try {
                api.setSynchronousReturnValueForOnShowFileChooser(
                  instanceIdArg, valueArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientHostApi.setSynchronousReturnValueForOnConsoleMessage",
        WebChromeClientHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const valueArg: boolean = args[1];
              try {
                api.setSynchronousReturnValueForOnConsoleMessage(
                  instanceIdArg, valueArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
        new BasicMessageChannel<ESObject>(
          binaryMessenger,
          "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientHostApi.setSynchronousReturnValueForOnJsAlert",
          WebChromeClientHostApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          onMessage: (message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const instanceIdArg: number = args[0];
            const valueArg: boolean = args[1];
            try {
              api.setSynchronousReturnValueForOnJsAlert(
                instanceIdArg, valueArg
              );
              wrapped.insert(null, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          }
        });
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
        new BasicMessageChannel<ESObject>(
          binaryMessenger,
          "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientHostApi.setSynchronousReturnValueForOnJsConfirm",
          WebChromeClientHostApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          onMessage: (message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const instanceIdArg: number = args[0];
            const valueArg: boolean = args[1];
            try {
              api.setSynchronousReturnValueForOnJsConfirm(
                instanceIdArg, valueArg
              );
              wrapped.insert(null, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          }
        });
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
        new BasicMessageChannel<ESObject>(
          binaryMessenger,
          "dev.flutter.pigeon.webview_flutter_ohos.WebChromeClientHostApi.setSynchronousReturnValueForOnJsPrompt",
          WebChromeClientHostApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          onMessage: (message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const instanceIdArg: number = args[0];
            const valueArg: boolean = args[1];
            try {
              api.setSynchronousReturnValueForOnJsPrompt(
                instanceIdArg, valueArg
              );
              wrapped.insert(null, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          }
        });
      } else {
        channel.setMessageHandler(null);
      }
    }
  }
}

export abstract class WebViewClientHostApi {
  abstract create(instanceId: number): void;

  abstract setSynchronousReturnValueForShouldOverrideUrlLoading(instanceId: number, value: boolean): void;

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  static setup(binaryMessenger: BinaryMessenger, api: WebViewClientHostApi) {
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebViewClientHostApi.create",
        WebViewClientHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                api.create(instanceIdArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebViewClientHostApi.setSynchronousReturnValueForShouldOverrideUrlLoading",
        WebViewClientHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const valueArg: boolean = args[1];
              try {
                api.setSynchronousReturnValueForShouldOverrideUrlLoading(
                  instanceIdArg, valueArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
  }
}

interface WebResourceErrorDataBuilder {
  errorCode: number;
  setErrorCode: (setterArg: number) => WebResourceErrorDataBuilder;
  description: string;
  setDescription: (setterArg: string) => WebResourceErrorDataBuilder;
  build: () => WebResourceErrorData;
}

export class WebResourceErrorData {
  private errorCode: number = 0;

  private constructor() {
  }

  getErrorCode(): number {
    return this.errorCode;
  }

  setErrorCode(setterArg: number) {
    if (setterArg == null) {
      throw new Error("Nonnull field \"errorCode\" is null.")
    }
    this.errorCode = setterArg;
  }

  private description: string = "";

  getDescription(): string {
    return this.description;
  }

  setDescription(setterArg: string) {
    if (setterArg == null) {
      throw new Error("Nonnull field \"description\" is null.")
    }
    this.description = setterArg;
  }

  public static Builder(): WebResourceErrorDataBuilder {
    const builder: WebResourceErrorDataBuilder = {
      errorCode: 0,
      setErrorCode(setterArg: number): WebResourceErrorDataBuilder {
        builder.errorCode = setterArg;
        return builder;
      },
      description: "",
      setDescription(setterArg: string): WebResourceErrorDataBuilder {
        builder.description = setterArg;
        return builder;
      },
      build(): WebResourceErrorData {
        const pigeonReturn = new WebResourceErrorData();
        pigeonReturn.setErrorCode(builder.errorCode);
        pigeonReturn.setDescription(builder.description);
        return pigeonReturn;
      }
    }

    return builder;
  }

  toArray(): Array<ESObject> {
    const toArrayResult: Array<ESObject> = new Array<ESObject>();
    toArrayResult.push(this.errorCode);
    toArrayResult.push(this.description);
    return toArrayResult;
  }

  static fromArray(list: Array<ESObject>): WebResourceErrorData {
    const pigeonResult = new WebResourceErrorData();
    const errorCode: number = list[0];
    pigeonResult.setErrorCode(errorCode);
    const description: string = list[1];
    pigeonResult.setDescription(description);
    return pigeonResult;
  }
}

interface WebResourceRequestDataBuilder {
  url: string;
  setUrl: (setterArg: string) => WebResourceRequestDataBuilder;
  isForMainFrame: boolean;
  setIsForMainFrame: (setterArg: boolean) => WebResourceRequestDataBuilder;
  isRedirect: boolean;
  setIsRedirect: (setterArg: boolean) => WebResourceRequestDataBuilder;
  hasGesture: boolean;
  setHasGesture: (setterArg: boolean) => WebResourceRequestDataBuilder;
  method: string;
  setMethod: (setterArg: string) => WebResourceRequestDataBuilder;
  requestHeaders: Map<string, string>;
  setRequestHeaders: (setterArg: Map<string, string>) => WebResourceRequestDataBuilder;
  build: () => WebResourceRequestData;
}

export class WebResourceRequestData {
  private url: string = "";

  private constructor() {
  }

  getUrl(): string {
    return this.url;
  }

  setUrl(setterArg: string) {
    if (setterArg == null) {
      throw new Error("Nonnull field \"url\" is null.")
    }
    this.url = setterArg;
  }

  private isForMainFrame: boolean = false;

  getIsForMainFrame(): boolean {
    return this.isForMainFrame;
  }

  setIsForMainFrame(setterArg: boolean) {
    if (setterArg == null) {
      throw new Error("Nonnull field \"isForMainFrame\" is null.")
    }
    this.isForMainFrame = setterArg;
  }

  private isRedirect: boolean = false;

  getIsRedirect(): boolean {
    return this.isRedirect;
  }

  setIsRedirect(setterArg: boolean) {
    if (setterArg == null) {
      throw new Error("Nonnull field \"isRedirect\" is null.")
    }
    this.isRedirect = setterArg;
  }

  private hasGesture: boolean = false;

  getHasGesture(): boolean {
    return this.hasGesture;
  }

  setHasGesture(setterArg: boolean) {
    if (setterArg == null) {
      throw new Error("Nonnull field \"hasGesture\" is null.")
    }
    this.hasGesture = setterArg;
  }

  private method: string = "";

  getMethod(): string {
    return this.method;
  }

  setMethod(setterArg: string) {
    if (setterArg == null) {
      throw new Error("Nonnull field \"method\" is null.")
    }
    this.method = setterArg;
  }

  private requestHeaders: Map<string, string> = new Map<string, string>();

  getRequestHeaders(): Map<string, string> {
    return this.requestHeaders;
  }

  setRequestHeaders(setterArg: Map<string, string>) {
    if (setterArg == null) {
      throw new Error("Nonnull field \"requestHeaders\" is null.")
    }
    this.requestHeaders = setterArg;
  }

  public static Builder(): WebResourceRequestDataBuilder {
    const builder: WebResourceRequestDataBuilder = {
      url: "",
      setUrl(setterArg: string): WebResourceRequestDataBuilder {
        builder.url = setterArg;
        return builder;
      },
      isForMainFrame: false,
      setIsForMainFrame(setterArg: boolean): WebResourceRequestDataBuilder {
        builder.isForMainFrame = setterArg;
        return builder;
      },
      isRedirect: false,
      setIsRedirect(setterArg: boolean): WebResourceRequestDataBuilder {
        builder.isRedirect = setterArg;
        return builder;
      },
      hasGesture: false,
      setHasGesture(setterArg: boolean): WebResourceRequestDataBuilder {
        builder.hasGesture = setterArg;
        return builder;
      },
      method: "",
      setMethod(setterArg: string): WebResourceRequestDataBuilder {
        builder.method = setterArg;
        return builder;
      },
      requestHeaders: new Map<string, string>(),
      setRequestHeaders(setterArg: Map<string, string>): WebResourceRequestDataBuilder {
        builder.requestHeaders = setterArg;
        return builder;
      },
      build(): WebResourceRequestData {
        const pigeonReturn = new WebResourceRequestData();
        pigeonReturn.setUrl(builder.url);
        pigeonReturn.setIsForMainFrame(builder.isForMainFrame);
        pigeonReturn.setIsRedirect(builder.isRedirect);
        pigeonReturn.setHasGesture(builder.hasGesture);
        pigeonReturn.setMethod(builder.method);
        pigeonReturn.setRequestHeaders(builder.requestHeaders);
        return pigeonReturn;
      }
    }

    return builder;
  }

  toArray(): Array<ESObject> {
    const toArrayResult: Array<ESObject> = new Array<ESObject>();
    toArrayResult.push(this.url);
    toArrayResult.push(this.isForMainFrame);
    toArrayResult.push(this.isRedirect);
    toArrayResult.push(this.hasGesture);
    toArrayResult.push(this.method);
    toArrayResult.push(this.requestHeaders);
    return toArrayResult;
  }

  static fromArray(list: Array<ESObject>): WebResourceRequestData {
    const pigeonResult = new WebResourceRequestData();
    const url: string = list[0];
    pigeonResult.setUrl(url);
    const isForMainFrame: boolean = list[1];
    pigeonResult.setIsForMainFrame(isForMainFrame);
    const isRedirect: boolean = list[2];
    pigeonResult.setIsRedirect(isRedirect);
    const hasGesture: boolean = list[3];
    pigeonResult.setHasGesture(hasGesture);
    const method: string = list[4];
    pigeonResult.setMethod(method);
    const requestHeaders: Map<string, string> = list[5];
    pigeonResult.setRequestHeaders(requestHeaders);
    return pigeonResult;
  }
}

class WebViewClientFlutterApiCodec extends StandardMessageCodec {
  public static INSTANCE: WebViewClientFlutterApiCodec = new WebViewClientFlutterApiCodec();

  private constructor() {
    super();
  }

  readValueOfType(type: number, buffer: ByteBuffer): ESObject {
    switch (type) {
      case 128:
        return WebResourceErrorData.fromArray(this.readValue(buffer));
      case 129:
        return WebResourceRequestData.fromArray(this.readValue(buffer));
      default:
        return super.readValueOfType(type, buffer);
    }
  }

  writeValue(stream: ByteBuffer, value: ESObject): ESObject {
    if (value instanceof WebResourceErrorData) {
      stream.writeInt8(128);
      super.writeValue(stream, value.toArray());
    } else if (value instanceof WebResourceRequestData) {
      stream.writeInt8(129);
      super.writeValue(stream, value.toArray());
    } else {
      super.writeValue(stream, value);
    }
  }
}

export abstract class WebViewClientFlutterApi {
  protected binaryMessenger: BinaryMessenger;

  constructor(argBinaryMessenger: BinaryMessenger) {
    this.binaryMessenger = argBinaryMessenger;
  }

  static getCodec(): MessageCodec<ESObject> {
    return WebViewClientFlutterApiCodec.INSTANCE;
  }

  onPageStarted(
    instanceIdArg: number,
    webViewInstanceIdArg: number,
    urlArg: string,
    callback: Reply<void>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebViewClientFlutterApi.onPageStarted",
      WebViewClientFlutterApi.getCodec()
    );
    channel.send(
      [instanceIdArg, webViewInstanceIdArg, urlArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

  onPageFinished(
    instanceIdArg: number,
    webViewInstanceIdArg: number,
    urlArg: string,
    callback: Reply<void>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebViewClientFlutterApi.onPageFinished",
      WebViewClientFlutterApi.getCodec()
    );
    channel.send(
      [instanceIdArg, webViewInstanceIdArg, urlArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

  onReceivedRequestError(
    instanceIdArg: number,
    webViewInstanceIdArg: number,
    requestArg: WebResourceRequestData,
    errorArg: WebResourceErrorData,
    callback: Reply<void>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebViewClientFlutterApi.onReceivedRequestError",
      WebViewClientFlutterApi.getCodec()
    );
    channel.send(
      [instanceIdArg, webViewInstanceIdArg, requestArg, errorArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

  requestLoading(
    instanceIdArg: number,
    webViewInstanceIdArg: number,
    requestArg: WebResourceRequestData,
    callback: Reply<void>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebViewClientFlutterApi.requestLoading",
      WebViewClientFlutterApi.getCodec()
    );
    channel.send(
      [instanceIdArg, webViewInstanceIdArg, requestArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

  doUpdateVisitedHistory(
    instanceIdArg: number,
    webViewInstanceIdArg: number,
    urlArg: string,
    isReloadArg: boolean,
    callback: Reply<void>
  ): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebViewClientFlutterApi.doUpdateVisitedHistory",
      WebViewClientFlutterApi.getCodec()
    );
    channel.send(
      [instanceIdArg, webViewInstanceIdArg, urlArg, isReloadArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

  onReceivedHttpAuthRequest(
    instanceIdArg: number,
    webViewInstanceIdArg: number,
    httpAuthHandlerInstanceIdArg: number,
    hostArg: string,
    realmArg: string,
    callback: Reply<void>
  ) {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.WebViewClientFlutterApi.onReceivedHttpAuthRequest",
      WebViewClientFlutterApi.getCodec()
    );
    channel.send(
      [instanceIdArg, webViewInstanceIdArg, httpAuthHandlerInstanceIdArg, hostArg, realmArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }
}

export abstract class WebSettingsHostApi {
  abstract create(instanceId: number, webViewInstanceId: number): void;

  abstract setDomStorageEnabled(instanceId: number, flag: boolean): void;

  abstract setJavaScriptCanOpenWindowsAutomatically(instanceId: number, flag: boolean): void;

  abstract setSupportMultipleWindows(instanceId: number, support: boolean): void;

  abstract setBackgroundColor(instanceId: number, color: number);

  abstract setJavaScriptEnabled(instanceId: number, flag: boolean): void;

  abstract setUserAgentString(instanceId: number, userAgentString: string): void;

  abstract setMediaPlaybackRequiresUserGesture(instanceId: number, require: boolean): void;

  abstract setSupportZoom(instanceId: number, support: boolean): void;

  abstract setLoadWithOverviewMode(instanceId: number, overview: boolean): void;

  abstract setUseWideViewPort(instanceId: number, use: boolean): void;

  abstract setDisplayZoomControls(instanceId: number, enabled: boolean): void;

  abstract setBuiltInZoomControls(instanceId: number, enabled: boolean): void;

  abstract setAllowFileAccess(instanceId: number, enabled: boolean): void;

  abstract setTextZoom(instanceId: number, textZoom: number): void;

  abstract getUserAgentString(instanceId: number): Promise<string>;

  abstract setAllowFullScreenRotate(instanceId: number, enabled: boolean): void;

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  static setup(binaryMessenger: BinaryMessenger, api: WebSettingsHostApi) {
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.create",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const webViewInstanceIdArg: number = args[1];
              try {
                api.create(instanceIdArg, webViewInstanceIdArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setDomStorageEnabled",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const flagArg: boolean = args[1];
              try {
                api.setDomStorageEnabled(
                  instanceIdArg, flagArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setJavaScriptCanOpenWindowsAutomatically",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const flagArg: boolean = args[1];
              try {
                api.setJavaScriptCanOpenWindowsAutomatically(
                  instanceIdArg, flagArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setSupportMultipleWindows",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const supportArg: boolean = args[1];
              try {
                api.setSupportMultipleWindows(
                  instanceIdArg, supportArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
        new BasicMessageChannel<ESObject>(
          binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setBackgroundColor",
          WebSettingsHostApi.getCodec()
        );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const colorArg: number = args[1];
              try {
                api.setBackgroundColor(
                  instanceIdArg,
                  colorArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setJavaScriptEnabled",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const flagArg: boolean = args[1];
              try {
                api.setJavaScriptEnabled(
                  instanceIdArg, flagArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setUserAgentString",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const userAgentStringArg: string = args[1];
              try {
                api.setUserAgentString(
                  instanceIdArg, userAgentStringArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setMediaPlaybackRequiresUserGesture",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const requireArg: boolean = args[1];
              try {
                api.setMediaPlaybackRequiresUserGesture(
                  instanceIdArg, requireArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setSupportZoom",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const supportArg: boolean = args[1];
              try {
                api.setSupportZoom(
                  instanceIdArg, supportArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setLoadWithOverviewMode",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const overviewArg: boolean = args[1];
              try {
                api.setLoadWithOverviewMode(
                  instanceIdArg, overviewArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setUseWideViewPort",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const useArg: boolean = args[1];
              try {
                api.setUseWideViewPort(
                  instanceIdArg, useArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setDisplayZoomControls",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const enabledArg: boolean = args[1];
              try {
                api.setDisplayZoomControls(
                  instanceIdArg, enabledArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setBuiltInZoomControls",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const enabledArg: boolean = args[1];
              try {
                api.setBuiltInZoomControls(
                  instanceIdArg, enabledArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setAllowFileAccess",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const enabledArg: boolean = args[1];
              try {
                api.setAllowFileAccess(
                  instanceIdArg, enabledArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setTextZoom",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const textZoomArg: number = args[1];
              try {
                api.setTextZoom(
                  instanceIdArg, textZoomArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.getUserAgentString",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: async (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                let output = await api.getUserAgentString(instanceIdArg);
                wrapped.insert(output, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebSettingsHostApi.setAllowFullScreenRotate",
        WebSettingsHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const enabledArg: boolean = args[1];
              try {
                api.setAllowFullScreenRotate(
                  instanceIdArg, enabledArg
                );
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
  }
}

export abstract class WebStorageHostApi {
  abstract create(instanceId: number): void;

  abstract deleteAllData(instanceId: number): void;

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  static setup(binaryMessenger: BinaryMessenger, api: WebStorageHostApi) {
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.WebStorageHostApi.create",
        WebStorageHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                api.create(instanceIdArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.WebStorageHostApi.deleteAllData",
        WebStorageHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              try {
                api.deleteAllData(instanceIdArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        );
      } else {
        channel.setMessageHandler(null);
      }
    }
  }
}

export abstract class GeolocationPermissionsCallbackHostApi {
  abstract invoke(instanceId: number, origin: string, allow: Boolean, retain: Boolean);

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  static setup(binaryMessenger: BinaryMessenger, api: GeolocationPermissionsCallbackHostApi) {
    {
      const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.GeolocationPermissionsCallbackHostApi.invoke",
        GeolocationPermissionsCallbackHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          new MessageHandlerBuilder((message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const instanceIdArg: number = args[0];
            const originArg: string = args[1];
            const allowArg: boolean = args[2];
            const retainArg: boolean = args[3];
            try {
              api.invoke(instanceIdArg, originArg, allowArg, retainArg);
              wrapped.insert(null, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          })
        )
      }
      else {
        channel.setMessageHandler(null);
      }
    }
  }
}

export class GeolocationPermissionsCallbackFlutterApi {
  private binaryMessenger: BinaryMessenger;

  //
  constructor(binaryMessenger: BinaryMessenger) {
    this.binaryMessenger = binaryMessenger;
  }

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  create(instanceIdArg: number, callback: Reply<void>): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.GeolocationPermissionsCallbackFlutterApi.create",
      GeolocationPermissionsCallbackFlutterApi.getCodec()
    );
    channel.send(
      [instanceIdArg],
      (channelReply: ESObject) => callback.reply(null)
    );

  }
}

export abstract class HttpAuthHandlerHostApi {
  abstract useHttpAuthUsernamePassword(instanceId: number): boolean;

  abstract cancel(instanceId: number): void;

  abstract proceed(instanceId: number, username: string, password: string): void;

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  static setup(binaryMessenger: BinaryMessenger, api: HttpAuthHandlerHostApi) {
    {
      const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.HttpAuthHandlerHostApi.useHttpAuthUsernamePassword",
        HttpAuthHandlerHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          new MessageHandlerBuilder((message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const instanceIdentifierArg: number = args[0];
            try {
              let output: boolean = api.useHttpAuthUsernamePassword(instanceIdentifierArg);
              wrapped.insert(output, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          })
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.HttpAuthHandlerHostApi.cancel",
        HttpAuthHandlerHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          new MessageHandlerBuilder((message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const instanceIdentifierArg: number = args[0];
            try {
              api.cancel(instanceIdentifierArg);
              wrapped.insert(null, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          })
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.HttpAuthHandlerHostApi.proceed",
        HttpAuthHandlerHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          new MessageHandlerBuilder((message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const instanceIdentifierArg: number = args[0] as number;
            const usernameArg: string = args[1] as string;
            const passwordArg: string = args[2] as string;
            try {
              api.proceed(instanceIdentifierArg, usernameArg, passwordArg);
              wrapped.insert(null, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          })
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
  }
}

export class HttpAuthHandlerFlutterApi {
  private binaryMessenger: BinaryMessenger;

  constructor(binaryMessenger: BinaryMessenger) {
    this.binaryMessenger = binaryMessenger;
  }

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  create(instanceIdArg: number, callback: Reply<void>): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.HttpAuthHandlerFlutterApi.create",
      HttpAuthHandlerHostApi.getCodec()
    );
    channel.send(
      [instanceIdArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }

}

export abstract class CookieManagerHostApi {
  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  abstract attachInstance(instanceIdentifier: number);

  abstract setCookie(identifier: number, url: string, value: string);

  abstract removeAllCookies(identifier: number, result: Result<Boolean>);

  abstract setAcceptThirdPartyCookies(identifier: number, accept: boolean);

  static setup(binaryMessenger: BinaryMessenger, api: CookieManagerHostApi) {
    {
      const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.CookieManagerHostApi.attachInstance",
        GeolocationPermissionsCallbackHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          new MessageHandlerBuilder((message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const instanceIdentifierArg: number = args[0];
            try {
              api.attachInstance(instanceIdentifierArg);
              wrapped.insert(null, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          })
        )
      }
      else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.CookieManagerHostApi.setCookie",
        GeolocationPermissionsCallbackHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          new MessageHandlerBuilder((message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const identifierArg: number = args[0];
            const urlArg: string = args[1];
            const valueArg: string = args[2];
            try {
              api.setCookie(identifierArg, urlArg, valueArg);
              wrapped.insert(null, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          })
        )
      }
      else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.CookieManagerHostApi.removeAllCookies",
        GeolocationPermissionsCallbackHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          new MessageHandlerBuilder((message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const identifierArg: number = args[0];
            const resultCallback: Result<Boolean> = new ResultBuilder<Boolean>(
              (result: Boolean) => {
                wrapped.insert(result, 0);              
                reply.reply(wrapped.convertToArray());
              }, (err) => {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              reply.reply(wrappedError.convertToArray());
            }
            )
            api.removeAllCookies(identifierArg, resultCallback)
          })
        )
      }
      else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.CookieManagerHostApi.setAcceptThirdPartyCookies",
        GeolocationPermissionsCallbackHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          new MessageHandlerBuilder((message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const identifierArg: number = args[0];
            const webViewIdentifierArg: number = args[1];
            const acceptArg: boolean = args[2];
            try {
              api.setAcceptThirdPartyCookies(identifierArg, acceptArg);
              wrapped.insert(null, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          })
        )
      }
      else {
        channel.setMessageHandler(null);
      }
    }
  }
}

class MessageHandlerBuilder {
  onMessage: (message: ESObject, reply: Reply<ESObject>) => void

  constructor(onMessage: (message: ESObject, reply: Reply<ESObject>) => void) {
    this.onMessage = onMessage
  }
}

export class PermissionRequestFlutterApi {
  private binaryMessenger: BinaryMessenger;

  //
  constructor(binaryMessenger: BinaryMessenger) {
    this.binaryMessenger = binaryMessenger;
  }

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  create(instanceIdArg: number, resourcesArg: string[], callback: Reply<void>): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.PermissionRequestFlutterApi.create",
      PermissionRequestFlutterApi.getCodec()
    );
    channel.send(
      [instanceIdArg, resourcesArg],
      (channelReply: ESObject) => callback.reply(null)
    );

  }
}

export abstract class CustomViewCallbackHostApi {
  abstract onCustomViewHidden(identifier: number): void;

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  static setup(binaryMessenger: BinaryMessenger, api: CustomViewCallbackHostApi) {
    {
      const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.CustomViewCallbackHostApi.onCustomViewHidden",
        CustomViewCallbackHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          new MessageHandlerBuilder((message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const instanceIdArg: number = args[0];
            const resourcesArg: string[] = args[1];
            try {
              api.onCustomViewHidden(instanceIdArg);
              wrapped.insert(null, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          })
        )
      }
      else {
        channel.setMessageHandler(null);
      }
    }
  }
}

export interface HttpAuthHandler {
  cancel(): void;

  proceed(username: string, password: string): void;

  useHttpAuthUsernamePassword(): boolean;
}

export interface CustomViewCallback {
  onCustomViewHidden(): void;
}

export class CustomViewCallbackFlutterApi {
  binaryMessenger: BinaryMessenger;

  constructor(binaryMessenger: BinaryMessenger) {
    this.binaryMessenger = binaryMessenger;
  }

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  create(identifierArg: number, callback: Reply<void>) {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.CustomViewCallbackFlutterApi.create",
      CustomViewCallbackFlutterApi.getCodec()
    );
    channel.send(
      [identifierArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }
}

export class ViewFlutterApi {
  binaryMessenger: BinaryMessenger;

  constructor(binaryMessenger: BinaryMessenger) {
    this.binaryMessenger = binaryMessenger;
  }

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  create(identifierArg: number, callback: Reply<void>) {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.ViewFlutterApi.create",
      ViewFlutterApi.getCodec()
    );
    channel.send(
      [identifierArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }
}

export abstract class PermissionRequestHostApi {
  abstract grant(instanceId: number, resources: string[]);

  abstract deny(instanceId: number);

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  static setup(binaryMessenger: BinaryMessenger, api: PermissionRequestHostApi) {
    {
      const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.PermissionRequestHostApi.grant",
        GeolocationPermissionsCallbackHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          new MessageHandlerBuilder((message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const instanceIdArg: number = args[0];
            const resourcesArg: string[] = args[1];
            try {
              api.grant(instanceIdArg, resourcesArg);
              wrapped.insert(null, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          })
        )
      }
      else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.PermissionRequestHostApi.deny",
        GeolocationPermissionsCallbackHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          new MessageHandlerBuilder((message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const instanceIdArg: number = args[0];
            try {
              api.deny(instanceIdArg);
              wrapped.insert(null, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          })
        )
      }
      else {
        channel.setMessageHandler(null);
      }
    }
  }
}

export class FileChooserParamsFlutterApi {
  private binaryMessenger: BinaryMessenger;

  constructor(binaryMessenger: BinaryMessenger) {
    this.binaryMessenger = binaryMessenger;
  }

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  tCreate(
    instanceIdArg: number,
    isCaptureEnabledArg: boolean,
    acceptTypesArg: string[],
    modeArg: FileChooserMode,
    filenameHintArg:string,
    callback: Reply<void>
  ) {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.FileChooserParamsFlutterApi.create",
      FileChooserParamsFlutterApi.getCodec()
    );
    channel.send(
      [instanceIdArg, isCaptureEnabledArg, acceptTypesArg, modeArg,
      filenameHintArg
      ],
      (channelReply: ESObject) => callback.reply(null)
    );
  }
}

export class JavaScriptChannelFlutterApi {
  private binaryMessenger: BinaryMessenger;

  constructor(binaryMessenger: BinaryMessenger) {
    this.binaryMessenger = binaryMessenger;
  }

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  postMessageT(
    instanceIdArg: number, messageArg: string, callback: Reply<void>
  ) {

    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.JavaScriptChannelFlutterApi.postMessage",
      JavaScriptChannelFlutterApi.getCodec()
    );
    channel.send(
      [instanceIdArg, messageArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }
}

export class DownloadListenerFlutterApi {
  private binaryMessenger: BinaryMessenger;

  constructor(binaryMessenger: BinaryMessenger) {
    this.binaryMessenger = binaryMessenger;
  }

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  onDownloadStartT(
    instanceIdArg: number, urlArg: string, userAgentArg: string, contentDispositionArg: string, mimetypeArg: string,
    contentLengthArg: number, callback: Reply<void>
  ) {

    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
      this.binaryMessenger,
      "dev.flutter.pigeon.webview_flutter_ohos.DownloadListenerFlutterApi.onDownloadStart",
      DownloadListenerFlutterApi.getCodec()
    );
    channel.send(
      [instanceIdArg, urlArg, userAgentArg, contentDispositionArg, mimetypeArg, contentLengthArg],
      (channelReply: ESObject) => callback.reply(null)
    );
  }
}

export abstract class DownloadListenerHostApi {
  abstract create(instanceId: number);

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  static setup(binaryMessenger: BinaryMessenger, api: DownloadListenerHostApi) {
    {
      const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.webview_flutter_ohos.DownloadListenerHostApi.create",
        DownloadListenerHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          new MessageHandlerBuilder((message: ESObject, reply: Reply<ESObject>) => {
            let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
            const args: Array<ESObject> = message;
            const instanceIdArg: number = args[0];
            try {
              api.create(instanceIdArg);
              wrapped.insert(null, 0);
            } catch (err) {
              const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped.convertToArray());
          })
        )
      }
      else {
        channel.setMessageHandler(null);
      }
    }
  }
}

export abstract class FlutterAssetManagerHostApi {
  abstract list(path: string);

  abstract getAssetFilePathByName(name: string);

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  static setup(binaryMessenger: BinaryMessenger, api: FlutterAssetManagerHostApi) {
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.FlutterAssetManagerHostApi.list",
        FlutterAssetManagerHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: async (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const pathArg: string = args[0];
              try {
                let output: ESObject = await api.list(pathArg);
                wrapped.insert(output, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.FlutterAssetManagerHostApi.getAssetFilePathByName",
        FlutterAssetManagerHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const nameArg: string = args[0];
              try {
                let output: ESObject = api.getAssetFilePathByName(nameArg);
                wrapped.insert(output, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
  }
}

export abstract class JavaScriptChannelHostApi {
  abstract create(instanceId: number, channelName: string);

  static getCodec(): MessageCodec<ESObject> {
    return WebChromeClientFlutterApiCodec.INSTANCE;
  }

  static setup(binaryMessenger: BinaryMessenger, api: JavaScriptChannelHostApi) {
    {
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.JavaScriptChannelHostApi.create",
        JavaScriptChannelHostApi.getCodec()
      );
      if (api != null) {
        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const instanceIdArg: number = args[0];
              const channelNameArg: string = args[1];
              try {
                api.create(instanceIdArg, channelNameArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )
      } else {
        channel.setMessageHandler(null);
      }
    }
  }
}

export abstract class OhosObjectHostApi {
  abstract dispose(identifier: number);

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  static setup(binaryMessenger: BinaryMessenger, api: OhosObjectHostApi) {
    {

      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.OhosObjectHostApi.dispose",
        OhosObjectHostApi.getCodec()
      );

      if (api != null) {

        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();
              const args: Array<ESObject> = message;
              const identifierArg: number = args[0];
              try {
                api.dispose(identifierArg);
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )

      }
      else {
        channel.setMessageHandler(null);
      }
    }
  }
}

export class OhosObjectFlutterApi {
  private binaryMessenger: BinaryMessenger;

  constructor(binaryMessenger: BinaryMessenger) {
    this.binaryMessenger = binaryMessenger;
  }

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  dispose(identifierArg: number, callback: Reply<void>) {

    const channel: BasicMessageChannel<ESObject> =
    new BasicMessageChannel<ESObject>(
      this.binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.OhosObjectFlutterApi.dispose",
      OhosObjectFlutterApi.getCodec()
    );

    channel.send(
      [identifierArg],
      (channelReply: ESObject) => callback.reply(null)
    );

  }
}

export interface InstanceManagerApi {
  clear: () => void;
}

export abstract class InstanceManagerHostApi {
  abstract clear: () => void;

  static getCodec(): MessageCodec<Object> {
    return new StandardMessageCodec();
  }

  /**
   * Sets up an instance of `InstanceManagerHostApi` to handle messages through the
   * `binaryMessenger`.
   */

  static setup(binaryMessenger: BinaryMessenger, api: InstanceManagerApi) {
    {

      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.webview_flutter_ohos.InstanceManagerHostApi.clear", OhosObjectHostApi.getCodec()
      );

      if (api != null) {

        channel.setMessageHandler(
          {
            onMessage: (message: ESObject, reply: Reply<ESObject>) => {
              let wrapped: ArrayList<ESObject> = new ArrayList<ESObject>();

              try {
                api.clear();
                wrapped.insert(null, 0);
              } catch (err) {
                const wrappedError: ArrayList<ESObject> = GeneratedOhosWebView.wrapError(err);
                wrapped = wrappedError;
              }
              reply.reply(wrapped.convertToArray());
            }
          }
        )

      }
      else {
        channel.setMessageHandler(null);
      }
    }
  }
}