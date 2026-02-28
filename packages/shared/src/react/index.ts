import { createContext, createElement, useContext, useSyncExternalStore, type ReactNode } from "react";
import type { App, AppState } from "../app.ts";
import type { Settings } from "../types.ts";

const AppContext = createContext<App | null>(null);

export function AppProvider({ app, children }: { app: App; children: ReactNode }) {
    return createElement(AppContext, { value: app }, children);
}

export function useApp(): App {
    const app = useContext(AppContext);
    if (!app) throw new Error("useApp must be used within AresProvider");
    return app;
}

export function useAppState(): AppState {
    const app = useApp();
    return app.state;
}

export function useSettings(): Settings | null {
    const app = useApp();
    return useSyncExternalStore(
        (cb) => {
            app.events.on("settingsUpdate", cb);
            return () => app.events.off("settingsUpdate", cb);
        },
        () => app.state.settings,
    );
}
