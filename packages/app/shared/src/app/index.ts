import type { Pointer } from "bun:ffi";
import { resolveCoreLib, type CoreLib } from "@ares/core";
import type { Settings, Theme, Mode, Scope, KeymapBinding, ScopedKeymaps, AppState, WorktreeEntry, BufferState } from "../types.ts";
import { resolveTheme } from "./theme.ts";

import { EventEmitter } from "events";

const ModeMap: Record<Mode, number> = { normal: 0, insert: 1, visual: 2 };
const ScopeMap: Record<Scope, number> = { global: 0, editor: 1, command_palette: 2 };

const MAC_TRAFFIC_LIGHTS_X = 12;
const MAC_TRAFFIC_LIGHTS_Y = 10;

export class App extends EventEmitter {
    readonly core: CoreLib;
    protected coreApp: Pointer;
    protected project: Pointer | null = null;
    private editors = new Set<Pointer>();

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
        this.destroyProject()
        const project = this.core.createProject(this.coreApp, path);
        if (project == null) throw new Error("Failed to create project")
        this.project = project;
    }

    destroyProject() {
        if (this.project) {
            this.core.destroyProject(this.project);
            this.project = null;
        }
    }

    start() {
        this.core.on("SettingsUpdate", this.onSettingsUpdate);
        this.core.on("ThemeUpdate", this.onThemeUpdate);
        this.core.on("FiletreeUpdate", this.onFiletreeUpdate);
        this.core.on("BufferUpdate", this.onBufferUpdate);
        const keymaps = this.readAllKeymaps();
        this._state = { ...this._state, settings: this.readSettings(), theme: this.readTheme(), keymaps };
    }

    stop() {
        this.core.off("BufferUpdate", this.onBufferUpdate);
        this.core.off("FiletreeUpdate", this.onFiletreeUpdate);
        this.core.off("SettingsUpdate", this.onSettingsUpdate);
        this.core.off("ThemeUpdate", this.onThemeUpdate);

        this.destroyProject();
        this.core.destroyApp(this.coreApp);
        this.core.deinitState();
    }

    protected onBufferUpdate = () => {
        this.emit("bufferUpdate");
    };

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

    createEditor(metalLayerPtr: Pointer): Pointer | null {
        if (!this.project) return null;
        const ptr = this.core.createEditor(this.project, metalLayerPtr);
        if (ptr) this.editors.add(ptr);
        return ptr;
    }

    resizeEditor(editor: Pointer, width: number, height: number) {
        this.core.resizeEditor(editor, width, height);
    }

    selectEditorEntry(editor: Pointer, id: number) {
        this.core.selectEditorEntry(editor, id);
    }

    editorScrollTo(editor: Pointer, row: number) {
        this.core.editorScrollTo(editor, row);
    }

    setEditorVisibility(editor: Pointer, visible: boolean) {
        this.core.setEditorVisibility(editor, visible);
    }

    readBufferState(editor: Pointer): BufferState | null {
        const raw = this.core.readBufferState(editor);
        if (!raw) return null;
        return { entryId: raw.entry_id, rowCount: raw.row_count };
    }

    readEditorBufferStates(): BufferState[] {
        const results: BufferState[] = [];
        for (const editor of this.editors) {
            const bs = this.readBufferState(editor);
            if (bs) results.push(bs);
        }
        return results;
    }

    destroyEditor(editor: Pointer) {
        this.editors.delete(editor);
        this.core.destroyEditor(editor);
    }
}
