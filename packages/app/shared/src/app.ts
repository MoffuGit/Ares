import type { Settings, Theme, WorktreeEntry, Mode, Scope, KeymapBinding, ScopedKeymaps } from "./types.ts";
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
};

export interface BaseApp {
    _state: AppState
    events: Emitter<AppEvents>
    selectEntry: (id: number) => void,
    setMode: (mode: Mode) => void,
    readKeymaps: (scope: Scope) => KeymapBinding[],
}
