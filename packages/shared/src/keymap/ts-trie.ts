import type { KeymapBinding, ScopedKeymaps } from "../types.ts";
import { parseSequence } from "./encoding.ts";

export type TSTrieNode = {
    terminal: boolean;
    children: Map<number, TSTrieNode>;
};

const EDGE_SHIFT = 21;

export function edgeKey(codepoint: number, mods: number): number {
    return (mods << EDGE_SHIFT) | codepoint;
}

export function buildKeymapTrie(keymaps: ScopedKeymaps | null): TSTrieNode {
    const root: TSTrieNode = { terminal: false, children: new Map() };
    if (!keymaps) return root;

    const bindings: KeymapBinding[] = [
        ...keymaps.global,
        ...keymaps.editor,
        ...keymaps.command_palette,
    ];

    for (const { sequence } of bindings) {
        const strokes = parseSequence(sequence);
        if (strokes.length === 0) continue;

        let node = root;
        for (const { codepoint, mods } of strokes) {
            const key = edgeKey(codepoint, mods);
            let next = node.children.get(key);
            if (!next) {
                next = { terminal: false, children: new Map() };
                node.children.set(key, next);
            }
            node = next;
        }
        node.terminal = true;
    }

    return root;
}
