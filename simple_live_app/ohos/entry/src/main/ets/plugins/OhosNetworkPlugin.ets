import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import connection from '@ohos.net.connection';

const CHANNEL_NAME = 'simple_live/ohos_network';

export default class OhosNetworkPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel;

  getUniqueClassName(): string {
    return 'OhosNetworkPlugin';
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
    if (call.method !== 'getNetworkType') {
      result.notImplemented();
      return;
    }

    connection.getDefaultNet()
      .then((handle: connection.NetHandle) => connection.getNetCapabilities(handle))
      .then((capabilities: connection.NetCapabilities) => {
        const bearers = capabilities.bearerTypes;
        if (bearers.includes(connection.NetBearType.BEARER_CELLULAR)) {
          result.success('cellular');
        } else if (bearers.includes(connection.NetBearType.BEARER_WIFI)) {
          result.success('wifi');
        } else if (bearers.includes(connection.NetBearType.BEARER_ETHERNET)) {
          result.success('ethernet');
        } else {
          result.success('other');
        }
      })
      .catch((error: Error) => {
        result.error('network_query_failed', `${error}`, null);
      });
  }
}
