import type { Pointer } from "bun:ffi";
import { readFileSync } from "fs";
import { join } from "path";
import type { Mode, ParsedKeymap, ParsedKeymaps, Settings } from "@ares/shared";
import { CoreLib, resolveCoreLib } from "@ares/core";

const MODES = ["normal", "insert", "visual"] as const satisfies readonly Mode[];

export class App {
    core: CoreLib;
    coreApp: Pointer;
    settingsPath: string;
    parsedKeymaps: ParsedKeymaps = {};
    currentMode: Mode = "normal";

    coreProject: Pointer | null = null;

    constructor(window: Pointer, settingsPath: string, libPath?: string) {
        this.core = resolveCoreLib(libPath);
        const coreApp = this.core.createApp(window);

        if (!coreApp) throw new Error("An error happen while creating the core app");
        this.coreApp = coreApp;
        this.settingsPath = settingsPath;

        console.log(`loading settings at: ${settingsPath}`)
        this.core.loadSettings(coreApp, settingsPath);
    }

    readSettings(): Settings {
        this.refreshParsedKeymaps();

        return {
            ...this.core.readSettings(this.coreApp),
            keymaps: this.parsedKeymaps,
        };
    }

    readTheme() {
        return this.core.readTheme(this.coreApp);
    }

    readMode(): Mode {
        return this.currentMode;
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

    setMode(mode: Mode) {
        if (this.currentMode === mode) return;

        this.core.setMode(this.coreApp, mode);
        this.currentMode = mode;
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

    private refreshParsedKeymaps() {
        const parsedKeymaps = readParsedKeymaps(this.settingsPath);
        if (parsedKeymaps) {
            this.parsedKeymaps = parsedKeymaps;
        }
    }
}

function readParsedKeymaps(settingsPath: string): ParsedKeymaps | null {
    try {
        const json = readFileSync(join(settingsPath, "settings.json"), "utf8");
        const settings = JSON.parse(json) as { keymaps?: unknown };
        return parseKeymaps(settings.keymaps);
    } catch {
        return null;
    }
}

function parseKeymaps(rawKeymaps: unknown): ParsedKeymaps {
    if (!isRecord(rawKeymaps)) return {};

    const parsedKeymaps: ParsedKeymaps = {};

    for (const [scope, scopeValue] of Object.entries(rawKeymaps)) {
        if (!isRecord(scopeValue)) continue;

        const parsedScope: Partial<Record<Mode, ParsedKeymap[]>> = {};

        for (const mode of MODES) {
            const modeValue = scopeValue[mode];
            if (!isRecord(modeValue)) continue;

            const bindings: ParsedKeymap[] = [];
            for (const [sequence, cmd] of Object.entries(modeValue)) {
                if (typeof cmd !== "string") continue;
                bindings.push({ scope, mode, cmd, sequence });
            }

            if (bindings.length > 0) {
                parsedScope[mode] = bindings;
            }
        }

        if (Object.keys(parsedScope).length > 0) {
            parsedKeymaps[scope] = parsedScope;
        }
    }

    return parsedKeymaps;
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}
