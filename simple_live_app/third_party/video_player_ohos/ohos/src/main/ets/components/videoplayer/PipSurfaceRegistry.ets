export interface PipPlaybackTarget {
  play(): void;
  pause(): void;
  isPlaying(): boolean;
  useOutputSurface(surfaceId: string): void;
  restoreOutputSurface(): void;
}

export class PipSurfaceRegistry {
  private static controller?: XComponentController;
  private static playbackTarget?: PipPlaybackTarget;

  static register(controller: XComponentController): void {
    PipSurfaceRegistry.controller = controller;
  }

  static unregister(controller: XComponentController): void {
    if (PipSurfaceRegistry.controller === controller) {
      PipSurfaceRegistry.controller = undefined;
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
  }

  static getPlaybackTarget(): PipPlaybackTarget | undefined {
    return PipSurfaceRegistry.playbackTarget;
  }
}
