import type { ColorScheme } from "./types.ts";

export type * from "./types.ts";
export type * from "./app.ts";
export * from "./emitter.ts";

export const SchemeMap: Record<number, ColorScheme> = {
    0: "light",
    1: "dark",
    2: "system",
};

export const FileType: string[] = [
    "zig", "c", "cpp", "h", "py", "js", "ts", "json", "xml", "yaml",
    "toml", "md", "txt", "html", "css", "sh", "go", "rs", "java", "rb",
    "lua", "makefile", "dockerfile", "gitignore", "license", "unknown",
];
