export interface PipPlaybackTarget {
  play(): void;
  pause(): void;
  isPlaying(): boolean;
  useOutputSurface(surfaceId: string, width: number, height: number): void;
  restoreOutputSurface(): void;
}

export class PipSurfaceRegistry {
  private static controller?: XComponentController;
  private static playbackTarget?: PipPlaybackTarget;
  private static pipPlaybackTarget?: PipPlaybackTarget;
  private static surfaceId: string = '';
  private static surfaceWidth: number = 0;
  private static surfaceHeight: number = 0;

  static register(controller: XComponentController): void {
    PipSurfaceRegistry.controller = controller;
  }

  static unregister(controller: XComponentController): void {
    if (PipSurfaceRegistry.controller === controller) {
      PipSurfaceRegistry.controller = undefined;
      PipSurfaceRegistry.surfaceId = '';
      PipSurfaceRegistry.surfaceWidth = 0;
      PipSurfaceRegistry.surfaceHeight = 0;
    }
  }

  static getController(): XComponentController | undefined {
    return PipSurfaceRegistry.controller;
  }

  static registerPlaybackTarget(target: PipPlaybackTarget): void {
    PipSurfaceRegistry.playbackTarget = target;
  }

  static unregisterPlaybackTarget(target: PipPlaybackTarget): void {
    if (PipSurfaceRegistry.playbackTarget === target) {
      PipSurfaceRegistry.playbackTarget = undefined;
    }
    if (PipSurfaceRegistry.pipPlaybackTarget === target) {
      PipSurfaceRegistry.pipPlaybackTarget = undefined;
    }
  }

  static getPlaybackTarget(): PipPlaybackTarget | undefined {
    return PipSurfaceRegistry.playbackTarget;
  }

  static activatePipPlaybackTarget(
    target: PipPlaybackTarget,
    surfaceId: string,
    width: number,
    height: number
  ): void {
    PipSurfaceRegistry.pipPlaybackTarget = target;
    PipSurfaceRegistry.updateSurface(surfaceId, width, height);
  }

  static deactivatePipPlaybackTarget(target: PipPlaybackTarget): void {
    if (PipSurfaceRegistry.pipPlaybackTarget === target) {
      PipSurfaceRegistry.pipPlaybackTarget = undefined;
    }
  }

  static updateSurface(surfaceId: string, width: number, height: number): void {
    if (surfaceId.length === 0 || width <= 0 || height <= 0) {
      return;
    }
    PipSurfaceRegistry.surfaceId = surfaceId;
    PipSurfaceRegistry.surfaceWidth = Math.round(width);
    PipSurfaceRegistry.surfaceHeight = Math.round(height);
    PipSurfaceRegistry.pipPlaybackTarget?.useOutputSurface(
      PipSurfaceRegistry.surfaceId,
      PipSurfaceRegistry.surfaceWidth,
      PipSurfaceRegistry.surfaceHeight
    );
  }
}
