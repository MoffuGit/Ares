import { defineStruct, defineEnum } from "bun-ffi-structs";

const Scheme = defineEnum({ light: 0, dark: 1, system: 2 }, "u64");

export const Settings = defineStruct([
    ["scheme", Scheme],
    ["light_theme", "char*"],
    ["light_theme_len", "u64", { lengthOf: "light_theme" }],
    ["dark_theme", "char*"],
    ["dark_theme_len", "u64", { lengthOf: "dark_theme" }],
] as const);

export const KeymapEntry = defineStruct([
    ["sequence", "char*"],
    ["sequence_len", "u64", { lengthOf: "sequence" }],
    ["action", "char*"],
    ["action_len", "u64", { lengthOf: "action" }],
] as const);

export const WorktreeEntry = defineStruct([
    ["id", "u64"],
    ["kind", "u8"],
    ["is_expanded", "bool_u8"],
    ["depth", "u16"],
    ["path", "char*"],
    ["path_len", "u64", { lengthOf: "path" }],
    ["file_type", "char*"],
    ["file_type_len", "u64", { lengthOf: "file_type" }],
] as const);
