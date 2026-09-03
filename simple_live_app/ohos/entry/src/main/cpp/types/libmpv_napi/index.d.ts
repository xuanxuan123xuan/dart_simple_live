export interface MpvEvent {
  kind: string;
  name: string;
  value: string;
  text: string;
  gen: number;
}

export const setEventCallback: (callback: (event: MpvEvent) => void) => void;
export const init: (surfaceId: string, width: number, height: number) => void;
export const loadFile: (url: string, headers: string, generation: number) => void;
export const setPropertyString: (name: string, value: string) => void;
export const getPropertyString: (name: string) => string;
export const commandString: (cmd: string) => void;
export const setGeometry: (width: number, height: number) => void;
export const destroy: () => void;
