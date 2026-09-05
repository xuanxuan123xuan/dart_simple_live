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
import common from '@ohos.app.ability.common';
import { PipPlaybackTarget } from '../pip/PipSurfaceRegistry';
import { OhosPipManager } from '../pip/OhosPipManager';
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
  private onEvent: (event: MpvEvent) => void;

  constructor(onEvent: (event: MpvEvent) => void) {
    this.onEvent = onEvent;
  }

  onListen(args: Object, events: EventSink): void {
    this.sink = events;
    const forward = (event: MpvEvent) => {
      this.onEvent(event);
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

export default class OhosMpvPlugin implements FlutterPlugin, MethodCallHandler, PipPlaybackTarget {
  private context: common.UIAbilityContext;
  private pipManager?: OhosPipManager;
  private channel?: MethodChannel;
  private eventChannel?: EventChannel;
  private textureRegistry?: TextureRegistry;
  private textureId: number = -1;
  private cachedSurfaceId: string = '';
  // Keep Flutter geometry separate from the PiP XComponent's buffer size.
  // The native g_geoW/g_geoH describe whichever output is currently active.
  private flutterSurfaceWidth: number = 1920;
  private flutterSurfaceHeight: number = 1080;
  private pipOutputActive: boolean = false;
  // Monotonic token handed to each Dart controller on create(); used by
  // dispose() to ignore stale controllers whose room has already switched.
  private createSeq: number = 0;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  getUniqueClassName(): string {
    return 'OhosMpvPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.textureRegistry = binding.getTextureRegistry();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), METHOD_CHANNEL);
    this.channel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), EVENT_CHANNEL);
    this.eventChannel.setStreamHandler(new MpvStreamHandler((event: MpvEvent) => {
      if (event.gen === this.createSeq && event.kind === 'property' && event.name === 'pause') {
        this.pipManager?.syncPlaybackState(this);
      }
    }));
    // Picture-in-picture manager now lives here (mpv is the only playback
    // backend) instead of inside the removed video_player_ohos plugin. It
    // registers the 'simple_live/ohos_pip' channel that OhosPipService talks
    // to from Dart.
    this.pipManager = new OhosPipManager(this.context);
    this.pipManager.setup(binding.getBinaryMessenger());
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.pipManager?.clearPlayer(this);
    this.pipManager?.detach();
    this.pipManager = undefined;
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
    this.eventChannel?.setStreamHandler(null);
    this.eventChannel = undefined;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'create' &&
      (call.argument('generation') as number) !== this.createSeq) {
      result.error('stale_player', 'Playback session has been replaced.', null);
      return;
    }
    switch (call.method) {
      case 'create':
        this.create(result);
        break;
      case 'loadFile':
        this.loadFile(call, result);
        break;
      case 'setProperty':
        mpvNapi.setPropertyString(
          call.argument('name') as string,
          call.argument('value') as string,
          call.argument('generation') as number
        ).then(() => result.success(null)).catch((error: Error) => {
          result.error('mpv_property_failed', `${error}`, null);
        });
        break;
      case 'getProperty':
        result.success(mpvNapi.getPropertyString(call.argument('name') as string));
        break;
      case 'setGeometry':
      case 'reconfigureSurface':
        this.reconfigureFlutterSurface(call, result);
        break;
      case 'getSurfaceSize':
        result.success(this.pipOutputActive
          ? { 'width': this.flutterSurfaceWidth, 'height': this.flutterSurfaceHeight }
          : mpvNapi.getSurfaceSize());
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
          this.pipManager?.clearPlayer(this);
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
      this.pipManager?.setActivePlayer(this);
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
    this.pipManager?.setActivePlayer(this);
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
        if (/[\r\n:]/.test(key) || /[\r\n]/.test(headers[key])) {
          result.error('invalid_header', 'Playback headers contain invalid characters.', null);
          return;
        }
        // mpv parses http-header-fields as a comma-separated list. Cookies
        // and User-Agent values can contain commas and backslashes.
        parts.push(`${key}: ${headers[key]}`.replace(/\\/g, '\\\\').replace(/,/g, '\\,'));
      }
      joined = parts.join(',');
    }
    mpvNapi.loadFile(url, joined, call.argument('generation') as number);
    result.success(null);
  }

  private reconfigureFlutterSurface(call: MethodCall, result: MethodResult): void {
    const width = call.argument('width') as number;
    const height = call.argument('height') as number;
    if (!Number.isInteger(width) || !Number.isInteger(height) ||
      width < 16 || height < 16 || width > 32768 || height > 32768) {
      result.error('mpv_geometry_failed', 'Invalid Flutter surface dimensions.', null);
      return;
    }
    this.flutterSurfaceWidth = width;
    this.flutterSurfaceHeight = height;
    if (this.pipOutputActive) {
      // Remember new stream geometry for restore without resizing the PiP
      // output behind its XComponent. PiP owns its own surface dimensions.
      result.success(null);
      return;
    }
    mpvNapi.reconfigureSurface(width, height, this.createSeq)
      .then(() => result.success(null)).catch((error: Error) => {
        result.error('mpv_reconfigure_failed', `${error}`, null);
      });
  }

  play(): void {
    mpvNapi.setPropertyString('pause', 'no', this.createSeq).catch(() => {});
  }

  pause(): void {
    mpvNapi.setPropertyString('pause', 'yes', this.createSeq).catch(() => {});
  }

  isPlaying(): boolean {
    return mpvNapi.getPropertyString('pause') !== 'yes';
  }

  useOutputSurface(surfaceId: string, width?: number, height?: number): void {
    if (surfaceId.length === 0) {
      throw new Error('Picture-in-picture output surface is unavailable.');
    }
    this.pipOutputActive = true;
    if (width !== undefined && height !== undefined &&
      Number.isFinite(width) && Number.isFinite(height) && width >= 16 && height >= 16) {
      mpvNapi.switchSurface(surfaceId, this.createSeq, Math.round(width), Math.round(height))
        .catch((error: Error) => {
          hilog.error(0x3200, TAG,
            'useOutputSurface failed (with size) surfaceId=' + surfaceId +
            ' width=' + width + ' height=' + height + ' error=' + error.message);
        });
    } else {
      mpvNapi.switchSurface(surfaceId, this.createSeq)
        .catch((error: Error) => {
          hilog.error(0x3200, TAG,
            'useOutputSurface failed surfaceId=' + surfaceId + ' error=' + error.message);
        });
    }
  }

  restoreOutputSurface(): void {
    if (this.cachedSurfaceId.length === 0) {
      return;
    }
    this.pipOutputActive = false;
    mpvNapi.switchSurface(this.cachedSurfaceId, this.createSeq,
      this.flutterSurfaceWidth, this.flutterSurfaceHeight)
      .catch((error: Error) => {
        hilog.error(0x3200, TAG,
          'restoreOutputSurface failed surfaceId=' + this.cachedSurfaceId +
          ' error=' + error.message);
      });
  }
}
