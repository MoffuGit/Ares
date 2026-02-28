import type { Emitter } from "./emitter.ts";
import type { Settings, Theme } from "./types.ts";

export type AppState = {
    settings: Settings | null;
    theme: Theme | null;
};

export type AppEvents = {
    settingsUpdate: [];
    themeUpdate: [];
};

export interface App {
    state: AppState;
    events: Emitter<AppEvents>;
    start?(): void;
    stop?(): void;
}
