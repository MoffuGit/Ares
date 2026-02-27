import { createContext, createElement, useContext, useSyncExternalStore, type ReactNode } from "react";
import type { App, AppState } from "../app.ts";
import type { Settings } from "../types.ts";

const AresContext = createContext<App | null>(null);

export function AresProvider({ app, children }: { app: App; children: ReactNode }) {
    return createElement(AresContext, { value: app }, children);
}

export function useApp(): App {
    const app = useContext(AresContext);
    if (!app) throw new Error("useApp must be used within AresProvider");
    return app;
}

export function useAppState(): AppState {
    const app = useApp();
    return useSyncExternalStore(
        (cb) => {
            app.events.on("change", cb);
            return () => app.events.off("change", cb);
        },
        () => app.state,
    );
}

export function useSettings(): Settings | null {
    return useAppState().settings;
}
