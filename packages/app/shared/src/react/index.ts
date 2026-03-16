import { createContext, createElement, useContext, useSyncExternalStore, type ReactNode } from "react";
import type { BaseApp, AppState } from "../app.ts";
import type { Settings, Theme, WorktreeEntry, Mode, Scope, KeymapBinding, ScopedKeymaps } from "../types.ts";

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

export function useFiletree(): WorktreeEntry[] | null {
    const app = useApp();
    return useSyncExternalStore(
        (cb) => {
            app.events.on("filetreeUpdate", cb);
            return () => app.events.off("filetreeUpdate", cb);
        },
        () => app._state.filetree,
    );
}

export function useMode(): Mode {
    const app = useApp();
    return useSyncExternalStore(
        (cb) => {
            app.events.on("modeUpdate", cb);
            return () => app.events.off("modeUpdate", cb);
        },
        () => app._state.mode,
    );
}

export function useKeymaps(): ScopedKeymaps | null {
    const app = useApp();
    return useSyncExternalStore(
        (cb) => {
            app.events.on("keymapsUpdate", cb);
            return () => app.events.off("keymapsUpdate", cb);
        },
        () => app._state.keymaps,
    );
}

export function useScopedKeymaps(scope: Scope): KeymapBinding[] {
    const keymaps = useKeymaps();
    return keymaps?.[scope] ?? [];
}

// export function useKeymapHandler(scope: Scope): (e: KeyboardEvent) => boolean {
//     const app = useApp();
//     const handlerRef = useRef<KeymapHandler | null>(null);
//
//     useEffect(() => {
//         const handler = new KeymapHandler(app, scope);
//         handlerRef.current = handler;
//         return () => {
//             handler.destroy();
//             handlerRef.current = null;
//         };
//     }, [app, scope]);
//
//     return (e: KeyboardEvent) => handlerRef.current?.handleKeyDown(e) ?? false;
// }
