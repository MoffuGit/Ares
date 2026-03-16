import type { Pointer } from "bun:ffi";
import { resolveCoreLib, type CoreLib } from "@ares/core";
import { EventEmitter } from "events"
import { EventType, } from "@ares/core/events";
import { SchemeMap } from "./index.ts";
import { Emitter } from "./emitter.ts";
import type { Settings, Theme, WorktreeEntry, Mode, Scope, KeymapBinding, ScopedKeymaps } from "./types.ts";
import type { AppState, AppEvents, BaseApp } from "./app.ts";

type RawThemeFile = {
    name: string;
    colors: Record<string, string>;
    theme: Record<string, string> & {
        fileType?: Record<string, string>;
    };
};

const THEME_KEYS = [
    "bg", "fg", "primaryBg", "primaryFg", "mutedBg", "mutedFg",
    "scrollThumb", "scrollTrack", "border", "card", "cardFg",
    "popover", "popoverFg", "secondary", "secondaryFg",
    "accent", "accentFg", "destructive", "destructiveFg",
    "input", "ring", "chart1", "chart2", "chart3", "chart4", "chart5",
    "sidebar", "sidebarFg", "sidebarPrimary", "sidebarPrimaryFg",
    "sidebarAccent", "sidebarAccentFg", "sidebarBorder", "sidebarRing",
] as const;

function normalizeHex(hex: string): string {
    const h = hex.toLowerCase();
    if (h.length === 7) return h + "ff";
    if (h.length === 9) return h;
    return "#000000ff";
}

function resolveColor(value: string, colors: Record<string, string>): string {
    if (value.startsWith("#")) return normalizeHex(value);
    const resolved = colors[value];
    if (resolved) return normalizeHex(resolved);
    return "#000000ff";
}

const ModeMap: Record<Mode, number> = { normal: 0, insert: 1, visual: 2 };
const ScopeMap: Record<Scope, number> = { global: 0, editor: 1, command_palette: 2 };

const FALLBACK_THEME: Theme = {
    name: "fallback",
    fg: "#dcdcdcff", bg: "#1e1e1eff",
    primaryBg: "#282828ff", primaryFg: "#c8c8c8ff",
    mutedBg: "#3c3c3cff", mutedFg: "#a0a0a0ff",
    scrollThumb: "#646464ff", scrollTrack: "#323232ff",
    border: "#00ff00ff",
    card: "#1e1e1eff", cardFg: "#dcdcdcff",
    popover: "#1e1e1eff", popoverFg: "#dcdcdcff",
    secondary: "#3c3c3cff", secondaryFg: "#a0a0a0ff",
    accent: "#3c3c3cff", accentFg: "#a0a0a0ff",
    destructive: "#dc2626ff", destructiveFg: "#ffffffff",
    input: "#323232ff", ring: "#282828ff",
    chart1: "#e76f51ff", chart2: "#2a9d8fff", chart3: "#e9c46aff",
    chart4: "#a78bfaff", chart5: "#f4845fff",
    sidebar: "#3c3c3cff", sidebarFg: "#dcdcdcff",
    sidebarPrimary: "#282828ff", sidebarPrimaryFg: "#c8c8c8ff",
    sidebarAccent: "#3c3c3cff", sidebarAccentFg: "#a0a0a0ff",
    sidebarBorder: "#323232ff", sidebarRing: "#282828ff",
    fileType: {},
};

export class CoreApp extends EventEmitter implements BaseApp {
    readonly core: CoreLib;
    protected monitor: Pointer;
    protected settings: Pointer;
    protected io: Pointer;
    protected project: Pointer | null = null;

    _state: AppState = { settings: null, theme: null, filetree: null, mode: "normal", keymaps: null };
    events = new Emitter<AppEvents>;

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
        this.core.on("SettingsUpdate", this.onSettingsUpdate);
        this.core.on("ThemeUpdate", this.onThemeUpdate);
        this.core.on("FiletreeUpdate", this.onFiletreeUpdate);
        const keymaps = this.readAllKeymaps();
        this._state = { ...this._state, settings: this.readSettings(), theme: this.readTheme(), keymaps };
    }

    stop() {
        this.core.off("FiletreeUpdate", this.onFiletreeUpdate);
        this.core.off(String(EventType.SettingsUpdate), this.onSettingsUpdate);
        this.core.off(String(EventType.ThemeUpdate), this.onThemeUpdate);

        if (this.project) {
            this.core.destroyProject(this.project);
            this.project = null;
        }
        this.core.destroySettings(this.settings);
        this.core.destroyMonitor(this.monitor);
        this.core.destroyIo(this.io);
        this.core.deinitState();
    }

    protected onFiletreeUpdate = () => {
        this.readFiletree();
    };

    readFiletree() {
        if (!this.project) return;
        const raw = this.core.readFileTree(this.project);
        const entries: WorktreeEntry[] = raw.map((e) => {
            const path = e.path ?? "";
            const parts = path.split("/");
            return {
                id: Number(e.id),
                name: parts[parts.length - 1] ?? path,
                path,
                kind: e.kind === 1 ? "dir" : "file",
                fileType: e.file_type ?? "unknown",
                expanded: e.is_expanded,
                depth: e.depth,
            };
        });
        console.log("refresh filetree: count=", raw.length, "entries=", JSON.stringify(entries.slice(0, 5)));
        this._state = { ...this._state, filetree: entries };
        this.emit("filetreeUpdate");
    }

    selectEntry(id: number) {
        if (this.project) {
            this.core.selectEntry(this.project, id);
        }
    }

    setMode(mode: Mode) {
        if (this._state.mode === mode) return;
        this._state = { ...this._state, mode, keymaps: this.readAllKeymaps(mode) };
        this.emit("modeUpdate");
        this.emit("keymapsUpdate");
    }

    readKeymaps(scope: Scope): KeymapBinding[] {
        return this.core.readKeymapEntries(this.settings, ScopeMap[scope], ModeMap[this._state.mode]);
    }

    protected readAllKeymaps(mode?: Mode): ScopedKeymaps {
        const m = ModeMap[mode ?? this._state.mode];
        return {
            global: this.core.readKeymapEntries(this.settings, ScopeMap.global, m),
            editor: this.core.readKeymapEntries(this.settings, ScopeMap.editor, m),
            command_palette: this.core.readKeymapEntries(this.settings, ScopeMap.command_palette, m),
        };
    }

    protected onSettingsUpdate = () => {
        const keymaps = this.readAllKeymaps();
        this._state = { ...this._state, settings: this.readSettings(), theme: this.readTheme(), keymaps };
        this.emit("settingsUpdate");
        this.emit("themeUpdate");
        this.emit("keymapsUpdate");
    };

    protected onThemeUpdate = () => {
        this._state = { ...this._state, theme: this.readTheme() };
        this.emit("themeUpdate");
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
        try {
            const json = this.core.readThemeJson(this.settings);
            const raw: RawThemeFile = JSON.parse(json);

            const resolved: Record<string, string> = {};
            for (const key of THEME_KEYS) {
                const ref = raw.theme[key];
                resolved[key] = ref ? resolveColor(ref, raw.colors) : "#000000ff";
            }

            const fileType: Record<string, string> = {};
            if (raw.theme.fileType) {
                for (const [key, value] of Object.entries(raw.theme.fileType)) {
                    fileType[key] = resolveColor(value, raw.colors);
                }
            }

            return {
                name: raw.name ?? "unknown",
                ...resolved,
                fileType,
            } as Theme;
        } catch {
            return FALLBACK_THEME;
        }
    }
}
