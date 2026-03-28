import { Electroview } from "electrobun/view";
import type { Mode, Scope, KeymapBinding, AppState, WorktreeEntry, Tab, Surface, BufferState } from "@ares/shared";
import { KeymapHandler, type TrieOps, buildKeymapTrie, edgeKey, type TSTrieNode } from "@ares/shared";
import type { AppRPC } from "../../rpc.ts";
import { create } from "zustand";
import { applyTheme } from "./theme.ts";

let trieRoot: TSTrieNode = { terminal: false, children: new Map() };

const trieOps: TrieOps<TSTrieNode> = {
    getTrieRoot: () => trieRoot,
    trieStep: (node, codepoint, mods) => node.children.get(edgeKey(codepoint, mods)) ?? null,
    trieNodeIsTerminal: (node) => node.terminal,
    trieNodeHasChildren: (node) => node.children.size > 0,
};

export const keymapHandler = new KeymapHandler<TSTrieNode>({
    trie: trieOps,
    onSequence: (sequence) => {
        for (const listener of sequenceListeners) listener(sequence);
    },
});

const sequenceListeners = new Set<(sequence: string) => void>();

export function onKeymapSequence(listener: (sequence: string) => void): () => void {
    sequenceListeners.add(listener);
    return () => sequenceListeners.delete(listener);
}

interface AppStore extends AppState {
    setMode: (mode: Mode) => void;
    readKeymaps: (scope: Scope) => KeymapBinding[];
    loadSettings: () => Promise<void>;
    expandEntry: (entry: WorktreeEntry) => void;
    selectSurfaceEntry: (entry: WorktreeEntry) => void;
    newTab: (surface: Surface) => void;
    closeTab: (tabId: number) => void;
    setActiveTab: (tabId: number) => void;
    setGpuSurfaceId: (tabId: number, gpuSurfaceId: number) => void;
    nextTab: () => void;
    prevTab: () => void;

    tabs: Tab[];
    activeTabId: number | null;

    sidebarOpen: boolean;
    setSidebarOpen: (open: boolean) => void;
    toggleSidebar: () => void;
}

function surfaceName(surface: Surface): string {
    switch (surface.kind) {
        case "editor": return surface.path.split("/").pop() ?? "untitled";
        case "terminal": return "terminal";
    }
}

export const useAppStore = create<AppStore>((set, get) => ({
    settings: null,
    theme: null,
    filetree: null,
    mode: "normal",
    keymaps: null,
    tabs: [],
    activeTabId: null,
    sidebarOpen: false,
    setSidebarOpen: (open) => set({ sidebarOpen: open }),
    toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),

    setMode: (mode) => {
        if (get().mode === mode) return;
        set({ mode: mode });
        rpc.send("setMode", mode);
    },

    readKeymaps: (scope) => {
        return get().keymaps?.[scope] ?? [];
    },

    expandEntry: (entry) => {
        if (entry.kind == "dir") {
            rpc.send("expandEntry", entry.id);
        }
    },

    selectSurfaceEntry: (entry) => {
        const { activeTabId, tabs } = get();
        const activeTab = tabs.find((t) => t.id === activeTabId);
        if (!activeTab || activeTab.surface.kind !== "editor") return;
        if (activeTab.surface.gpuSurfaceId != null) {
            rpc.send("selectSurfaceEntry", { surfaceId: activeTab.surface.gpuSurfaceId, id: entry.id });
        }
        set({
            tabs: tabs.map((t) => t.id === activeTabId && t.surface.kind === "editor"
                ? { ...t, name: entry.name, surface: { ...t.surface, entry: entry } } : t)
        });
    },

    newTab: (surface) => {
        const id = Date.now();
        const name = surfaceName(surface);
        const tab: Tab = { id, name, surface: surface };
        const tabs = [...get().tabs, tab];
        set({ tabs, activeTabId: id });
    },

    closeTab: (tabId) => {
        const { tabs, activeTabId } = get();
        const idx = tabs.findIndex((t) => t.id === tabId);
        if (idx === -1) return;
        const tab = tabs[idx];
        if (tab.surface.gpuSurfaceId != null) {
            rpc.send("gpuTagStop", { id: tab.surface.gpuSurfaceId });
        }
        const next = tabs.filter((t) => t.id !== tabId);
        let nextActiveId: number | null = null;
        if (next.length > 0 && activeTabId === tabId) {
            nextActiveId = next[Math.min(idx, next.length - 1)].id;
        } else if (next.length > 0) {
            nextActiveId = activeTabId;
        }
        set({ tabs: next, activeTabId: nextActiveId });
    },

    setActiveTab: (tabId) => {
        set({ activeTabId: tabId });
    },

    setGpuSurfaceId: (tabId, gpuSurfaceId) => {
        const tabs = get().tabs.map((t) =>
            t.id === tabId ? { ...t, surface: { ...t.surface, gpuSurfaceId } } : t
        );
        set({ tabs });
    },

    nextTab: () => {
        const { tabs, activeTabId } = get();
        if (tabs.length === 0) return;
        const idx = tabs.findIndex((t) => t.id === activeTabId);
        set({ activeTabId: tabs[(idx + 1) % tabs.length].id });
    },

    prevTab: () => {
        const { tabs, activeTabId } = get();
        if (tabs.length === 0) return;
        const idx = tabs.findIndex((t) => t.id === activeTabId);
        set({ activeTabId: tabs[(idx - 1 + tabs.length) % tabs.length].id });
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
            bufferUpdate: (bufferState) => {
                const tabs = useAppStore.getState().tabs.map((t) => {
                    if (t.surface.kind === "editor" && t.surface.entry?.id === bufferState.entryId) {
                        return { ...t, surface: { ...t.surface, bufferState } };
                    }
                    return t;
                });
                useAppStore.setState({ tabs });
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
    if (state.mode !== prev.mode) {
        keymapHandler.setMode(state.mode);
    }
    if (state.keymaps !== prev.keymaps) {
        trieRoot = buildKeymapTrie(state.keymaps);
        keymapHandler.resetTrie();
    }
});

export { rpc };
