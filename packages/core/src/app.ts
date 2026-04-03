import type { Pointer } from "bun:ffi";
import { CoreLib, resolveCoreLib } from "@ares/core";
import type { Mode, ModeKeymaps, Scope, ScopedKeymaps } from "@ares/shared";

const MODES: Mode[] = ["normal", "insert", "visual"];
const SCOPES: Scope[] = ["global", "editor", "command_palette"];

function createScopedKeymaps(): ScopedKeymaps {
    return {
        global: [],
        editor: [],
        command_palette: [],
    };
}

export class App {
    core: CoreLib;
    coreApp: Pointer;

    coreProject: Pointer | null = null;

    constructor(settingsPath: string, libPath?: string) {
        this.core = resolveCoreLib(libPath);
        const coreApp = this.core.createApp();

        if (!coreApp) throw new Error("An error happen while creating the core app");
        this.coreApp = coreApp;

        console.log(`loading settings at: ${settingsPath}`)
        this.core.loadSettings(coreApp, settingsPath);
    }

    readSettings() {
        return this.core.readSettings(this.coreApp);
    }

    readTheme() {
        return this.core.readTheme(this.coreApp);
    }

    readKeymaps(): ModeKeymaps {
        const keymaps: ModeKeymaps = {
            normal: createScopedKeymaps(),
            insert: createScopedKeymaps(),
            visual: createScopedKeymaps(),
        };

        for (const [modeIndex, mode] of MODES.entries()) {
            for (const [scopeIndex, scope] of SCOPES.entries()) {
                keymaps[mode][scope] = this.core.readKeymapEntries(this.coreApp, scopeIndex, modeIndex);
            }
        }

        return keymaps;
    }

    readFileTree() {
        if (!this.coreProject) return null;

        return this.core.readFileTree(this.coreProject);
    }

    openProject(path: string) {
        this.destroyProject();

        const nextProject = this.core.createProject(this.coreApp, path);
        if (nextProject == null) throw new Error("Failed to create project");

        this.coreProject = nextProject;
    }

    expandEntry(id: number) {
        if (!this.coreProject) return;
        this.core.expandEntry(this.coreProject, id);
    }

    destroyProject() {
        if (this.coreProject != null) {
            this.core.destroyProject(this.coreProject);
            this.coreProject = null;
        }
    }

    destroy() {
        this.destroyProject();
        this.core.destroyApp(this.coreApp);
        this.core.deinitState();
    }
}
