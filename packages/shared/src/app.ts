import type { Emitter } from "./emitter.ts";
import type { Settings } from "./types.ts";

export type AppState = {
    settings: Settings | null;
};

export type AppEvents = {
    change: [];
};

export interface App {
    state: AppState;
    events: Emitter<AppEvents>;
    start?(): void;
    stop?(): void;
}
