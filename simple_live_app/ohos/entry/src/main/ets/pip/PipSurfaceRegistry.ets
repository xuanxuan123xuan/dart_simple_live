// Picture-in-picture surface registry for the libmpv player.
//
// HarmonyOS PiP needs two pieces to hand a small window to PiPWindow.create():
//   1. an XComponentController for the dedicated PiP output surface (owned by
//      the page's Index.ets and registered here via register());
//   2. the playback target that will be switched onto that surface when PiP
//      starts and back off when it ends (the OhosMpvPlugin).
//
// This is a single-target registry: the app now has exactly one player backend
// (libmpv), so the AVPlayer-era slot that could be overwritten by the platform
// video_player is gone.
export interface PipPlaybackTarget {
  play(): void;
  pause(): void;
  isPlaying(): boolean;
  // width/height are the dimensions reported by the PiP XComponent. They
  // are optional to keep existing playback targets source-compatible while
  // the registry rolls this information into the surface hand-off.
  useOutputSurface(surfaceId: string, width?: number, height?: number): void;
  restoreOutputSurface(): void;
}

export interface PipSurfaceSnapshot {
  surfaceId: string;
  width: number;
  height: number;
  revision: number;
}

export class PipSurfaceRegistry {
  private static controller?: XComponentController;
  private static playbackTarget?: PipPlaybackTarget;
  private static pipPlaybackTarget?: PipPlaybackTarget;
  private static surfaceSnapshot?: PipSurfaceSnapshot;
  private static contentWidth: number = 0;
  private static contentHeight: number = 0;
  private static revision: number = 0;

  static register(controller: XComponentController): void {
    if (PipSurfaceRegistry.controller !== undefined &&
      PipSurfaceRegistry.controller !== controller) {
      // A new XComponent owns a new surface. Do not let a stale surface id
      // from a previous Flutter page satisfy a PiP request.
      PipSurfaceRegistry.surfaceSnapshot = undefined;
      PipSurfaceRegistry.contentWidth = 0;
      PipSurfaceRegistry.contentHeight = 0;
      PipSurfaceRegistry.revision++;
    }
    PipSurfaceRegistry.controller = controller;
  }

  static unregister(controller: XComponentController): void {
    if (PipSurfaceRegistry.controller === controller) {
      PipSurfaceRegistry.controller = undefined;
      PipSurfaceRegistry.surfaceSnapshot = undefined;
      PipSurfaceRegistry.revision++;
      if (PipSurfaceRegistry.pipPlaybackTarget !== undefined) {
        PipSurfaceRegistry.pipPlaybackTarget = undefined;
      }
    }
  }

  static getController(): XComponentController | undefined {
    return PipSurfaceRegistry.controller;
  }

  static registerPlaybackTarget(target: PipPlaybackTarget): void {
    if (PipSurfaceRegistry.playbackTarget !== target &&
      PipSurfaceRegistry.pipPlaybackTarget !== undefined) {
      PipSurfaceRegistry.pipPlaybackTarget = undefined;
    }
    PipSurfaceRegistry.playbackTarget = target;
  }

  static unregisterPlaybackTarget(target: PipPlaybackTarget): void {
    if (PipSurfaceRegistry.playbackTarget === target) {
      PipSurfaceRegistry.playbackTarget = undefined;
    }
    if (PipSurfaceRegistry.pipPlaybackTarget === target) {
      PipSurfaceRegistry.pipPlaybackTarget = undefined;
      PipSurfaceRegistry.contentWidth = 0;
      PipSurfaceRegistry.contentHeight = 0;
    }
  }

  static getPlaybackTarget(): PipPlaybackTarget | undefined {
    return PipSurfaceRegistry.playbackTarget;
  }

  static getSurfaceSnapshot(): PipSurfaceSnapshot | undefined {
    const snapshot = PipSurfaceRegistry.surfaceSnapshot;
    if (snapshot === undefined) {
      return undefined;
    }
    // Return a copy so callers cannot mutate the registry's readiness state.
    return {
      surfaceId: snapshot.surfaceId,
      width: snapshot.width,
      height: snapshot.height,
      revision: snapshot.revision
    };
  }

  static activatePipPlaybackTarget(
    target: PipPlaybackTarget,
    surfaceId: string,
    width: number,
    height: number
  ): void {
    PipSurfaceRegistry.pipPlaybackTarget = target;
    PipSurfaceRegistry.contentWidth = Math.round(width);
    PipSurfaceRegistry.contentHeight = Math.round(height);
    const normalizedId = surfaceId.trim();
    const normalizedWidth = Math.round(width);
    const normalizedHeight = Math.round(height);
    const existing = PipSurfaceRegistry.surfaceSnapshot;
    if (existing !== undefined &&
      existing.surfaceId === normalizedId &&
      existing.width === normalizedWidth &&
      existing.height === normalizedHeight) {
      // updateSurface() deliberately de-duplicates unchanged callbacks. An
      // activation still needs one explicit hand-off when the snapshot was
      // recorded before the target became active.
      try {
        target.useOutputSurface(
          existing.surfaceId,
        PipSurfaceRegistry.contentWidth,
        PipSurfaceRegistry.contentHeight
        );
      } catch (_error) {
      }
      return;
    }
    PipSurfaceRegistry.updateSurface(surfaceId, width, height);
  }

  static deactivatePipPlaybackTarget(target: PipPlaybackTarget): void {
    if (PipSurfaceRegistry.pipPlaybackTarget === target) {
      PipSurfaceRegistry.pipPlaybackTarget = undefined;
    }
  }

  /**
   * Records the currently usable XComponent surface.
   *
   * Index.ets receives this callback whenever the PiP surface is created or
   * resized. While PiP is active, a surface replacement must be forwarded to
   * mpv immediately so the window does not keep rendering into a dead
   * buffer. Before PiP starts, the snapshot is only readiness metadata and
   * does not move playback.
   */
  static updateSurface(surfaceId: string, width: number, height: number): void {
    if (!Number.isFinite(width) || !Number.isFinite(height)) {
      return;
    }
    const normalizedId = surfaceId.trim();
    if (normalizedId.length === 0 || width <= 0 || height <= 0) {
      return;
    }
    const normalizedWidth = Math.round(width);
    const normalizedHeight = Math.round(height);
    if (normalizedWidth <= 0 || normalizedHeight <= 0) {
      return;
    }

    const previous = PipSurfaceRegistry.surfaceSnapshot;
    if (previous !== undefined &&
      previous.surfaceId === normalizedId &&
      previous.width === normalizedWidth &&
      previous.height === normalizedHeight) {
      return;
    }

    PipSurfaceRegistry.revision++;
    const snapshot: PipSurfaceSnapshot = {
      surfaceId: normalizedId,
      width: normalizedWidth,
      height: normalizedHeight,
      revision: PipSurfaceRegistry.revision
    };
    PipSurfaceRegistry.surfaceSnapshot = snapshot;

    const activeTarget = PipSurfaceRegistry.pipPlaybackTarget;
    if (activeTarget === undefined) {
      return;
    }
    try {
      activeTarget.useOutputSurface(
        snapshot.surfaceId,
        PipSurfaceRegistry.contentWidth > 0 ? PipSurfaceRegistry.contentWidth : snapshot.width,
        PipSurfaceRegistry.contentHeight > 0 ? PipSurfaceRegistry.contentHeight : snapshot.height
      );
    } catch (_error) {
      // The PiP manager will restore/retry through its normal lifecycle. A
      // surface callback must never throw into the ArkUI event dispatcher.
    }
  }
}
