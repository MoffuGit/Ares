import type { Pointer } from "bun:ffi";
import { resolveCoreLib, type CoreLib } from "@ares/core";
import type { Settings, Theme, Mode, Scope, KeymapBinding, ScopedKeymaps, AppState } from "../types.ts";
import { resolveTheme } from "./theme.ts";

import { EventEmitter } from "events";
import { Project } from "../project/index.ts";

const ModeMap: Record<Mode, number> = { normal: 0, insert: 1, visual: 2 };
const ScopeMap: Record<Scope, number> = { global: 0, editor: 1, command_palette: 2 };

const MAC_TRAFFIC_LIGHTS_X = 14;
const MAC_TRAFFIC_LIGHTS_Y = 12;

export class App extends EventEmitter {
    readonly core: CoreLib;
    protected coreApp: Pointer;
    protected project: Project | null = null;

    _state: AppState = { settings: null, theme: null, filetree: null, mode: "normal", keymaps: null };

    constructor(settingsPath: string, libPath?: string,) {
        super();
        this.core = resolveCoreLib(libPath);

        const coreApp = this.core.createApp();

        if (!coreApp) throw new Error("Failed to init App");

        this.coreApp = coreApp;

        this.loadSettings(settingsPath);
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

    loadSettings(settingsPath: string) {
        this.core.loadSettings(this.coreApp, settingsPath);
    }

    openProject(path: string) {
        if (this.project) {
            this.project.destroy();
        }
        this.project = new Project(this.core, this.coreApp, path);
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
        this.core.off("SettingsUpdate", this.onSettingsUpdate);
        this.core.off("ThemeUpdate", this.onThemeUpdate);

        if (this.project) {
            this.project.destroy();
            this.project = null;
        }
        this.core.destroyApp(this.coreApp);
        this.core.deinitState();
    }

    protected onFiletreeUpdate = () => {
        this.readFiletree();
    };

    readFiletree() {
        if (!this.project) return;
        const entries = this.project.readFiletree();
        this._state = { ...this._state, filetree: entries };
        this.emit("filetreeUpdate");
    }

    expandEntry(id: number) {
        if (this.project) {
            this.project.expandEntry(id);
        }
    }

    setMode(mode: Mode) {
        if (this._state.mode === mode) return;
        this._state = { ...this._state, mode, keymaps: this.readAllKeymaps(mode) };
        this.emit("modeUpdate");
        this.emit("keymapsUpdate");
    }

    setSystemScheme(scheme: number) {
        this.core.setSystemScheme(this.coreApp, scheme);
    }

    readKeymaps(scope: Scope): KeymapBinding[] {
        return this.core.readKeymapEntries(this.coreApp, ScopeMap[scope], ModeMap[this._state.mode]);
    }

    getTrieRoot(mode: Mode): Pointer | null {
        return this.core.getTrieRoot(this.coreApp, ModeMap[mode]);
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

    protected readAllKeymaps(mode?: Mode): ScopedKeymaps {
        const m = ModeMap[mode ?? this._state.mode];
        return {
            global: this.core.readKeymapEntries(this.coreApp, ScopeMap.global, m),
            editor: this.core.readKeymapEntries(this.coreApp, ScopeMap.editor, m),
            command_palette: this.core.readKeymapEntries(this.coreApp, ScopeMap.command_palette, m),
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
        const raw = this.core.readSettings(this.coreApp);
        console.log("raw system scheme", raw.system_scheme);
        return {
            scheme: raw.scheme,
            system_scheme: raw.system_scheme,
            light_theme: raw.light_theme ?? "",
            dark_theme: raw.dark_theme ?? "",
        };
    }

    protected readTheme(): Theme {
        const json = this.core.readThemeJson(this.coreApp);
        return resolveTheme(json);
    }
}
