import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { avSession } from '@kit.AVSessionKit';

const CHANNEL_NAME = 'simple_live/background_playback';
const BUNDLE_NAME = 'com.simplelive.app';
const ABILITY_NAME = 'EntryAbility';

export default class OhosBackgroundPlaybackPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel;
  private context: common.UIAbilityContext;
  private session?: avSession.AVSession;
  private running: boolean = false;
  private siteId: string = '';
  private roomId: string = '';
  private metadata: avSession.AVMetadata = {
    assetId: 'simple_live_current_room',
    title: 'Simple Live',
    artist: '直播播放',
    album: 'Simple Live'
  };

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  getUniqueClassName(): string {
    return 'OhosBackgroundPlaybackPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
    this.releaseResources().catch((_error: Error) => {});
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'start') {
      this.start(result);
      return;
    }
    if (call.method === 'stop') {
      this.stop(result);
      return;
    }
    if (call.method === 'updateMetadata') {
      this.updateMetadata(call, result);
      return;
    }
    if (call.method === 'release') {
      this.release(result);
      return;
    }
    result.notImplemented();
  }

  private async ensureSession(): Promise<void> {
    if (this.session !== undefined) return;
    const session = await avSession.createAVSession(this.context, 'simple_live_playback', 'video');
    try {
      session.on('play', () => this.channel?.invokeMethod('play', null));
      session.on('pause', () => this.channel?.invokeMethod('pause', null));
      await session.setAVMetadata(this.metadata);
      await session.activate();
    } catch (error) {
      // Session was created but not fully initialized; tear it down so no
      // half-activated session is left dangling.
      try {
        await session.deactivate();
      } catch (_error) {
      }
      try {
        await session.destroy();
      } catch (_error) {
      }
      throw error;
    }
    this.session = session;
  }

  private async updateMetadata(call: MethodCall, result: MethodResult): Promise<void> {
    const assetId: string = call.argument('assetId');
    const siteId: string = call.argument('siteId');
    const roomId: string = call.argument('roomId');
    const title: string = call.argument('title');
    const artist: string = call.argument('artist');
    const album: string = call.argument('album');
    const artwork: string = call.argument('artwork');
    const metadata: avSession.AVMetadata = {
      assetId: assetId || 'simple_live_current_room',
      title: title || 'Simple Live',
      artist: artist || '直播播放',
      album: album || 'Simple Live'
    };
    if (artwork) {
      metadata.mediaImage = artwork;
    }
    this.metadata = metadata;
    this.siteId = siteId || '';
    this.roomId = roomId || '';
    try {
      await this.session?.setAVMetadata(metadata);
      result.success(null);
    } catch (error) {
      result.error('metadata_update_failed', `${error}`, null);
    }
  }

  private async start(result: MethodResult): Promise<void> {
    if (this.running) {
      result.success(null);
      return;
    }
    try {
      await this.ensureSession();
      await this.session?.setAVPlaybackState({
        state: avSession.PlaybackState.PLAYBACK_STATE_PLAY,
        speed: 1
      });
      const agentInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: BUNDLE_NAME,
          abilityName: ABILITY_NAME,
          parameters: {
            roomId: this.roomId,
            siteId: this.siteId
          }
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 1207,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent: WantAgent = await wantAgent.getWantAgent(agentInfo);
      await backgroundTaskManager.startBackgroundRunning(
        this.context,
        ['audioPlayback'],
        agent
      );
      this.running = true;
      result.success(null);
    } catch (error) {
      // The session may already be created/activated before the background
      // task starts; reclaim it so no activated session is left dangling.
      await this.releaseResources().catch((_error: Error) => {});
      result.error('background_start_failed', `${error}`, null);
    }
  }

  private async stop(result: MethodResult): Promise<void> {
    try {
      await this.stopBackgroundTask();
      await this.session?.setAVPlaybackState({
        state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        speed: 0
      });
      result.success(null);
    } catch (error) {
      result.error('background_stop_failed', `${error}`, null);
    }
  }

  private async release(result: MethodResult): Promise<void> {
    try {
      await this.releaseResources();
      result.success(null);
    } catch (error) {
      result.error('background_release_failed', `${error}`, null);
    }
  }

  private async stopBackgroundTask(): Promise<void> {
    if (!this.running) return;
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context);
    } finally {
      this.running = false;
    }
  }

  private async releaseResources(): Promise<void> {
    await this.stopBackgroundTask();
    const session = this.session;
    this.session = undefined;
    if (session === undefined) return;
    try {
      await session.setAVPlaybackState({
        state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        speed: 0
      });
    } catch (_error) {
    }
    try {
      await session.deactivate();
    } finally {
      await session.destroy();
    }
  }
}
