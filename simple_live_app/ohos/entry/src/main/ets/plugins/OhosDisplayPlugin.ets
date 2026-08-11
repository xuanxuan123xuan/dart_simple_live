import {
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import { common } from '@kit.AbilityKit';
import window from '@ohos.window';

const TAG = 'OhosDisplayPlugin';
const CHANNEL_NAME = 'simple_live/ohos_display';

export default class OhosDisplayPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel?: MethodChannel;
  private context?: common.UIAbilityContext;
  private keepScreenOn: boolean = false;

  getUniqueClassName(): string {
    return 'OhosDisplayPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    const context = this.context;
    this.context = undefined;
    this.releaseKeepScreenOn(context);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
    this.releaseKeepScreenOn(this.context);
    this.context = undefined;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'setKeepScreenOn':
        this.setKeepScreenOn(call, result);
        return;
      case 'getKeepScreenOn':
        result.success(this.keepScreenOn);
        return;
      default:
        result.notImplemented();
    }
  }

  private setKeepScreenOn(call: MethodCall, result: MethodResult): void {
    const context = this.context;
    if (context === undefined) {
      result.error('no_context', 'Application context is unavailable', null);
      return;
    }
    const enabled: boolean = call.argument('enabled');
    if (enabled === this.keepScreenOn) {
      result.success(null);
      return;
    }
    window.getLastWindow(context)
      .then((appWindow: window.Window) => appWindow.setWindowKeepScreenOn(enabled))
      .then(() => {
        this.keepScreenOn = enabled;
        result.success(null);
      })
      .catch((error: Error) => {
        result.error('keep_screen_on_failed', `${error}`, null);
      });
  }

  private releaseKeepScreenOn(context?: common.UIAbilityContext): void {
    this.keepScreenOn = false;
    if (context === undefined) return;
    window.getLastWindow(context)
      .then((appWindow: window.Window) => appWindow.setWindowKeepScreenOn(false))
      .catch((error: Error) => Log.w(TAG, `Failed to release keep-screen-on: ${error}`));
  }
}
