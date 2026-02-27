import type { Emitter } from "./emitter.ts";
import type { SettingsDTO } from "./types.ts";

export type BackendEvents = {
  "settings:update": [settings: SettingsDTO];
};

export interface AresBackend {
  events: Emitter<BackendEvents>;
  getSettings(): Promise<SettingsDTO>;
  start?(): void;
  stop?(): void;
}
