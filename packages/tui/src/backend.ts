import { resolveCoreLib } from "@ares/core";
import { EventType } from "@ares/core/events";
import { Emitter, type AresBackend, type BackendEvents, type ColorScheme, type SettingsDTO } from "@ares/shared";
import type { Pointer } from "bun:ffi";

const SCHEME_MAP: Record<number, ColorScheme> = {
    0: "light",
    1: "dark",
    2: "system",
};

export function createTuiBackend(settingsPath: string): AresBackend {
    const core = resolveCoreLib();
    const events = new Emitter<BackendEvents>();

    const monitor = core.createMonitor();
    const settings = core.createSettings();
    if (!monitor || !settings) throw new Error("Failed to init core handles");

    core.loadSettings(settings, settingsPath, monitor);

    let drainTimer: ReturnType<typeof setInterval> | null = null;

    function readSettingsDTO(): SettingsDTO {
        const raw = core.readSettings(settings as Pointer);
        return {
            scheme: SCHEME_MAP[Number(raw.scheme)] ?? "system",
            light_theme: raw.light_theme ?? "",
            dark_theme: raw.dark_theme ?? "",
        };
    }

    function onSettingsUpdate() {
        events.emit("settings:update", readSettingsDTO());
    }

    return {
        events,

        async getSettings() {
            return readSettingsDTO();
        },

        start() {
            drainTimer = setInterval(() => core.drainEvents(), 16);
            core.events.on(String(EventType.SettingsUpdate), onSettingsUpdate);
        },

        stop() {
            core.events.off(String(EventType.SettingsUpdate), onSettingsUpdate);
            if (drainTimer) {
                clearInterval(drainTimer);
                drainTimer = null;
            }
            core.destroySettings(settings as Pointer);
            core.destroyMonitor(monitor as Pointer);
        },
    };
}
