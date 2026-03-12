import type { Settings, Theme, WorktreeEntry } from "./types.ts";
import { Emitter } from "./emitter.ts";

export type AppState = {
    settings: Settings | null;
    theme: Theme | null;
    filetree: WorktreeEntry[] | null;
};

export type AppEvents = {
    settingsUpdate: [];
    themeUpdate: [];
    filetreeUpdate: [];
};

export interface BaseApp {
    _state: AppState
    events: Emitter<AppEvents>
}
