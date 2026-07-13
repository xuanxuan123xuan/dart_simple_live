import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import web_webview from '@ohos.web.webview';

const CHANNEL_NAME = 'simple_live/ohos_web_cookie';

export default class OhosWebCookiePlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel;

  getUniqueClassName(): string {
    return 'OhosWebCookiePlugin';
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
    if (call.method !== 'getCookie') {
      result.notImplemented();
      return;
    }
    const url: string = call.argument('url');
    if (!url) {
      result.error('invalid_url', 'Cookie URL is empty', null);
      return;
    }
    try {
      // Persist the latest ArkWeb cookie jar before Flutter reads it. Login on
      // live.kuaishou.com is an SPA flow and may not cause a page navigation.
      web_webview.WebCookieManager.saveCookieSync();
      result.success(web_webview.WebCookieManager.fetchCookieSync(url));
    } catch (error) {
      result.error('cookie_read_failed', `${error}`, null);
    }
  }
}
