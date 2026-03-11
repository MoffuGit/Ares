import { defineStruct, defineEnum } from "bun-ffi-structs";

const Scheme = defineEnum({ light: 0, dark: 1, system: 2 }, "u64");

export const Settings = defineStruct([
    ["scheme", Scheme],
    ["light_theme", "char*"],
    ["light_theme_len", "u64", { lengthOf: "light_theme" }],
    ["dark_theme", "char*"],
    ["dark_theme_len", "u64", { lengthOf: "dark_theme" }],
] as const);

export const Theme = defineStruct([
    ["name", "char*"],
    ["len", "u64", { lengthOf: "name" }],
    ["fg", "u32"],
    ["bg", "u32"],
    ["primaryBg", "u32"],
    ["primaryFg", "u32"],
    ["mutedBg", "u32"],
    ["mutedFg", "u32"],
    ["scrollThumb", "u32"],
    ["scrollTrack", "u32"],
    ["border", "u32"],
    ["card", "u32"],
    ["cardFg", "u32"],
    ["popover", "u32"],
    ["popoverFg", "u32"],
    ["secondary", "u32"],
    ["secondaryFg", "u32"],
    ["accent", "u32"],
    ["accentFg", "u32"],
    ["destructive", "u32"],
    ["destructiveFg", "u32"],
    ["input", "u32"],
    ["ring", "u32"],
    ["chart1", "u32"],
    ["chart2", "u32"],
    ["chart3", "u32"],
    ["chart4", "u32"],
    ["chart5", "u32"],
    ["sidebar", "u32"],
    ["sidebarFg", "u32"],
    ["sidebarPrimary", "u32"],
    ["sidebarPrimaryFg", "u32"],
    ["sidebarAccent", "u32"],
    ["sidebarAccentFg", "u32"],
    ["sidebarBorder", "u32"],
    ["sidebarRing", "u32"],
] as const);

export const WorktreeEntry = defineStruct([
    ["id", "u64"],
    ["kind", "u8"],
    ["file_type", "u8"],
    ["depth", "u16"],
    ["_pad", "u32"],
    ["path", "char*"],
    ["path_len", "u64", { lengthOf: "path" }],
] as const);
