import type { Settings, Theme, WorktreeEntry, Mode, Scope, KeymapBinding, ScopedKeymaps, KeyDownMods } from "./types.ts";
import { Emitter } from "./emitter.ts";

export type AppState = {
    settings: Settings | null;
    theme: Theme | null;
    filetree: WorktreeEntry[] | null;
    mode: Mode;
    keymaps: ScopedKeymaps | null;
};

export type AppEvents = {
    settingsUpdate: [];
    themeUpdate: [];
    filetreeUpdate: [];
    modeUpdate: [];
    keymapsUpdate: [];
    keymapSequence: [sequence: string];
};

export interface BaseApp {
    _state: AppState
    events: Emitter<AppEvents>
    selectEntry: (id: number) => void,
    setMode: (mode: Mode) => void,
    readKeymaps: (scope: Scope) => KeymapBinding[],
    handleKeyDown: (char: string, mods: KeyDownMods) => boolean | Promise<boolean>;
}
