import { Emitter } from "./emitter.ts";
import type { Settings, Theme, WorktreeEntry } from "./types.ts";

export type AppState = {
    settings: Settings | null;
    theme: Theme | null;
    worktree: WorktreeEntry[];
};

export type AppEvents = {
    settingsUpdate: [];
    themeUpdate: [];
    worktreeUpdate: [];
};

export interface App {
    state: AppState;
    events: Emitter<AppEvents>;
    start?(): void;
    stop?(): void;
}

export class BaseApp implements App {
    readonly events = new Emitter<AppEvents>();
    _state: AppState = { settings: null, theme: null, worktree: [] };

    get state(): AppState {
        return this._state;
    }
}
