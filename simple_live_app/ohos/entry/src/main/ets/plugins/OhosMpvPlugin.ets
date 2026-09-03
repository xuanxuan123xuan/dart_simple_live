import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  EventChannel,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { EventSink, StreamHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { TextureRegistry } from '@ohos/flutter_ohos/src/main/ets/view/TextureRegistry';
import mpvNapi from 'libmpv_napi.so';

const TAG = 'OhosMpvPlugin';
const METHOD_CHANNEL = 'simple_live/ohos_mpv';
const EVENT_CHANNEL = 'simple_live/ohos_mpv_events';

interface MpvEvent {
  kind: string;
  name: string;
  value: string;
  text: string;
  gen: number;
}

class MpvStreamHandler implements StreamHandler {
  private sink: EventSink | null = null;

  onListen(args: Object, events: EventSink): void {
    this.sink = events;
    const forward = (event: MpvEvent) => {
      if (this.sink !== null) {
        this.sink.success({
          'kind': event.kind,
          'name': event.name,
          'value': event.value,
          'text': event.text,
          'gen': event.gen
        });
      }
    };
    mpvNapi.setEventCallback(forward);
  }

  onCancel(args: Object): void {
    this.sink = null;
  }
}

export default class OhosMpvPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel;
  private eventChannel?: EventChannel;
  private textureRegistry?: TextureRegistry;
  private textureId: number = -1;
  private cachedSurfaceId: string = '';
  // Monotonic token handed to each Dart controller on create(); used by
  // dispose() to ignore stale controllers whose room has already switched.
  private createSeq: number = 0;

  getUniqueClassName(): string {
    return 'OhosMpvPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.textureRegistry = binding.getTextureRegistry();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), METHOD_CHANNEL);
    this.channel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), EVENT_CHANNEL);
    this.eventChannel.setStreamHandler(new MpvStreamHandler());
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
    this.eventChannel?.setStreamHandler(null);
    this.eventChannel = undefined;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'create':
        this.create(result);
        break;
      case 'loadFile':
        this.loadFile(call, result);
        break;
      case 'setProperty':
        mpvNapi.setPropertyString(call.argument('name') as string, call.argument('value') as string);
        result.success(null);
        break;
      case 'getProperty':
        result.success(mpvNapi.getPropertyString(call.argument('name') as string));
        break;
      case 'setGeometry':
        mpvNapi.setGeometry(call.argument('width') as number, call.argument('height') as number);
        result.success(null);
        break;
      case 'command':
        mpvNapi.commandString(call.argument('cmd') as string);
        result.success(null);
        break;
      case 'dispose':
        // Stop playback only when the caller owns the current generation;
        // stale controllers (room already switched) must not kill the new
        // stream. mpv and the output texture stay alive for the whole app
        // session: room switches are loadfile-replace, and repeatedly
        // recreating the Vulkan device degrades the Maleoon driver.
        const generation = call.argument('generation') as number;
        const matched = generation === this.createSeq;
        hilog.info(0x3200, TAG, 'dispose gen=' + generation + ' seq=' + this.createSeq + ' stop=' + matched);
        if (matched) {
          mpvNapi.commandString('stop');
        }
        result.success(null);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private create(result: MethodResult): void {
    const registry = this.textureRegistry;
    if (registry === undefined) {
      result.error('no_registry', 'TextureRegistry unavailable', null);
      return;
    }
    if (this.textureId >= 0) {
      this.createSeq++;
      result.success({
        'textureId': this.textureId,
        'surfaceId': this.cachedSurfaceId,
        'generation': this.createSeq
      });
      return;
    }
    const textureId: number = registry.getTextureId();
    const entry = registry.registerTexture(textureId);
    this.textureId = textureId;
    this.cachedSurfaceId = entry.getSurfaceId().toString();
    hilog.info(0x3200, TAG, 'create: before napi init');
    mpvNapi.init(this.cachedSurfaceId, 1920, 1080);
    hilog.info(0x3200, TAG, 'create: after napi init');
    this.createSeq++;
    result.success({
      'textureId': this.textureId,
      'surfaceId': this.cachedSurfaceId,
      'generation': this.createSeq
    });
  }

  private loadFile(call: MethodCall, result: MethodResult): void {
    const url = call.argument('url') as string;
    const headers = call.argument('headers') as Record<string, string> | null;
    let joined = '';
    if (headers !== null && headers !== undefined) {
      const parts: string[] = [];
      for (const key of Object.keys(headers)) {
        parts.push(`${key}: ${headers[key]}`);
      }
      joined = parts.join(',');
    }
    mpvNapi.loadFile(url, joined, this.createSeq);
    result.success(null);
  }
}
