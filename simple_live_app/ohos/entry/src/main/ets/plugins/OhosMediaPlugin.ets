import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { audio } from '@kit.AudioKit';
import fileuri from '@ohos.file.fileuri';
import image from '@ohos.multimedia.image';
import window from '@ohos.window';

const CHANNEL_NAME = 'simple_live/ohos_media';
const SYSTEM_MEDIA_VOLUME_LEVEL_KEY = 'simple_live_system_media_volume_level';

interface MediaVolumeRange {
  current: number;
  min: number;
  max: number;
}

export default class OhosMediaPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel?: MethodChannel;
  private context?: common.UIAbilityContext;
  private mediaVolumeMin?: number;
  private mediaVolumeMax?: number;

  getUniqueClassName(): string {
    return 'OhosMediaPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.context = undefined;
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
    } else if (call.method === 'getSystemMediaVolume') {
      this.getSystemMediaVolume(result);
    } else if (call.method === 'setSystemMediaVolume') {
      this.setSystemMediaVolume(call, result);
    } else {
      result.notImplemented();
    }
  }

  private async readMediaVolumeRange(): Promise<MediaVolumeRange> {
    const volumeManager = audio.getAudioManager().getVolumeManager();
    const groupManager = await volumeManager.getVolumeGroupManager(audio.DEFAULT_VOLUME_GROUP_ID);
    const current = await groupManager.getVolume(audio.AudioVolumeType.MEDIA);
    const min = await groupManager.getMinVolume(audio.AudioVolumeType.MEDIA);
    const max = await groupManager.getMaxVolume(audio.AudioVolumeType.MEDIA);
    this.mediaVolumeMin = min;
    this.mediaVolumeMax = max;
    return { current: current, min: min, max: max };
  }

  private getSystemMediaVolume(result: MethodResult): void {
    this.readMediaVolumeRange()
      .then((range: MediaVolumeRange) => {
        const span = range.max - range.min;
        const normalized = span > 0 ? (range.current - range.min) / span : 0;
        AppStorage.setOrCreate<number>(SYSTEM_MEDIA_VOLUME_LEVEL_KEY, range.current);
        result.success(Math.max(0, Math.min(1, normalized)));
      })
      .catch((error: Error) => {
        result.error('get_system_media_volume_failed', `${error}`, null);
      });
  }

  private setSystemMediaVolume(call: MethodCall, result: MethodResult): void {
    const requested: number = call.argument('volume');
    if (!Number.isFinite(requested)) {
      result.error('invalid_volume', 'System media volume must be a number', null);
      return;
    }
    const normalized = Math.max(0, Math.min(1, requested));
    if (this.mediaVolumeMin !== undefined && this.mediaVolumeMax !== undefined) {
      this.applySystemMediaVolume(normalized, this.mediaVolumeMin, this.mediaVolumeMax);
      result.success(null);
      return;
    }
    this.readMediaVolumeRange()
      .then((range: MediaVolumeRange) => {
        this.applySystemMediaVolume(normalized, range.min, range.max);
        result.success(null);
      })
      .catch((error: Error) => {
        result.error('set_system_media_volume_failed', `${error}`, null);
      });
  }

  private applySystemMediaVolume(normalized: number, min: number, max: number): void {
    const level = Math.round(min + normalized * (max - min));
    // Third-party apps drive system output volume through AVVolumePanel. The
    // linked value is consumed by the panel hosted in pages/Index.ets.
    AppStorage.setOrCreate<number>(SYSTEM_MEDIA_VOLUME_LEVEL_KEY, level);
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

    try {
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
    } catch (error) {
      result.error('capture_failed', `${error}`, null);
    }
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
          // Cancelling the system dialog is not a failure. Report null so the
          // Dart side can tell "user cancelled" from "save failed", matching
          // OhosDocumentPlugin.saveBytes.
          if (savedUris.length === 0) {
            result.success(null);
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
