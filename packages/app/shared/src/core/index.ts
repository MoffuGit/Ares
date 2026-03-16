import type { Pointer } from "bun:ffi";
import { resolveCoreLib, type CoreLib } from "@ares/core";
import { EventType, } from "@ares/core/events";
import { SchemeMap } from "../index.ts";
import { Emitter } from "../emitter.ts";
import type { Settings, Theme, WorktreeEntry, Mode, Scope, KeymapBinding, ScopedKeymaps } from "../types.ts";
import type { AppState, AppEvents, BaseApp } from "../app.ts";
import { resolveTheme } from "./theme.ts";
import { KeymapHandler } from "./keymap-handler.ts";

const ModeMap: Record<Mode, number> = { normal: 0, insert: 1, visual: 2 };
const ScopeMap: Record<Scope, number> = { global: 0, editor: 1, command_palette: 2 };


export class CoreApp implements BaseApp {
    readonly core: CoreLib;
    protected monitor: Pointer;
    protected settings: Pointer;
    protected io: Pointer;
    protected project: Pointer | null = null;
    protected keymapHandler: KeymapHandler;

    _state: AppState = { settings: null, theme: null, filetree: null, mode: "normal", keymaps: null };
    events = new Emitter<AppEvents>;

    constructor(libPath?: string) {
        this.core = resolveCoreLib(libPath);

        const monitor = this.core.createMonitor();
        const settings = this.core.createSettings();
        const io = this.core.createIo();

        if (!monitor || !settings || !io) throw new Error("Failed to init core handles");

        this.monitor = monitor;
        this.io = io;
        this.settings = settings;
        this.keymapHandler = new KeymapHandler(this);
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
        this.events.emit("filetreeUpdate");
    }

    selectEntry(id: number) {
        if (this.project) {
            this.core.selectEntry(this.project, id);
        }
    }

    setMode(mode: Mode) {
        if (this._state.mode === mode) return;
        this._state = { ...this._state, mode, keymaps: this.readAllKeymaps(mode) };
        this.events.emit("modeUpdate");
        this.events.emit("keymapsUpdate");
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
        this.events.emit("settingsUpdate");
        this.events.emit("themeUpdate");
        this.events.emit("keymapsUpdate");
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
        const json = this.core.readThemeJson(this.settings);
        return resolveTheme(json);
    }
}
