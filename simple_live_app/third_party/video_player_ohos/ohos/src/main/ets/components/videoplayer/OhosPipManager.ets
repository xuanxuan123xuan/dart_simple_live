import {
  BinaryMessenger,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import PiPWindow from '@ohos.PiPWindow';
import { VideoPlayer } from './VideoPlayer';
import { PipSurfaceRegistry } from './PipSurfaceRegistry';

const TAG: string = 'OhosPipManager';
const CHANNEL_NAME: string = 'simple_live/ohos_pip';
const PIP_START_TIMEOUT_MS: number = 5000;

export class OhosPipManager implements MethodCallHandler {
  private context: common.UIAbilityContext;
  private channel?: MethodChannel;
  private controller?: PiPWindow.PiPController;
  private activePlayer?: VideoPlayer;
  private controllerPlayer?: VideoPlayer;
  private controllerSurface?: XComponentController;
  private pipActive: boolean = false;
  private pipStarting: boolean = false;
  private autoStartEnabled: boolean = false;
  private pipStartTimer: number | undefined = undefined;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  setup(binaryMessenger: BinaryMessenger): void {
    this.channel = new MethodChannel(binaryMessenger, CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  setActivePlayer(player: VideoPlayer): void {
    this.activePlayer = player;
  }

  clearPlayer(player: VideoPlayer): void {
    if (this.activePlayer === player) {
      this.activePlayer = undefined;
    }
    if (this.controllerPlayer === player) {
      this.stopAndDispose().catch((error: Error) => {
        Log.e(TAG, `Failed to stop PiP while disposing player: ${error.message}`);
      });
    }
  }

  syncPlaybackState(player: VideoPlayer): void {
    if (this.controllerPlayer !== player || this.controller === undefined) {
      return;
    }
    try {
      this.controller.updatePiPControlStatus(
        PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
        player.isPlaying() ? PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE
      );
    } catch (error) {
      Log.w(TAG, `Failed to update PiP playback state: ${error}`);
    }
  }

  detach(): void {
    this.channel?.setMethodCallHandler(null);
    this.stopAndDispose().catch((error: Error) => {
      Log.e(TAG, `Failed to stop PiP during detach: ${error.message}`);
    });
    this.channel = undefined;
    this.activePlayer = undefined;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'isAvailable':
        try {
        result.success(this.isAvailable());
        } catch (error) {
          Log.w(TAG, `PiP capability check failed: ${error}`);
          result.success(false);
        }
        return;
      case 'enter':
        this.enter(call, result);
        return;
      case 'prepareAuto':
        this.prepareAuto(call, result);
        return;
      case 'cancelAuto':
        this.cancelAuto(result);
        return;
      case 'exit':
        this.exit(result);
        return;
      default:
        result.notImplemented();
    }
  }

  private isAvailable(): boolean {
    return PiPWindow.isPiPEnabled() &&
      PipSurfaceRegistry.getController() !== undefined &&
      this.activePlayer !== undefined;
  }

  private readDimension(call: MethodCall, name: string, fallback: number): number {
    const value: number = call.argument(name);
    return value > 0 ? Math.round(value) : fallback;
  }

  private async enter(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const controller = await this.ensureController(
        this.readDimension(call, 'width', 16),
        this.readDimension(call, 'height', 9)
      );
      controller.setAutoStartEnabled(false);
      this.autoStartEnabled = false;
      if (!this.pipActive && !this.pipStarting) {
        this.pipStarting = true;
        this.schedulePiPTimeout();
        await controller.startPiP();
      }
      result.success(true);
    } catch (error) {
      this.clearPiPTimeout();
      this.restorePlayerSurface();
      this.pipStarting = false;
      result.error('pip_start_failed', `${error}`, null);
    }
  }

  private async prepareAuto(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const controller = await this.ensureController(
        this.readDimension(call, 'width', 16),
        this.readDimension(call, 'height', 9)
      );
      controller.setAutoStartEnabled(true);
      this.autoStartEnabled = true;
      result.success(true);
    } catch (error) {
      result.error('pip_auto_start_failed', `${error}`, null);
    }
  }

  private cancelAuto(result: MethodResult): void {
    try {
      this.controller?.setAutoStartEnabled(false);
      this.autoStartEnabled = false;
      if (!this.pipActive && !this.pipStarting) {
        this.disposeController();
      }
      result.success(null);
    } catch (error) {
      result.error('pip_cancel_auto_failed', `${error}`, null);
    }
  }

  private async exit(result: MethodResult): Promise<void> {
    try {
      await this.stopAndDispose();
      result.success(null);
    } catch (error) {
      result.error('pip_stop_failed', `${error}`, null);
    }
  }

  private async ensureController(width: number, height: number): Promise<PiPWindow.PiPController> {
    if (!PiPWindow.isPiPEnabled()) {
      throw new Error('Picture-in-picture is disabled on this device.');
    }
    const player = this.activePlayer;
    const surfaceController = PipSurfaceRegistry.getController();
    if (player === undefined || surfaceController === undefined) {
      throw new Error('Picture-in-picture video surface is not ready.');
    }
    if (this.controller !== undefined &&
      this.controllerPlayer === player &&
      this.controllerSurface === surfaceController) {
      this.controller.updateContentSize(width, height);
      return this.controller;
    }
    await this.stopAndDispose();
    const controller = await PiPWindow.create({
      context: this.context,
      componentController: surfaceController,
      templateType: PiPWindow.PiPTemplateType.VIDEO_LIVE,
      contentWidth: width,
      contentHeight: height,
      controlGroups: [PiPWindow.VideoLiveControlGroup.VIDEO_PLAY_PAUSE]
    });
    this.controller = controller;
    this.controllerPlayer = player;
    this.controllerSurface = surfaceController;
    controller.on('stateChange', (state: PiPWindow.PiPState, reason: string) => {
      this.onStateChange(controller, player, surfaceController, state, reason);
    });
    controller.on('controlPanelActionEvent', (event: PiPWindow.PiPActionEventType, status?: number) => {
      if (event !== 'playbackStateChanged') {
        return;
      }
      if (status === PiPWindow.PiPControlStatus.PLAY) {
        player.play();
      } else {
        player.pause();
      }
      this.syncPlaybackState(player);
    });
    this.syncPlaybackState(player);
    return controller;
  }

  private onStateChange(
    controller: PiPWindow.PiPController,
    player: VideoPlayer,
    surfaceController: XComponentController,
    state: PiPWindow.PiPState,
    reason: string
  ): void {
    Log.i(TAG, `PiP state=${state}, reason=${reason}`);
    if (state === PiPWindow.PiPState.ABOUT_TO_START) {
      player.useOutputSurface(surfaceController.getXComponentSurfaceId());
      this.pipStarting = true;
      return;
    }
    if (state === PiPWindow.PiPState.STARTED) {
      this.clearPiPTimeout();
      this.pipStarting = false;
      this.pipActive = true;
      this.channel?.invokeMethod('stateChanged', { 'enabled': true });
      return;
    }
    if (state === PiPWindow.PiPState.STOPPED || state === PiPWindow.PiPState.ERROR) {
      this.clearPiPTimeout();
      this.restorePlayerSurface();
      this.pipStarting = false;
      this.pipActive = false;
      this.autoStartEnabled = false;
      this.channel?.invokeMethod('stateChanged', { 'enabled': false });
      if (this.controller === controller) {
        this.disposeController();
      }
    }
  }

  private restorePlayerSurface(): void {
    try {
      this.controllerPlayer?.restoreOutputSurface();
    } catch (error) {
      Log.w(TAG, `Failed to restore Flutter video surface: ${error}`);
    }
  }

  private async stopAndDispose(): Promise<void> {
    const controller = this.controller;
    if (controller === undefined) {
      return;
    }
    try {
      controller.setAutoStartEnabled(false);
      if (this.pipActive || this.pipStarting) {
        await controller.stopPiP();
      }
    } finally {
      this.clearPiPTimeout();
      this.restorePlayerSurface();
      this.pipActive = false;
      this.pipStarting = false;
      this.autoStartEnabled = false;
      if (this.controller === controller) {
        this.disposeController();
      }
      this.channel?.invokeMethod('stateChanged', { 'enabled': false });
    }
  }

  private disposeController(): void {
    this.controller?.off('stateChange');
    this.controller?.off('controlPanelActionEvent');
    this.controller = undefined;
    this.controllerPlayer = undefined;
    this.controllerSurface = undefined;
  }

  private schedulePiPTimeout(): void {
    this.clearPiPTimeout();
    this.pipStartTimer = setTimeout(() => {
      this.pipStartTimer = undefined;
      if (this.pipStarting) {
        Log.w(TAG, 'PiP STARTED event was not received within timeout, resetting pipStarting to allow retry');
        this.pipStarting = false;
      }
    }, PIP_START_TIMEOUT_MS);
  }

  private clearPiPTimeout(): void {
    if (this.pipStartTimer !== undefined) {
      clearTimeout(this.pipStartTimer);
      this.pipStartTimer = undefined;
    }
  }
}
