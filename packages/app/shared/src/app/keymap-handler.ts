import type { Pointer } from "bun:ffi";
import type { App } from "./index.ts";
import { KeymapHandler, type TrieOps } from "../keymap/index.ts";

export function createCoreKeymapHandler(
    core: App,
    onSequence: (sequence: string) => void,
): KeymapHandler<Pointer> {
    const trie: TrieOps<Pointer> = {
        getTrieRoot: (mode) => core.getTrieRoot(mode),
        trieStep: (node, codepoint, mods) => core.trieStep(node, codepoint, mods),
        trieNodeIsTerminal: (node) => core.trieNodeIsTerminal(node),
        trieNodeHasChildren: (node) => core.trieNodeHasChildren(node),
    };

    return new KeymapHandler({ trie, onSequence });
}
