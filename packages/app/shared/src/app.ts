import type { Settings, Theme } from "./types.ts";
import { Emitter } from "./emitter.ts";

export type AppState = {
    settings: Settings | null;
    theme: Theme | null;
};

export type AppEvents = {
    settingsUpdate: [];
    themeUpdate: [];
};

export interface BaseApp {
    _state: AppState
    events: Emitter<AppEvents>
}
