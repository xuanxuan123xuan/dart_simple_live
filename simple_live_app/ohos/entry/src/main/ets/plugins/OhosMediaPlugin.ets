import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import fileuri from '@ohos.file.fileuri';
import image from '@ohos.multimedia.image';
import window from '@ohos.window';

const CHANNEL_NAME = 'simple_live/ohos_media';

export default class OhosMediaPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel;
  private context?: common.Context;

  getUniqueClassName(): string {
    return 'OhosMediaPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
    this.context = undefined;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'captureWindowRegion') {
      this.captureWindowRegion(call, result);
    } else if (call.method === 'saveImage') {
      this.saveImage(call, result);
    } else {
      result.notImplemented();
    }
  }

  private captureWindowRegion(call: MethodCall, result: MethodResult): void {
    const context = this.context;
    if (context === undefined) {
      result.error('no_context', 'Application context is unavailable', null);
      return;
    }

    const requestedX: number = call.argument('x');
    const requestedY: number = call.argument('y');
    const requestedWidth: number = call.argument('width');
    const requestedHeight: number = call.argument('height');
    if (requestedWidth <= 0 || requestedHeight <= 0) {
      result.error('invalid_region', 'Screenshot region is empty', null);
      return;
    }

    window.getLastWindow(context)
      .then((appWindow: window.Window) => appWindow.snapshot())
      .then(async (pixelMap: image.PixelMap) => {
        const packer = image.createImagePacker();
        try {
          const info = await pixelMap.getImageInfo();
          const x = Math.max(0, Math.min(Math.round(requestedX), info.size.width - 1));
          const y = Math.max(0, Math.min(Math.round(requestedY), info.size.height - 1));
          const width = Math.max(1, Math.min(Math.round(requestedWidth), info.size.width - x));
          const height = Math.max(1, Math.min(Math.round(requestedHeight), info.size.height - y));
          await pixelMap.crop({ x: x, y: y, size: { width: width, height: height } });
          const bytes = await packer.packing(pixelMap, {
            format: 'image/png',
            quality: 100
          });
          result.success(new Uint8Array(bytes));
        } catch (error) {
          result.error('capture_failed', `${error}`, null);
        } finally {
          await pixelMap.release();
          await packer.release();
        }
      })
      .catch((error: Error) => {
        result.error('capture_failed', `${error}`, null);
      });
  }

  private saveImage(call: MethodCall, result: MethodResult): void {

    const path: string = call.argument('path');
    const title: string = call.argument('title');
    const extension: string = call.argument('extension');
    const context = this.context;
    if (!path || !title || !extension || context === undefined) {
      result.error('invalid_arguments', 'Screenshot path or metadata is empty', null);
      return;
    }

    try {
      const sourceUri = fileuri.getUriFromPath(path);
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const config: photoAccessHelper.PhotoCreationConfig = {
        title: title,
        fileNameExtension: extension,
        photoType: photoAccessHelper.PhotoType.IMAGE
      };
      helper.showAssetsCreationDialog([sourceUri], [config])
        .then((savedUris: Array<string>) => {
          if (savedUris.length === 0) {
            result.error('save_cancelled', 'No image was saved', null);
            return;
          }
          result.success(savedUris[0]);
        })
        .catch((error: Error) => {
          result.error('save_failed', `${error}`, null);
        });
    } catch (error) {
      result.error('save_failed', `${error}`, null);
    }
  }
}
