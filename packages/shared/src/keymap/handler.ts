import type { Mode, KeyDownMods } from "../types.ts";
import { packMods, codepointFromKey, formatKeystroke } from "./encoding.ts";

const SEQUENCE_TIMEOUT_MS = 500;

export interface TrieOps<Node> {
    getTrieRoot(mode: Mode): Node | null;
    trieStep(node: Node, codepoint: number, mods: number): Node | null;
    trieNodeIsTerminal(node: Node): boolean;
    trieNodeHasChildren(node: Node): boolean;
}

export type KeymapHandlerOptions<Node> = {
    trie: TrieOps<Node>;
    onSequence: (sequence: string) => void;
};

export class KeymapHandler<Node> {
    private trie: TrieOps<Node>;
    private onSequence: (sequence: string) => void;
    private mode: Mode = "normal";
    private currentNode: Node | null = null;
    private timer: ReturnType<typeof setTimeout> | null = null;
    private sequence: string[] = [];
    private lastTerminalSequence: string | null = null;

    constructor(opts: KeymapHandlerOptions<Node>) {
        this.trie = opts.trie;
        this.onSequence = opts.onSequence;
    }

    destroy(): void {
        this.clearTimer();
    }

    setMode(mode: Mode): void {
        if (this.mode === mode) return;
        this.mode = mode;
        this.reset();
    }

    resetTrie(): void {
        this.reset();
    }

    private reset(): void {
        this.clearTimer();
        this.currentNode = null;
        this.sequence = [];
        this.lastTerminalSequence = null;
    }

    private restartTimer(): void {
        this.clearTimer();
        this.timer = setTimeout(() => {
            if (this.lastTerminalSequence) {
                this.emit(this.lastTerminalSequence);
            } else {
                this.reset();
            }
        }, SEQUENCE_TIMEOUT_MS);
    }

    private clearTimer(): void {
        if (this.timer !== null) {
            clearTimeout(this.timer);
            this.timer = null;
        }
    }

    private emit(sequenceStr: string): void {
        this.onSequence(sequenceStr);
        this.reset();
    }

    handleKeyDown(i: string | number, mods: KeyDownMods): boolean {
        let codepoint: number;

        if (typeof i === "number") {
            codepoint = i;
        } else {
            codepoint = i.length === 1 ? i.codePointAt(0)! : codepointFromKey(i);
        }

        if (codepoint === 0) return false;
        const pack = packMods(mods);

        if (!this.currentNode) {
            const root = this.trie.getTrieRoot(this.mode);
            if (!root) return false;
            this.currentNode = root;
        }

        const next = this.trie.trieStep(this.currentNode, codepoint, pack);

        if (!next) {
            if (this.lastTerminalSequence) {
                this.emit(this.lastTerminalSequence);
                return true;
            }
            this.reset();
            return false;
        }

        let char: string;

        if (typeof i === "number") {
            char = String.fromCodePoint(i);
        } else {
            char = i;
        }

        this.sequence.push(formatKeystroke(char, mods));
        this.currentNode = next;

        if (this.trie.trieNodeIsTerminal(next)) {
            const seqStr = this.sequence.join(" ");
            if (!this.trie.trieNodeHasChildren(next)) {
                this.emit(seqStr);
                return true;
            }
            this.lastTerminalSequence = seqStr;
            this.restartTimer();
            return true;
        }

        if (this.trie.trieNodeHasChildren(next)) {
            this.restartTimer();
            return true;
        }

        this.reset();
        return false;
    }
}
