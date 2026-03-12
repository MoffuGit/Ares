import { BaseApp, SchemeMap, type Settings, type Theme, type WorktreeEntry, FileType } from "@ares/shared";
import type { Pointer } from "bun:ffi";
import { EventType } from "./events";
import { resolveCoreLib, type CoreLib } from "./index";

const toRgba = (v: number): number[] => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

export class CoreApp extends BaseApp {
    protected core: CoreLib;
    protected monitor: Pointer;
    protected settings: Pointer;
    protected io: Pointer;
    protected project: Pointer | null = null;

    constructor(libPath?: string) {
        super();

        this.core = resolveCoreLib(libPath);

        const monitor = this.core.createMonitor();
        const settings = this.core.createSettings();
        const io = this.core.createIo();

        if (!monitor || !settings || !io) throw new Error("Failed to init core handles");

        this.monitor = monitor;
        this.io = io;
        this.settings = settings;
    }

    drainMailbox() {
        this.core.drainMailbox();
    }

    loadSettings(settingsPath: string, appearance: Pointer | null) {
        this.core.loadSettings(this.settings, settingsPath, this.monitor, appearance);
    }

    openProject(path: string) {
        if (this.project) {
            this.core.destroyProject(this.project);
        }
        this.project = this.core.createProject(this.monitor, this.io, path);

        if (!this.project) {
            console.error("Failed to create project for path:", path);
            return;
        }
    }

    start() {
        this.core.events.on("SettingsUpdate", this.onSettingsUpdate);
        this.core.events.on("ThemeUpdate", this.onThemeUpdate);
        this.core.events.on("WorktreeUpdate", this.onWorktreeUpdate);
        this._state = { ...this._state, settings: this.readSettings(), theme: this.readTheme() };
    }

    stop() {
        this.core.events.off(String(EventType.WorktreeUpdate), this.onWorktreeUpdate);
        this.core.events.off(String(EventType.SettingsUpdate), this.onSettingsUpdate);
        this.core.events.off(String(EventType.ThemeUpdate), this.onThemeUpdate);
        this.core.destroySettings(this.settings);
        this.core.destroyMonitor(this.monitor);
        this.core.destroyIo(this.io);
        if (this.project) {
            this.core.destroyProject(this.project);
            this.project = null;
        }
        this.core.deinitState();
    }

    protected onWorktreeUpdate = () => {
        this.refreshWorktree();
    };

    refreshWorktree() {
        if (!this.project) return;
        const raw = this.core.readWorktreeEntries(this.project);
        const entries: WorktreeEntry[] = raw.map((e) => {
            const path = e.path ?? "";
            const parts = path.split("/");
            return {
                id: Number(e.id),
                name: parts[parts.length - 1] ?? path,
                path,
                kind: e.kind === 1 ? "dir" : "file",
                fileType: FileType[e.file_type] ?? "unknown",
                depth: e.depth,
            };
        });
        console.log("refreshWorktree: count=", raw.length, "entries=", JSON.stringify(entries.slice(0, 5)));
        this._state = { ...this._state, worktree: entries };
        this.events.emit("worktreeUpdate");
    }

    protected onSettingsUpdate = () => {
        this._state = { ...this._state, settings: this.readSettings(), theme: this.readTheme() };
        this.events.emit("settingsUpdate");
        this.events.emit("themeUpdate");
    };

    protected onThemeUpdate = () => {
        this._state = { ...this._state, theme: this.readTheme() };
        this.events.emit("themeUpdate");
    };

    protected readSettings(): Settings {
        const raw = this.core.readSettings(this.settings);
        return {
            scheme: SchemeMap[Number(raw.scheme)] ?? "system",
            light_theme: raw.light_theme ?? "",
            dark_theme: raw.dark_theme ?? "",
        };
    }

    protected readTheme(): Theme {
        const raw = this.core.readTheme(this.settings);
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
            card: toRgba(raw.card),
            cardFg: toRgba(raw.cardFg),
            popover: toRgba(raw.popover),
            popoverFg: toRgba(raw.popoverFg),
            secondary: toRgba(raw.secondary),
            secondaryFg: toRgba(raw.secondaryFg),
            accent: toRgba(raw.accent),
            accentFg: toRgba(raw.accentFg),
            destructive: toRgba(raw.destructive),
            destructiveFg: toRgba(raw.destructiveFg),
            input: toRgba(raw.input),
            ring: toRgba(raw.ring),
            chart1: toRgba(raw.chart1),
            chart2: toRgba(raw.chart2),
            chart3: toRgba(raw.chart3),
            chart4: toRgba(raw.chart4),
            chart5: toRgba(raw.chart5),
            sidebar: toRgba(raw.sidebar),
            sidebarFg: toRgba(raw.sidebarFg),
            sidebarPrimary: toRgba(raw.sidebarPrimary),
            sidebarPrimaryFg: toRgba(raw.sidebarPrimaryFg),
            sidebarAccent: toRgba(raw.sidebarAccent),
            sidebarAccentFg: toRgba(raw.sidebarAccentFg),
            sidebarBorder: toRgba(raw.sidebarBorder),
            sidebarRing: toRgba(raw.sidebarRing),
        };
    }
}
