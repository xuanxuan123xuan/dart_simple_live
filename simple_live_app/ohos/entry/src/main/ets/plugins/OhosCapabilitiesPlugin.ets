import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import deviceInfo from '@ohos.deviceInfo';
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
    if (call.method === 'getPlaybackCapabilities') {
      this.getPlaybackCapabilities(result);
      return;
    }
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

  private getPlaybackCapabilities(result: MethodResult): void {
    let supported = false;
    try {
      // The low-latency media-source configuration is available from API 12.
      supported = deviceInfo.sdkApiVersion >= 12;
    } catch (error) {
      // Capability detection is fail-closed so an unknown/old device stays on
      // the stable playback profile.
      supported = false;
    }
    result.success({
      'lowLatencyExperimentalSupported': supported
    });
  }
}
