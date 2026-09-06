import {
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { avSession } from '@kit.AVSessionKit';

const TAG = 'OhosBackgroundPlaybackPlugin';
const CHANNEL_NAME = 'simple_live/background_playback';
const BUNDLE_NAME = 'com.simplelive.app';
const ABILITY_NAME = 'EntryAbility';
const AUDIO_FOCUS_RETRY_LIMIT = 3;
const AUDIO_FOCUS_RETRY_DELAY_MS = 500;

interface FocusPayload { focused: boolean; reason?: number }
interface RecoveryPayload { scheduled: boolean; attempt: number; delayMs: number }
interface StatePayload { running: boolean; focused: boolean; requestedPlaying: boolean }

/**
 * Owns the AVSession and the continuous audio playback task used while the
 * Flutter page is backgrounded.
 *
 * The AVSession and audio session are separate HarmonyOS resources. Keeping
 * both in this plugin makes the lifecycle explicit: start acquires focus and
 * publishes PLAY before requesting the continuous task; stop/release pauses
 * the session, drops the task, and releases focus. The small recovery loop
 * handles the API-12 audio-session timeout callback without fighting a
 * foreground media app indefinitely.
 */
export default class OhosBackgroundPlaybackPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel;
  private context: common.UIAbilityContext;
  private session?: avSession.AVSession;
  private running: boolean = false;
  private requestedPlaying: boolean = false;
  private audioSessionManager?: audio.AudioSessionManager;
  private audioSessionListenerBound: boolean = false;
  private audioFocusActive: boolean = false;
  private audioFocusRetryTimer: number | undefined = undefined;
  private audioFocusRetryCount: number = 0;
  private transition: Promise<void> = Promise.resolve() as Promise<void>;
  private siteId: string = '';
  private roomId: string = '';
  private metadata: avSession.AVMetadata = {
    assetId: 'simple_live_current_room',
    title: 'Simple Live',
    artist: '直播播放',
    album: 'Simple Live'
  };

  private readonly audioSessionDeactivatedListener =
    (event: audio.AudioSessionDeactivatedEvent): void => {
      this.audioFocusActive = false;
      const payload: FocusPayload = {
        'focused': false,
        'reason': event.reason
      };
      this.notifyFlutter('audioFocusChanged', payload);
      Log.i(TAG, `audio session deactivated reason=${event.reason}`);

      if (this.running && this.requestedPlaying) {
        this.scheduleAudioFocusRecovery();
      }
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
    // Engine teardown must use the same queue as channel calls. This avoids
    // destroying a session while an in-flight start is still creating it.
    this.enqueue(() => this.releaseResources()).catch((_error: Error) => {});
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'start') {
      this.dispatch(result, () => this.start(), 'background_start_failed');
      return;
    }
    if (call.method === 'stop') {
      this.dispatch(result, () => this.stop(), 'background_stop_failed');
      return;
    }
    if (call.method === 'updateMetadata') {
      this.dispatch(
        result,
        () => this.updateMetadata(call),
        'metadata_update_failed'
      );
      return;
    }
    if (call.method === 'release') {
      this.dispatch(result, () => this.releaseResources(), 'background_release_failed');
      return;
    }
    if (call.method === 'getState') {
      result.success({
        'running': this.running,
        'focused': this.audioFocusActive,
        'requestedPlaying': this.requestedPlaying
      });
      return;
    }
    result.notImplemented();
  }

  private dispatch(
    result: MethodResult,
    operation: () => Promise<void>,
    errorCode: string
  ): void {
    this.enqueue(operation).then(() => {
      result.success(null);
    }).catch((error: Error) => {
      result.error(errorCode, `${error}`, null);
    });
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next = this.transition.then(operation, operation);
    // Keep the queue usable after a failed operation. The caller still gets
    // the original rejection through `next`.
    this.transition = next.catch((_error: Error) => {});
    return next;
  }

  private async ensureSession(): Promise<void> {
    if (this.session !== undefined) return;
    const session = await avSession.createAVSession(
      this.context,
      'simple_live_playback',
      'video'
    );
    try {
      session.on('play', () => {
        this.requestedPlaying = true;
        this.notifyFlutter('play', null);
      });
      session.on('pause', () => {
        this.requestedPlaying = false;
        this.notifyFlutter('pause', null);
      });
      session.on('stop', () => {
        this.requestedPlaying = false;
        this.notifyFlutter('stop', null);
      });
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
      throw new Error(`ensureSession failed: ${error}`);
    }
    this.session = session;
  }

  private async updateMetadata(call: MethodCall): Promise<void> {
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
    await this.session?.setAVMetadata(metadata);
  }

  private async start(): Promise<void> {
    this.requestedPlaying = true;
    await this.ensureSession();
    await this.activateAudioFocus();
    await this.session?.setAVPlaybackState({
      state: avSession.PlaybackState.PLAYBACK_STATE_PLAY,
      speed: 1
    });

    if (this.running) {
      // A repeated start can repair audio focus and playback state without
      // requesting a second continuous task.
      this.notifyState();
      return;
    }

    try {
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
      // AVSession controls and the continuous-task notification should open
      // the same ability, including the current room target.
      await this.session?.setLaunchAbility(agent);
      await backgroundTaskManager.startBackgroundRunning(
        this.context,
        ['audioPlayback'],
        agent
      );
      this.running = true;
      this.audioFocusRetryCount = 0;
      this.notifyState();
    } catch (error) {
      // The session/focus may already be active before task creation fails;
      // reclaim all resources so a later retry starts from a clean state.
      await this.releaseResources().catch((_error: Error) => {});
      throw new Error(`${error}`);
    }
  }

  private async stop(): Promise<void> {
    this.requestedPlaying = false;
    this.clearAudioFocusRecovery();
    await this.stopBackgroundTask();
    await this.session?.setAVPlaybackState({
      state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      speed: 0
    });
    await this.deactivateAudioFocus();
    this.notifyState();
  }

  private async ensureAudioSessionManager(): Promise<audio.AudioSessionManager | undefined> {
    if (this.audioSessionManager !== undefined) {
      return this.audioSessionManager;
    }
    try {
      this.audioSessionManager = audio.getAudioManager().getSessionManager();
      this.bindAudioSessionListener(this.audioSessionManager);
      return this.audioSessionManager;
    } catch (error) {
      Log.w(TAG, `getSessionManager failed: ${error}`);
      return undefined;
    }
  }

  private bindAudioSessionListener(manager: audio.AudioSessionManager): void {
    if (this.audioSessionListenerBound) return;
    try {
      manager.on(
        'audioSessionDeactivated',
        this.audioSessionDeactivatedListener
      );
      this.audioSessionListenerBound = true;
    } catch (error) {
      Log.w(TAG, `on audioSessionDeactivated failed: ${error}`);
    }
  }

  private async activateAudioFocus(): Promise<boolean> {
    const manager = await this.ensureAudioSessionManager();
    if (manager === undefined) {
      this.audioFocusActive = false;
      const payload: FocusPayload = { 'focused': false };
      this.notifyFlutter('audioFocusChanged', payload);
      return false;
    }
    try {
      if (!manager.isAudioSessionActivated()) {
        await manager.activateAudioSession({
          concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT
        });
      }
      this.audioFocusActive = true;
      this.audioFocusRetryCount = 0;
      const payload: FocusPayload = { 'focused': true };
      this.notifyFlutter('audioFocusChanged', payload);
      return true;
    } catch (error) {
      this.audioFocusActive = false;
      Log.w(TAG, `activateAudioSession failed: ${error}`);
      const payload: FocusPayload = { 'focused': false };
      this.notifyFlutter('audioFocusChanged', payload);
      return false;
    }
  }

  private async deactivateAudioFocus(): Promise<void> {
    const manager = this.audioSessionManager;
    this.audioFocusActive = false;
    if (manager === undefined) return;
    try {
      if (manager.isAudioSessionActivated()) {
        await manager.deactivateAudioSession();
      }
    } catch (error) {
      Log.w(TAG, `deactivateAudioSession failed: ${error}`);
    }
    const payload: FocusPayload = { 'focused': false };
    this.notifyFlutter('audioFocusChanged', payload);
  }

  private scheduleAudioFocusRecovery(): void {
    if (this.audioFocusRetryTimer !== undefined ||
      this.audioFocusRetryCount >= AUDIO_FOCUS_RETRY_LIMIT) {
      return;
    }
    this.audioFocusRetryCount++;
    const retry = this.audioFocusRetryCount;
    const delay = retry === 1
      ? AUDIO_FOCUS_RETRY_DELAY_MS
      : retry === 2
        ? AUDIO_FOCUS_RETRY_DELAY_MS * 2
        : AUDIO_FOCUS_RETRY_DELAY_MS * 4;
    const payload: RecoveryPayload = {
      'scheduled': true,
      'attempt': retry,
      'delayMs': delay
    };
    this.notifyFlutter('audioFocusRecovery', payload);
    this.audioFocusRetryTimer = setTimeout(() => {
      this.audioFocusRetryTimer = undefined;
      if (!this.running || !this.requestedPlaying) return;
      this.enqueue(async () => {
        if (!this.running || !this.requestedPlaying) return;
        const restored = await this.activateAudioFocus();
        if (!restored) {
          this.scheduleAudioFocusRecovery();
        }
      }).catch((error: Error) => {
        Log.w(TAG, `audio focus recovery failed: ${error}`);
      });
    }, delay);
  }

  private clearAudioFocusRecovery(): void {
    if (this.audioFocusRetryTimer !== undefined) {
      clearTimeout(this.audioFocusRetryTimer);
      this.audioFocusRetryTimer = undefined;
    }
    this.audioFocusRetryCount = 0;
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
    this.requestedPlaying = false;
    this.clearAudioFocusRecovery();
    let firstError: Error | undefined = undefined;

    try {
      await this.stopBackgroundTask();
    } catch (error) {
      firstError = new Error(`${error}`);
    }

    try {
      await this.deactivateAudioFocus();
    } catch (error) {
      firstError ??= new Error(`${error}`);
    }

    const manager = this.audioSessionManager;
    this.audioSessionManager = undefined;
    if (manager !== undefined && this.audioSessionListenerBound) {
      try {
        manager.off(
          'audioSessionDeactivated',
          this.audioSessionDeactivatedListener
        );
      } catch (error) {
        firstError ??= new Error(`${error}`);
      }
    }
    this.audioSessionListenerBound = false;

    const session = this.session;
    this.session = undefined;
    if (session !== undefined) {
      try {
        await session.setAVPlaybackState({
          state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
          speed: 0
        });
      } catch (error) {
        firstError ??= new Error(`${error}`);
      }
      try {
        await session.deactivate();
      } catch (error) {
        firstError ??= new Error(`${error}`);
      }
      try {
        await session.destroy();
      } catch (error) {
        firstError ??= new Error(`${error}`);
      }
    }
    this.notifyState();
    if (firstError !== undefined) {
      throw firstError;
    }
  }

  private notifyState(): void {
    const payload: StatePayload = {
      'running': this.running,
      'focused': this.audioFocusActive,
      'requestedPlaying': this.requestedPlaying
    };
    this.notifyFlutter('stateChanged', payload);
  }

  private notifyFlutter(method: string, payload: Object | null): void {
    const channel = this.channel;
    if (channel === undefined) return;
    channel.invokeMethod(method, payload);
  }
}
