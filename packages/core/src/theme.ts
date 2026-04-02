import type { Theme } from "./types.ts";

export function resolveTheme(json: string): Theme {
    const raw = JSON.parse(json) as Partial<RawThemeFile>;
    const colors = raw.colors ?? {};
    const theme = raw.theme ?? {};

    const resolved: Record<string, string> = {};
    for (const key of THEME_KEYS) {
        const ref = theme[key];
        resolved[key] = ref ? resolveColor(ref, colors) : "#000000ff";
    }

    const fileType: Record<string, string> = {};
    if (theme.fileType) {
        for (const [key, value] of Object.entries(theme.fileType)) {
            fileType[key] = resolveColor(value, colors);
        }
    }

    return {
        name: raw.name ?? "unknown",
        ...resolved,
        fileType,
    } as Theme;
}

type RawThemeFile = {
    name: string;
    colors: Record<string, string>;
    theme: Record<string, string> & {
        fileType?: Record<string, string>;
    };
};

const THEME_KEYS = [
    "bg", "fg", "primaryBg", "primaryFg", "mutedBg", "mutedFg",
    "scrollThumb", "scrollTrack", "border", "card", "cardFg",
    "popover", "popoverFg", "secondary", "secondaryFg",
    "accent", "accentFg", "destructive", "destructiveFg",
    "input", "ring", "chart1", "chart2", "chart3", "chart4", "chart5",
    "sidebar", "sidebarFg", "sidebarPrimary", "sidebarPrimaryFg",
    "sidebarAccent", "sidebarAccentFg", "sidebarBorder", "sidebarRing",
    "modeNormal", "modeVisual", "modeInsert",
] as const;

function normalizeHex(hex: string): string {
    const h = hex.toLowerCase();
    if (h.length === 7) return h + "ff";
    if (h.length === 9) return h;
    return "#000000ff";
}

function resolveColor(value: string, colors: Record<string, string>): string {
    if (value.startsWith("#")) return normalizeHex(value);
    const resolved = colors[value];
    if (resolved) return normalizeHex(resolved);
    return "#000000ff";
}
