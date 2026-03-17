import type { Pointer } from "bun:ffi";
import type { CoreApp } from "./index.ts";
import type { KeyDownMods } from "../types.ts";

const SEQUENCE_TIMEOUT_MS = 500;

export class KeymapHandler {
    private core: CoreApp;
    private currentNode: Pointer | null = null;
    private timer: ReturnType<typeof setTimeout> | null = null;
    private sequence: string[] = [];
    private lastTerminalSequence: string | null = null;

    constructor(core: CoreApp) {
        this.core = core;
        this.core.events.on("modeUpdate", this.onModeUpdate)
        this.core.events.on("keymapsUpdate", this.onKeymapsUpdate);
    }

    destroy(): void {
        this.clearTimer();
        this.core.events.off("modeUpdate", this.onModeUpdate)
        this.core.events.off("keymapsUpdate", this.onKeymapsUpdate);
    }

    onModeUpdate = (): void => {
        this.reset()
    }

    onKeymapsUpdate = (): void => {
        this.reset()
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
        this.core.events.emit("keymapSequence", sequenceStr);
        this.reset();
    }

    handleKeyDown(char: string, mods: KeyDownMods): boolean {
        const codepoint = char.length === 1 ? char.codePointAt(0)! : codepointFromKey(char);
        if (codepoint === 0) return false;
        const pack = packMods(mods);
        const mode = this.core._state.mode;

        if (!this.currentNode) {
            const root = this.core.getTrieRoot(mode);
            if (!root) return false;
            this.currentNode = root;
        }

        const next = this.core.trieStep(this.currentNode, codepoint, pack);

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

        if (this.core.trieNodeIsTerminal(next)) {
            const seqStr = this.sequence.join(" ");
            if (!this.core.trieNodeHasChildren(next)) {
                this.emit(seqStr);
                return true;
            }
            this.lastTerminalSequence = seqStr;
            this.restartTimer();
            return true;
        }

        if (this.core.trieNodeHasChildren(next)) {
            this.restartTimer();
            return true;
        }

        this.reset();
        return false;
    }
}

function packMods(mods: KeyDownMods): number {
    let pack = 0;
    if (mods.shift) pack |= 1 << 0;
    if (mods.alt) pack |= 1 << 1;
    if (mods.ctrl) pack |= 1 << 2;
    if (mods.super) pack |= 1 << 3;
    if (mods.hyper) pack |= 1 << 4;
    if (mods.meta) pack |= 1 << 5;
    if (mods.caps_lock) pack |= 1 << 6;
    if (mods.num_lock) pack |= 1 << 7;
    return pack;
}

function formatKeystroke(char: string, mods: KeyDownMods): string {
    const parts: string[] = [];
    if (mods.ctrl) parts.push("ctrl");
    if (mods.alt) parts.push("alt");
    if (mods.shift) parts.push("shift");
    if (mods.super) parts.push("super");
    if (mods.hyper) parts.push("hyper");
    if (mods.meta) parts.push("meta");
    parts.push(char.length === 1 ? char : char.toLowerCase());
    return parts.join("+");
}

const SPECIAL_KEYS: Record<string, number> = {
    Escape: 0x1b, Enter: 0x0d, Tab: 0x09, Backspace: 0x7f,
    " ": 0x20,
    Delete: 0x10F000, Insert: 0x10F001,
    Home: 0x10F002, End: 0x10F003,
    PageUp: 0x10F004, PageDown: 0x10F005,
    ArrowUp: 0x10F006, ArrowDown: 0x10F007,
    ArrowLeft: 0x10F008, ArrowRight: 0x10F009,
    F1: 0x10F010, F2: 0x10F011, F3: 0x10F012, F4: 0x10F013,
    F5: 0x10F014, F6: 0x10F015, F7: 0x10F016, F8: 0x10F017,
    F9: 0x10F018, F10: 0x10F019, F11: 0x10F01A, F12: 0x10F01B,
};

function codepointFromKey(key: string): number {
    return SPECIAL_KEYS[key] ?? 0;
}
