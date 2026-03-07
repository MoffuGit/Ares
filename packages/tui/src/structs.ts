import { defineStruct, defineEnum } from "bun-ffi-structs";

const MouseButton = defineEnum({
    left: 0,
    middle: 1,
    right: 2,
    none: 3,
    wheel_up: 64,
    wheel_down: 65,
    wheel_right: 66,
    wheel_left: 67,
    button_8: 128,
    button_9: 129,
    button_10: 130,
    button_11: 131,
}, "u8");

const MouseType = defineEnum({
    press: 0,
    release: 1,
    motion: 2,
    drag: 3,
}, "u8");

export const KeyEvent = defineStruct([
    ["codepoint", "u32"],
    ["mods", "u8"],
    ["text_len", "u8"],
    ["_pad", "u16"],
    ["text_0", "u32"],
    ["text_1", "u32"],
    ["text_2", "u32"],
    ["text_3", "u32"],
    ["text_4", "u32"],
    ["text_5", "u32"],
    ["text_6", "u32"],
    ["text_7", "u32"],
] as const, {
    reduceValue: (v: any) => ({
        codepoint: v.codepoint,
        mods: v.mods,
        text: extractText(v),
    }),
});

function extractText(v: any): string | null {
    const len: number = v.text_len;
    if (len === 0) return null;
    const buf = new Uint8Array(32);
    const dv = new DataView(buf.buffer);
    for (let i = 0; i < 8; i++) {
        dv.setUint32(i * 4, v[`text_${i}`], true);
    }
    return new TextDecoder().decode(buf.subarray(0, len));
}

export const MouseEvent = defineStruct([
    ["col", "u16"],
    ["row", "u16"],
    ["pixel_col", "i16"],
    ["pixel_row", "i16"],
    ["xoffset", "u16"],
    ["yoffset", "u16"],
    ["button", MouseButton],
    ["mods", "u8"],
    ["type", MouseType],
] as const);

export const Resize = defineStruct([
    ["cols", "u16"],
    ["rows", "u16"],
] as const);

export const Scheme = defineStruct([
    ["value", "u8"],
] as const);
