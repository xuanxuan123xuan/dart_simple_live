import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { util } from '@kit.ArkTS';
import fileuri from '@ohos.file.fileuri';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';

const CHANNEL_NAME = 'simple_live/ohos_documents';

export default class OhosDocumentPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  getUniqueClassName(): string {
    return 'OhosDocumentPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'shareText') {
      this.shareText(call, result);
      return;
    }
    if (call.method === 'shareFile') {
      this.shareFile(call, result);
      return;
    }
    if (call.method === 'saveBytes') {
      this.saveBytes(call, result);
      return;
    }
    if (call.method === 'pickText') {
      this.pickText(call, result);
      return;
    }
    result.notImplemented();
  }

  private shareText(call: MethodCall, result: MethodResult): void {
    const text: string = call.argument('text');
    const title: string = call.argument('title');
    const isUrl: boolean = call.argument('isUrl');
    if (!text) {
      result.error('invalid_arguments', 'Shared text is empty', null);
      return;
    }
    const record: systemShare.SharedRecord = {
      utd: isUrl ? 'general.hyperlink' : 'general.plain-text',
      content: text,
      title: title
    };
    this.showSharePanel(new systemShare.SharedData(record), result);
  }

  private shareFile(call: MethodCall, result: MethodResult): void {
    const path: string = call.argument('path');
    const title: string = call.argument('title');
    if (!path) {
      result.error('invalid_arguments', 'Shared file path is empty', null);
      return;
    }
    try {
      const record: systemShare.SharedRecord = {
        utd: 'general.file-uri',
        uri: fileuri.getUriFromPath(path),
        title: title
      };
      this.showSharePanel(new systemShare.SharedData(record), result);
    } catch (error) {
      result.error('share_failed', `${error}`, null);
    }
  }

  private showSharePanel(data: systemShare.SharedData, result: MethodResult): void {
    const controller = new systemShare.ShareController(data);
    controller.show(this.context, {})
      .then(() => result.success(null))
      .catch((error: BusinessError) => {
        result.error('share_failed', `${error.code}: ${error.message}`, null);
      });
  }

  private pickText(call: MethodCall, result: MethodResult): void {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.json'];
    const documentPicker = new picker.DocumentViewPicker(this.context);
    documentPicker.select(options)
      .then((uris: Array<string>) => {
        if (uris.length === 0) {
          result.success(null);
          return;
        }
        const file = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
        try {
          const stat = fs.statSync(file.fd);
          const buffer = new ArrayBuffer(stat.size);
          fs.readSync(file.fd, buffer);
          const text = util.TextDecoder.create('utf-8')
            .decodeToString(new Uint8Array(buffer));
          result.success(text);
        } finally {
          fs.closeSync(file.fd);
        }
      })
      .catch((error: BusinessError) => {
        // 用户取消选择：某些版本报 13900042（同 saveBytes）。
        if (error.code === 13900042) {
          result.success(null);
          return;
        }
        result.error('pick_failed', `${error.code}: ${error.message}`, null);
      });
  }

  private saveBytes(call: MethodCall, result: MethodResult): void {
    const fileName: string = call.argument('fileName');
    const extension: string = call.argument('extension');
    const bytes: Uint8Array = call.argument('bytes');
    if (!fileName || bytes === undefined) {
      result.error('invalid_arguments', 'Saved file name or data is empty', null);
      return;
    }

    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    if (extension) {
      options.fileSuffixChoices = [`.${extension}`];
    }
    const documentPicker = new picker.DocumentViewPicker(this.context);
    documentPicker.save(options)
      .then((uris: Array<string>) => {
        if (uris.length === 0) {
          result.success(null);
          return;
        }
        const file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE);
        try {
          fs.truncateSync(file.fd, 0);
          const data = bytes.buffer.slice(
            bytes.byteOffset,
            bytes.byteOffset + bytes.byteLength
          );
          fs.writeSync(file.fd, data);
          fs.fsyncSync(file.fd);
        } finally {
          fs.closeSync(file.fd);
        }
        result.success(uris[0]);
      })
      .catch((error: BusinessError) => {
        // Some HarmonyOS File Picker releases report closing the picker as
        // the generic file-service error. Treat it as a normal cancellation.
        if (error.code === 13900042) {
          result.success(null);
          return;
        }
        result.error('save_failed', `${error.code}: ${error.message}`, null);
      });
  }
}
