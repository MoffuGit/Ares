import { Electroview } from "electrobun/view";
import type { Mode, Scope, KeymapBinding, AppState, WorktreeEntry, Tab } from "@ares/shared";
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
    newTab: () => void;
    closeTab: (tabId: number) => void;
    setActiveTab: (tabId: number) => void;
    nextTab: () => void;
    prevTab: () => void;

    tabs: Tab[];
    activeTabId: number | null;
}

export const useAppStore = create<AppStore>((set, get) => ({
    settings: null,
    theme: null,
    filetree: null,
    mode: "normal",
    keymaps: null,
    tabs: [],
    activeTabId: null,

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

    newTab: () => {
        const id = Date.now();
        const tab: Tab = { id, name: "untitled", };
        const tabs = [...get().tabs, tab];
        set({ tabs, activeTabId: id });
    },

    closeTab: (tabId) => {
        const { tabs, activeTabId } = get();
        const idx = tabs.findIndex((t) => t.id === tabId);
        if (idx === -1) return;
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
            tabs: [],
            activeTabId: null,
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
    if (state.mode !== prev.mode) {
        keymapHandler.setMode(state.mode);
    }
    if (state.keymaps !== prev.keymaps) {
        trieRoot = buildKeymapTrie(state.keymaps);
        keymapHandler.resetTrie();
    }
});

export { rpc };
