import type { AresBackend } from "./backend.ts";
import type { SettingsDTO } from "./types.ts";
import { Emitter } from "./emitter.ts";

export type AresSnapshot = {
  settings: SettingsDTO | null;
  ready: boolean;
  error: string | null;
};

export type StoreEvents = {
  change: [];
};

export function createAresStore(backend: AresBackend) {
  let snapshot: AresSnapshot = { settings: null, ready: false, error: null };
  const emitter = new Emitter<StoreEvents>();
  let started = false;

  function onSettingsUpdate(settings: SettingsDTO) {
    snapshot = { settings, ready: true, error: null };
    emitter.emit("change");
  }

  async function refreshSettings() {
    try {
      const settings = await backend.getSettings();
      snapshot = { settings, ready: true, error: null };
      emitter.emit("change");
    } catch (e) {
      snapshot = {
        ...snapshot,
        ready: true,
        error: e instanceof Error ? e.message : String(e),
      };
      emitter.emit("change");
    }
  }

  function ensureStarted() {
    if (started) return;
    started = true;

    backend.start?.();
    backend.events.on("settings:update", onSettingsUpdate);
    void refreshSettings();
  }

  function destroy() {
    backend.events.off("settings:update", onSettingsUpdate);
    backend.stop?.();
    emitter.removeAll();
    started = false;
  }

  return {
    ensureStarted,
    destroy,
    getSnapshot: () => snapshot,
    subscribe: (listener: () => void) => {
      ensureStarted();
      emitter.on("change", listener);
      return () => emitter.off("change", listener);
    },
    refreshSettings,
  };
}
