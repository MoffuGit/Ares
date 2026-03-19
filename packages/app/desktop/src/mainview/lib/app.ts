import { Electroview } from "electrobun/view";
import type { Mode, Scope, KeymapBinding, AppState, WorktreeEntry } from "@ares/shared";
import type { AppRPC } from "../../rpc.ts";
import { create } from "zustand";
import { applyTheme } from "./theme.ts";


interface AppStore extends AppState {
    setMode: (mode: Mode) => void;
    readKeymaps: (scope: Scope) => KeymapBinding[];
    loadSettings: () => Promise<void>;
    clickEntry: (entry: WorktreeEntry) => void;
}

export const useAppStore = create<AppStore>((set, get) => ({
    settings: null,
    theme: null,
    filetree: null,
    mode: "normal",
    keymaps: null,

    setMode: (mode) => {
        if (get().mode === mode) return;
        set({ mode: mode });
    },

    readKeymaps: (scope) => {
        return get().keymaps?.[scope] ?? [];
    },

    clickEntry: (entry) => {
        if (entry.kind == "dir") {
            rpc.send("expandEntry", entry.id);
        }
    },

    loadSettings: async () => {
        const state = await rpc.request.getState({});
        set({
            settings: state.settings,
            theme: state.theme,
            filetree: state.filetree,
            mode: state.mode,
            keymaps: state.keymaps,
        });
    },
}));

const rpc = Electroview.defineRPC<AppRPC>({
    handlers: {
        requests: {},
        messages: {
            settingsUpdate: (settings) => {
                useAppStore.setState({ settings });
            },
            themeUpdate: (theme) => {
                useAppStore.setState({ theme });
            },
            filetreeUpdate: (filetree) => {
                useAppStore.setState({ filetree });
            },
            keymapsUpdate: (keymaps) => {
                useAppStore.setState({ keymaps });
            },
        },
    },
});

useAppStore.subscribe((state, prev) => {
    if (state.theme !== prev.theme || state.settings !== prev.settings) {
        if (state.theme && state.settings) {
            const scheme = state.settings.scheme === "system"
                ? (state.settings.system_scheme as "light" | "dark")
                : state.settings.scheme;
            applyTheme(state.theme, scheme);
        }
    }
});

export { rpc };
