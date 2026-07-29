export class PipSurfaceRegistry {
  private static controller?: XComponentController;

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
}
