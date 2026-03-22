import type { Pointer } from "bun:ffi";
import { resolveCoreLib, type CoreLib } from "@ares/core";
import { EventType, } from "@ares/core/events";
import type { Settings, Theme, WorktreeEntry, Mode, Scope, KeymapBinding, ScopedKeymaps, AppState } from "../types.ts";
import { resolveTheme } from "./theme.ts";

import { EventEmitter } from "events";

const ModeMap: Record<Mode, number> = { normal: 0, insert: 1, visual: 2 };
const ScopeMap: Record<Scope, number> = { global: 0, editor: 1, command_palette: 2 };

const MAC_TRAFFIC_LIGHTS_X = 14;
const MAC_TRAFFIC_LIGHTS_Y = 12;

export class CoreApp extends EventEmitter {
    readonly core: CoreLib;
    protected appearance: Pointer | null = null;
    protected monitor: Pointer;
    protected settings: Pointer;
    protected io: Pointer;
    protected project: Pointer | null = null;

    _state: AppState = { settings: null, theme: null, filetree: null, mode: "normal", keymaps: null };

    constructor(settingsPath: string, projectPath: string, appearance: boolean, libPath?: string,) {
        super();
        this.core = resolveCoreLib(libPath);

        const monitor = this.core.createMonitor();
        const settings = this.core.createSettings();
        const io = this.core.createIo();

        if (!monitor || !settings || !io) throw new Error("Failed to init core handles");

        this.monitor = monitor;
        this.io = io;
        this.settings = settings;
        // this.keymapHandler = new KeymapHandler(this);

        if (appearance) {
            this.appearance = this.core.createAppearance()
        }

        this.loadSettings(settingsPath, this.appearance);
        this.openProject(projectPath);
    }

    setWindowTrafficLightPosition(window: Pointer) {
        this.core.setWindowTrafficLightsPosition(
            window,
            MAC_TRAFFIC_LIGHTS_X,
            MAC_TRAFFIC_LIGHTS_Y,
        );
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

        if (this.appearance) this.core.destroyAppearance(this.appearance);

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

    expandEntry(id: number) {
        if (this.project) {
            this.core.expandEntry(this.project, id);
        }
    }

    setMode(mode: Mode) {
        if (this._state.mode === mode) return;
        this._state = { ...this._state, mode, keymaps: this.readAllKeymaps(mode) };
        this.emit("modeUpdate");
        this.emit("keymapsUpdate");
    }

    setSystemScheme(scheme: number) {
        this.core.setSystemScheme(this.settings, scheme);
    }

    readKeymaps(scope: Scope): KeymapBinding[] {
        return this.core.readKeymapEntries(this.settings, ScopeMap[scope], ModeMap[this._state.mode]);
    }

    getTrieRoot(mode: Mode): Pointer | null {
        return this.core.getTrieRoot(this.settings, ModeMap[mode]);
    }

    trieStep(node: Pointer, codepoint: number, mods: number): Pointer | null {
        return this.core.trieStep(node, codepoint, mods);
    }

    trieNodeIsTerminal(node: Pointer): boolean {
        return this.core.trieNodeIsTerminal(node);
    }

    trieNodeHasChildren(node: Pointer): boolean {
        return this.core.trieNodeHasChildren(node);
    }

    // handleKeyDown(char: string | number, mods: KeyDownMods): boolean {
    //     return this.keymapHandler.handleKeyDown(char, mods);
    // }

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
        console.log("raw system scheme", raw.system_scheme);
        return {
            scheme: raw.scheme,
            system_scheme: raw.system_scheme,
            light_theme: raw.light_theme ?? "",
            dark_theme: raw.dark_theme ?? "",
        };
    }

    protected readTheme(): Theme {
        const json = this.core.readThemeJson(this.settings);
        return resolveTheme(json);
    }
}
