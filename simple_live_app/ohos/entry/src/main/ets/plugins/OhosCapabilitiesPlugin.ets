import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import PiPWindow from '@ohos.PiPWindow';

const CHANNEL_NAME = 'simple_live/ohos_capabilities';

export default class OhosCapabilitiesPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel;

  getUniqueClassName(): string {
    return 'OhosCapabilitiesPlugin';
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
    if (call.method !== 'getPipCapabilities') {
      result.notImplemented();
      return;
    }
    try {
      const available = PiPWindow.isPiPEnabled();
      result.success({
        'pipAvailable': available,
        'pipAutoOnLeaveSupported': available,
        'pipCanHideDanmaku': available
      });
    } catch (error) {
      result.error('pip_capability_failed', `${error}`, null);
    }
  }
}
