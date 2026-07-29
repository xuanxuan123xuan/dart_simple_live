import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';

const CHANNEL_NAME = 'simple_live/ohos_scan';

export default class OhosScanPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel;
  private context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  getUniqueClassName(): string {
    return 'OhosScanPlugin';
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
    if (call.method !== 'scanQrCode') {
      result.notImplemented();
      return;
    }

    scanBarcode.startScanForResult(this.context, {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: true
    }).then((scanResult: scanBarcode.ScanResult) => {
      result.success(scanResult.originalValue);
    }).catch((error: BusinessError) => {
      if (error.code === 1000500002) {
        result.error('scan_cancelled', 'The user cancelled QR scanning', null);
      } else {
        result.error('scan_failed', `${error.code}: ${error.message}`, null);
      }
    });
  }
}
