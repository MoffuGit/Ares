import { Electroview } from "electrobun/view";
import type { Mode, Scope, KeymapBinding, AppState, WorktreeEntry, Buffer } from "@ares/shared";
import type { AppRPC } from "../../rpc.ts";
import { create } from "zustand";
import { applyTheme } from "./theme.ts";


interface AppStore extends AppState {
    buffers: Map<number, Buffer>;
    setMode: (mode: Mode) => void;
    readKeymaps: (scope: Scope) => KeymapBinding[];
    loadSettings: () => Promise<void>;
    expandEntry: (entry: WorktreeEntry) => void;
    getBuffer: (id: number) => Buffer;
}

export const useAppStore = create<AppStore>((set, get) => ({
    settings: null,
    theme: null,
    filetree: null,
    mode: "normal",
    keymaps: null,
    buffers: new Map(),

    setMode: (mode) => {
        if (get().mode === mode) return;
        set({ mode: mode });
    },

    readKeymaps: (scope) => {
        return get().keymaps?.[scope] ?? [];
    },

    expandEntry: (entry) => {
        if (entry.kind == "dir") {
            rpc.send("expandEntry", entry.id);
        }
    },

    getBuffer: (id) => {
        const cached = get().buffers.get(id);
        if (cached) return cached;

        const empty: Buffer = { id, state: "empty", content: "" };
        const buffers = new Map(get().buffers);
        buffers.set(id, empty);
        set({ buffers });

        rpc.request.readBuffer({ id }).then((buffer) => {
            if (buffer) {
                const buffers = new Map(get().buffers);
                buffers.set(id, buffer);
                set({ buffers });
            }
        });

        return empty;
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
            bufferUpdate: (buffer) => {
                const buffers = new Map(useAppStore.getState().buffers);
                buffers.set(buffer.id, buffer);
                useAppStore.setState({ buffers });
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
