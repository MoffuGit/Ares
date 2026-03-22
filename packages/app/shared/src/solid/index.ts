import { createContext, useContext, createSignal, onCleanup, type Accessor } from "solid-js";
import type { Settings, Theme, WorktreeEntry, Mode, Scope, ScopedKeymaps, ScopeActionMap, AppState } from "../types.ts";
import type { App } from "../app/index.ts";

export const AppContext = createContext<App>();

export function useApp(): App {
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
    app.on("settingsUpdate", handler);
    onCleanup(() => app.off("settingsUpdate", handler));
    return settings;
}

export function useTheme(): Accessor<Theme | null> {
    const app = useApp();
    const [theme, setTheme] = createSignal<Theme | null>(app._state.theme);
    const handler = () => setTheme(() => app._state.theme);
    app.on("themeUpdate", handler);
    onCleanup(() => app.off("themeUpdate", handler));
    return theme;
}

export function useFiletree(): Accessor<WorktreeEntry[] | null> {
    const app = useApp();
    const [filetree, setFiletree] = createSignal<WorktreeEntry[] | null>(app._state.filetree);
    const handler = () => setFiletree(() => app._state.filetree);
    app.on("filetreeUpdate", handler);
    onCleanup(() => app.off("filetreeUpdate", handler));
    return filetree;
}

export function useMode(): Accessor<Mode> {
    const app = useApp();
    const [mode, setMode] = createSignal<Mode>(app._state.mode);
    const handler = () => setMode(() => app._state.mode);
    app.on("modeUpdate", handler);
    onCleanup(() => app.off("modeUpdate", handler));
    return mode;
}

export function useKeymaps(): Accessor<ScopedKeymaps | null> {
    const app = useApp();
    const [keymaps, setKeymaps] = createSignal<ScopedKeymaps | null>(app._state.keymaps);
    const handler = () => setKeymaps(() => app._state.keymaps);
    app.on("keymapsUpdate", handler);
    onCleanup(() => app.off("keymapsUpdate", handler));
    return keymaps;
}

export function useScopedKeymaps<S extends Scope>(scope: Scope): Accessor<Record<string, ScopeActionMap[S]>> {
    const keymaps = useKeymaps();
    return () => {
        const bindings = keymaps()?.[scope] ?? [];
        const map: Record<string, ScopeActionMap[S]> = {};
        for (const b of bindings) {
            map[b.sequence] = b.action as ScopeActionMap[S];
        }
        return map;

    };
}

// export function useKeymapHandler(scope: Scope): (e: KeyboardEvent) => boolean {
//     const app = useApp();
//     const handler = new KeymapHandler(app, scope);
//     onCleanup(() => handler.destroy());
//     return (e: KeyboardEvent) => handler.handleKeyDown(e);
// }
