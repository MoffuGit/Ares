import { createContext, createElement, useContext, useSyncExternalStore, type ReactNode } from "react";
import type { BaseApp, AppState } from "../app.ts";
import type { Settings, Theme, WorktreeEntry } from "../types.ts";

const AppContext = createContext<BaseApp | null>(null);

export function AppProvider({ app, children }: { app: BaseApp; children: ReactNode }) {
    return createElement(AppContext.Provider, { value: app }, children);
}

export function useApp(): BaseApp {
    const app = useContext(AppContext);
    if (!app) throw new Error("useApp must be used within AresProvider");
    return app;
}

export function useAppState(): AppState {
    const app = useApp();
    return app._state;
}

export function useSettings(): Settings | null {
    const app = useApp();
    return useSyncExternalStore(
        (cb) => {
            app.events.on("settingsUpdate", cb);
            return () => app.events.off("settingsUpdate", cb);
        },
        () => app._state.settings,
    );
}

export function useTheme(): Theme | null {
    const app = useApp();
    return useSyncExternalStore(
        (cb) => {
            app.events.on("themeUpdate", cb);
            return () => app.events.off("themeUpdate", cb);
        },
        () => app._state.theme,
    );
}

