import type { ColorScheme } from "./types.ts";

export type * from "./types.ts";
export * from "./app.ts";
export * from "./emitter.ts";
export * from "./keymap/index.ts";

export const SchemeMap: Record<number, ColorScheme> = {
    0: "light",
    1: "dark",
    2: "system",
};
