import { useEffect, useMemo } from "react";
import { KeymapHandler as TSKeymapHandler, type Scope, type ScopeActionMap, type TrieOps, buildKeymapTrie, edgeKey, type TSTrieNode } from "@ares/shared";
import { useAppStore } from "@/lib/app";

let trieRoot: TSTrieNode = { terminal: false, children: new Map() };

const trieOps: TrieOps<TSTrieNode> = {
    getTrieRoot: () => trieRoot,
    trieStep: (node, codepoint, mods) => node.children.get(edgeKey(codepoint, mods)) ?? null,
    trieNodeIsTerminal: (node) => node.terminal,
    trieNodeHasChildren: (node) => node.children.size > 0,
};

const keymapHandler = new TSKeymapHandler<TSTrieNode>({
    trie: trieOps,
    onSequence: (sequence) => {
        for (const listener of sequenceListeners) listener(sequence);
    },
});

const sequenceListeners = new Set<(sequence: string) => void>();

function onKeymapSequence(listener: (sequence: string) => void): () => void {
    sequenceListeners.add(listener);
    return () => sequenceListeners.delete(listener);
}

const initialState = useAppStore.getState();
keymapHandler.setMode(initialState.mode);
trieRoot = buildKeymapTrie(initialState.keymaps);
keymapHandler.resetTrie();

useAppStore.subscribe((state, prev) => {
    if (state.mode !== prev.mode) {
        keymapHandler.setMode(state.mode);
    }
    if (state.keymaps !== prev.keymaps) {
        trieRoot = buildKeymapTrie(state.keymaps);
        keymapHandler.resetTrie();
    }
});

function useScopedKeymaps<S extends Scope>(scope: S): Record<string, ScopeActionMap[S]> {
    const keymaps = useAppStore((state) => state.keymaps);

    return useMemo(() => {
        const bindings = keymaps?.[scope] ?? [];
        const map: Record<string, ScopeActionMap[S]> = {};

        for (const binding of bindings) {
            map[binding.sequence] = binding.action as ScopeActionMap[S];
        }

        return map;
    }, [keymaps, scope]);
}

export function KeyMaps() {
    const globalKeymaps = useScopedKeymaps("global");
    const activeTabId = useAppStore((state) => state.activeTabId);
    const newTab = useAppStore((state) => state.newTab);
    const closeTab = useAppStore((state) => state.closeTab);
    const nextTab = useAppStore((state) => state.nextTab);
    const prevTab = useAppStore((state) => state.prevTab);
    const setMode = useAppStore((state) => state.setMode);
    const toggleSidebar = useAppStore((state) => state.toggleSidebar);

    useEffect(() => {
        const onKeyDown = (event: KeyboardEvent) => {
            const consumed = keymapHandler.handleKeyDown(event.key, {
                shift: event.shiftKey,
                alt: event.altKey,
                ctrl: event.ctrlKey,
                super: event.metaKey,
                hyper: false,
                meta: false,
                caps_lock: event.getModifierState("CapsLock"),
                num_lock: event.getModifierState("NumLock"),
            });

            if (consumed) {
                event.preventDefault();
                event.stopPropagation();
            }
        };

        document.addEventListener("keydown", onKeyDown);
        return () => document.removeEventListener("keydown", onKeyDown);
    }, []);

    useEffect(() => {
        return onKeymapSequence((sequence) => {
            const action = globalKeymaps[sequence];

            switch (action) {
                case "workspace:toggle_left_sidebar":
                    toggleSidebar();
                    break;
                case "workspace:new_tab":
                    newTab({ kind: "editor", path: "" });
                    break;
                case "workspace:next_tab":
                    nextTab();
                    break;
                case "workspace:prev_tab":
                    prevTab();
                    break;
                case "workspace:close_active_tab":
                    if (activeTabId != null) closeTab(activeTabId);
                    break;
                case "workspace:enter_insert":
                    setMode("insert");
                    break;
                case "workspace:enter_visual":
                    setMode("visual");
                    break;
                case "workspace:enter_normal":
                    setMode("normal");
                    break;
            }
        });
    }, [activeTabId, closeTab, globalKeymaps, newTab, nextTab, prevTab, setMode, toggleSidebar]);

    return null;
}
