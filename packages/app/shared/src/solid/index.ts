import { createContext, useContext, createSignal, onCleanup, type Accessor } from "solid-js";
import type { BaseApp, AppState } from "../app.ts";
import type { Settings, Theme, WorktreeEntry } from "../types.ts";

export const AppContext = createContext<BaseApp>();

export function useApp(): BaseApp {
    const app = useContext(AppContext);
    if (!app) throw new Error("useApp must be used within AppContext.Provider");
    return app;
}

export function useAppState(): AppState {
    const app = useApp();
    return app._state;
}

export function useSettings(): Accessor<Settings | null> {
    const app = useApp();
    const [settings, setSettings] = createSignal<Settings | null>(app._state.settings);
    const handler = () => setSettings(() => app._state.settings);
    app.events.on("settingsUpdate", handler);
    onCleanup(() => app.events.off("settingsUpdate", handler));
    return settings;
}

export function useTheme(): Accessor<Theme | null> {
    const app = useApp();
    const [theme, setTheme] = createSignal<Theme | null>(app._state.theme);
    const handler = () => setTheme(() => app._state.theme);
    app.events.on("themeUpdate", handler);
    onCleanup(() => app.events.off("themeUpdate", handler));
    return theme;
}

export function useFiletree(): Accessor<WorktreeEntry[] | null> {
    const app = useApp();
    const [theme, setTheme] = createSignal<WorktreeEntry[] | null>(app._state.filetree);
    const handler = () => setTheme(() => app._state.filetree);
    app.events.on("filetreeUpdate", handler);
    onCleanup(() => app.events.off("filetreeUpdate", handler));
    return theme;
}
