import type { Emitter } from "./emitter.ts";
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
