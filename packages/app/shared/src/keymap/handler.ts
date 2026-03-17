import type { Mode, KeyDownMods } from "../types.ts";
import type { AppEvents } from "../app.ts";
import type { Emitter } from "../emitter.ts";
import { packMods, codepointFromKey, formatKeystroke } from "./encoding.ts";

const SEQUENCE_TIMEOUT_MS = 500;

export interface KeymapTrieHost<Node> {
    _state: { mode: Mode };
    events: Emitter<AppEvents>;

    getTrieRoot(mode: Mode): Node | null;
    trieStep(node: Node, codepoint: number, mods: number): Node | null;
    trieNodeIsTerminal(node: Node): boolean;
    trieNodeHasChildren(node: Node): boolean;
}

export class KeymapHandler<Node> {
    private host: KeymapTrieHost<Node>;
    private currentNode: Node | null = null;
    private timer: ReturnType<typeof setTimeout> | null = null;
    private sequence: string[] = [];
    private lastTerminalSequence: string | null = null;

    constructor(host: KeymapTrieHost<Node>) {
        this.host = host;
        this.host.events.on("modeUpdate", this.onModeUpdate);
        this.host.events.on("keymapsUpdate", this.onKeymapsUpdate);
    }

    destroy(): void {
        this.clearTimer();
        this.host.events.off("modeUpdate", this.onModeUpdate);
        this.host.events.off("keymapsUpdate", this.onKeymapsUpdate);
    }

    onModeUpdate = (): void => {
        this.reset();
    };

    onKeymapsUpdate = (): void => {
        this.reset();
    };

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
        this.host.events.emit("keymapSequence", sequenceStr);
        this.reset();
    }

    handleKeyDown(char: string, mods: KeyDownMods): boolean {
        const codepoint = char.length === 1 ? char.codePointAt(0)! : codepointFromKey(char);
        if (codepoint === 0) return false;
        const pack = packMods(mods);
        const mode = this.host._state.mode;

        if (!this.currentNode) {
            const root = this.host.getTrieRoot(mode);
            if (!root) return false;
            this.currentNode = root;
        }

        const next = this.host.trieStep(this.currentNode, codepoint, pack);

        if (!next) {
            if (this.lastTerminalSequence) {
                this.emit(this.lastTerminalSequence);
                return true;
            }
            this.reset();
            return false;
        }

        this.sequence.push(formatKeystroke(char, mods));
        this.currentNode = next;

        if (this.host.trieNodeIsTerminal(next)) {
            const seqStr = this.sequence.join(" ");
            if (!this.host.trieNodeHasChildren(next)) {
                this.emit(seqStr);
                return true;
            }
            this.lastTerminalSequence = seqStr;
            this.restartTimer();
            return true;
        }

        if (this.host.trieNodeHasChildren(next)) {
            this.restartTimer();
            return true;
        }

        this.reset();
        return false;
    }
}
