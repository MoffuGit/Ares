import { defineStruct, defineEnum } from "bun-ffi-structs";

const SchemeEnum = defineEnum({ light: 0, dark: 1, system: 2 }, "u64");

export const SettingsView = defineStruct([
    ["scheme", SchemeEnum],
    ["light_theme", "char*"],
    ["light_theme_len", "u64", { lengthOf: "light_theme" }],
    ["dark_theme", "char*"],
    ["dark_theme_len", "u64", { lengthOf: "dark_theme" }],
] as const);
