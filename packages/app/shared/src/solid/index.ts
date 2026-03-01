import { createContext, useContext, createSignal, onCleanup, type Accessor } from "solid-js";
import type { App, AppState } from "../app.ts";
import type { Settings, Theme } from "../types.ts";

export const AppContext = createContext<App>();

export function useApp(): App {
    const app = useContext(AppContext);
    if (!app) throw new Error("useApp must be used within AppContext.Provider");
    return app;
}

export function useAppState(): AppState {
    const app = useApp();
    return app.state;
}

export function useSettings(): Accessor<Settings | null> {
    const app = useApp();
    const [settings, setSettings] = createSignal<Settings | null>(app.state.settings);
    const handler = () => setSettings(() => app.state.settings);
    app.events.on("settingsUpdate", handler);
    onCleanup(() => app.events.off("settingsUpdate", handler));
    return settings;
}

export function useTheme(): Accessor<Theme | null> {
    const app = useApp();
    const [theme, setTheme] = createSignal<Theme | null>(app.state.theme);
    const handler = () => setTheme(() => app.state.theme);
    app.events.on("themeUpdate", handler);
    onCleanup(() => app.events.off("themeUpdate", handler));
    return theme;
}
