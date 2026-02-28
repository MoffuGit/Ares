import { resolveCoreLib, type CoreLib } from "@ares/core";
import { EventType } from "@ares/core/events";
import { Emitter, type App, type AppEvents, type AppState, type ColorScheme, type Settings, type Theme } from "@ares/shared";
import type { Pointer } from "bun:ffi";

const SCHEME_MAP: Record<number, ColorScheme> = {
    0: "light",
    1: "dark",
    2: "system",
};

export class TuiApp implements App {
    readonly events = new Emitter<AppEvents>();

    private core: CoreLib;
    private monitor: Pointer;
    private settings: Pointer;
    private drainTimer: ReturnType<typeof setInterval> | null = null;

    private _state: AppState = { settings: null, theme: null };

    get state(): AppState {
        return this._state;
    }

    constructor(settingsPath: string) {
        this.core = resolveCoreLib();

        const monitor = this.core.createMonitor();
        const settings = this.core.createSettings();
        if (!monitor || !settings) throw new Error("Failed to init core handles");

        this.monitor = monitor;
        this.settings = settings;
        this.core.loadSettings(this.settings, settingsPath, this.monitor);
    }

    start() {
        this._state = { ...this._state, settings: this.readSettings(), theme: this.readTheme() };
        this.drainTimer = setInterval(() => this.core.drainEvents(), 16);
        this.core.events.on(String(EventType.SettingsUpdate), this.onSettingsUpdate);
        this.core.events.on(String(EventType.ThemeUpdate), this.onThemeUpdate);
    }

    stop() {
        this.core.events.off(String(EventType.SettingsUpdate), this.onSettingsUpdate);
        this.core.events.off(String(EventType.ThemeUpdate), this.onThemeUpdate);
        if (this.drainTimer) {
            clearInterval(this.drainTimer);
            this.drainTimer = null;
        }
        this.core.destroySettings(this.settings);
        this.core.destroyMonitor(this.monitor);
        this.core.deinitState();
    }

    private onSettingsUpdate = () => {
        this._state = { ...this._state, settings: this.readSettings() };
        this._state = { ...this._state, theme: this.readTheme() };
        this.events.emit("settingsUpdate");
        this.events.emit("themeUpdate");
    };

    private onThemeUpdate = () => {
        this._state = { ...this._state, theme: this.readTheme() };
        this.events.emit("themeUpdate");
    };

    private readSettings(): Settings {
        const raw = this.core.readSettings(this.settings);
        return {
            scheme: SCHEME_MAP[Number(raw.scheme)] ?? "system",
            light_theme: raw.light_theme ?? "",
            dark_theme: raw.dark_theme ?? "",
        };
    }

    private readTheme(): Theme {
        const raw = this.core.readTheme(this.settings);
        const toRgba = (v: number): number[] => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
        return {
            name: raw.name ?? "",
            fg: toRgba(raw.fg),
            bg: toRgba(raw.bg),
            primaryBg: toRgba(raw.primaryBg),
            primaryFg: toRgba(raw.primaryFg),
            mutedBg: toRgba(raw.mutedBg),
            mutedFg: toRgba(raw.mutedFg),
            scrollThumb: toRgba(raw.scrollThumb),
            scrollTrack: toRgba(raw.scrollTrack),
            border: toRgba(raw.border),
        };
    }
}
