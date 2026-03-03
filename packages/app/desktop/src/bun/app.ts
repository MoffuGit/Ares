import { resolveCoreLib, type CoreLib } from "@ares/core";
import { EventType } from "@ares/core/events";
import { Emitter, type App, type AppEvents, type AppState, type ColorScheme, type Settings, type Theme, type WorktreeEntry } from "@ares/shared";
import type { Pointer } from "bun:ffi";

const SCHEME_MAP: Record<number, ColorScheme> = {
    0: "light",
    1: "dark",
    2: "system",
};

const FILE_TYPE_MAP: string[] = [
    "zig", "c", "cpp", "h", "py", "js", "ts", "json", "xml", "yaml",
    "toml", "md", "txt", "html", "css", "sh", "go", "rs", "java", "rb",
    "lua", "makefile", "dockerfile", "gitignore", "license", "unknown",
];

export class DesktopApp implements App {
    readonly events = new Emitter<AppEvents>();

    private core: CoreLib;
    private monitor: Pointer;
    private io: Pointer;
    private settings: Pointer;
    private project: Pointer | null = null;

    _state: AppState = { settings: null, theme: null, worktree: [] };

    get state(): AppState {
        return this._state;
    }

    constructor(settingsPath: string, private projectPath: string, libPath?: string) {
        this.core = resolveCoreLib(libPath);

        const monitor = this.core.createMonitor();
        const io = this.core.createIo();
        const settings = this.core.createSettings();
        if (!monitor || !io || !settings) throw new Error("Failed to init core handles");

        this.monitor = monitor;
        this.io = io;
        this.settings = settings;
        console.log("setting path:", settingsPath);
        this.core.loadSettings(this.settings, settingsPath, this.monitor);
    }

    start() {
        this._state = { ...this._state, settings: this.readSettings(), theme: this.readTheme() };
        this.core.events.on(String(EventType.SettingsUpdate), this.onSettingsUpdate);
        this.core.events.on(String(EventType.ThemeUpdate), this.onThemeUpdate);
        this.core.events.on(String(EventType.WorktreeUpdate), this.onWorktreeUpdate);

        this.openProject(this.projectPath);
        this.refreshWorktree();
    }

    stop() {
        this.core.events.off(String(EventType.SettingsUpdate), this.onSettingsUpdate);
        this.core.events.off(String(EventType.ThemeUpdate), this.onThemeUpdate);
        this.core.events.off(String(EventType.WorktreeUpdate), this.onWorktreeUpdate);
        if (this.project) {
            this.core.destroyProject(this.project);
            this.project = null;
        }
        this.core.destroySettings(this.settings);
        this.core.destroyIo(this.io);
        this.core.destroyMonitor(this.monitor);
        this.core.deinitState();
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
                fileType: FILE_TYPE_MAP[e.file_type] ?? "unknown",
                depth: e.depth,
            };
        });
        console.log("refreshWorktree: count=", raw.length, "entries=", JSON.stringify(entries.slice(0, 5)));
        this._state = { ...this._state, worktree: entries };
        this.events.emit("worktreeUpdate");
    }

    private onSettingsUpdate = () => {
        const settings = this.readSettings();
        const theme = this.readTheme();

        this._state = { ...this._state, settings, theme };
        this.events.emit("settingsUpdate");
        this.events.emit("themeUpdate");
    };

    private onThemeUpdate = () => {
        const theme = this.readTheme();
        this._state = { ...this._state, theme };
        this.events.emit("themeUpdate");
    };

    private onWorktreeUpdate = () => {
        this.refreshWorktree();
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
