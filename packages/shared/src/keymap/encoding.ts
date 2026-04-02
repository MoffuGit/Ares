import type { KeyDownMods } from "../types.ts";

export type EncodedStroke = { codepoint: number; mods: number };

export function packMods(mods: KeyDownMods): number {
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

export function formatKeystroke(char: string, mods: KeyDownMods): string {
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

/** Map from DOM KeyboardEvent.key names to codepoints (matching Zig named codepoints). */
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

export function codepointFromKey(key: string): number {
    return SPECIAL_KEYS[key] ?? 0;
}

/** Map from lowercase binding key names (as in settings.json) to codepoints. */
const NAMED_KEYS: Record<string, number> = {
    escape: 0x1b, esc: 0x1b,
    enter: 0x0d, return: 0x0d,
    tab: 0x09,
    backspace: 0x7f,
    space: 0x20,
    delete: 0x10F000,
    insert: 0x10F001,
    home: 0x10F002,
    end: 0x10F003,
    page_up: 0x10F004, pageup: 0x10F004,
    page_down: 0x10F005, pagedown: 0x10F005,
    up: 0x10F006,
    down: 0x10F007,
    left: 0x10F008,
    right: 0x10F009,
    f1: 0x10F010, f2: 0x10F011, f3: 0x10F012, f4: 0x10F013,
    f5: 0x10F014, f6: 0x10F015, f7: 0x10F016, f8: 0x10F017,
    f9: 0x10F018, f10: 0x10F019, f11: 0x10F01A, f12: 0x10F01B,
};

function parseKeyCodepoint(s: string): number {
    let key = s;
    if (key.length >= 2 && key[0] === "<" && key[key.length - 1] === ">") {
        key = key.slice(1, -1);
    }
    if (key.length === 0) return 0;

    const named = NAMED_KEYS[key.toLowerCase()];
    if (named !== undefined) return named;

    const cp = key.codePointAt(0);
    if (cp !== undefined && String.fromCodePoint(cp).length === key.length) return cp;

    return 0;
}

function parseStroke(tok: string): EncodedStroke | null {
    if (tok.length === 0) return null;

    const parts = tok.split("+");
    if (parts.length === 0) return null;
    const keyPart = parts.at(-1);
    if (!keyPart) return null;

    let mods = 0;
    for (let i = 0; i < parts.length - 1; i++) {
        const m = parts[i];
        if (!m) return null;
        const normalized = m.toLowerCase();
        if (normalized === "shift") mods |= 1 << 0;
        else if (normalized === "alt") mods |= 1 << 1;
        else if (normalized === "ctrl") mods |= 1 << 2;
        else if (normalized === "super") mods |= 1 << 3;
        else if (normalized === "hyper") mods |= 1 << 4;
        else if (normalized === "meta") mods |= 1 << 5;
        else return null;
    }

    const codepoint = parseKeyCodepoint(keyPart);
    if (codepoint === 0) return null;

    return { codepoint, mods };
}

export function parseSequence(sequence: string): EncodedStroke[] {
    const strokes: EncodedStroke[] = [];
    const tokens = sequence.split(/\s+/).filter(Boolean);
    for (const tok of tokens) {
        const stroke = parseStroke(tok);
        if (!stroke) return [];
        strokes.push(stroke);
    }
    return strokes;
}
