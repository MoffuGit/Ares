import type { Theme } from "@ares/shared";

export function resolveTheme(json: string): Theme {
    const raw = JSON.parse(json) as Partial<RawThemeFile>;
    const colors = raw.colors ?? {};
    const theme = raw.theme ?? {};
    const highlightSource = raw.highlights ?? raw;

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

    const highlightGlobals: Record<string, string> = {};
    for (const [key, value] of Object.entries(highlightSource.globals ?? {})) {
        const resolvedColor = resolveOptionalColor(value, colors);
        if (resolvedColor) {
            highlightGlobals[key] = resolvedColor;
        }
    }

    const highlightRules = (highlightSource.rules ?? []).map((rule) => {
        const resolvedRule: Theme["highlights"]["rules"][number] = {};

        if (rule.name) resolvedRule.name = rule.name;
        if (rule.scope) resolvedRule.scope = rule.scope;
        if (rule.scopes) {
            resolvedRule.scopes = rule.scopes.filter((scope) => scope.length > 0);
        }

        const foreground = rule.foreground ? resolveOptionalColor(rule.foreground, colors) : undefined;
        if (foreground) resolvedRule.foreground = foreground;

        const background = rule.background ? resolveOptionalColor(rule.background, colors) : undefined;
        if (background) resolvedRule.background = background;

        const selectionForeground = rule.selection_foreground
            ? resolveOptionalColor(rule.selection_foreground, colors)
            : undefined;
        if (selectionForeground) {
            resolvedRule.selection_foreground = selectionForeground;
        }

        if (rule.font_style) resolvedRule.font_style = rule.font_style;

        return resolvedRule;
    });

    return {
        name: raw.name ?? "unknown",
        ...resolved,
        fileType,
        highlights: {
            globals: highlightGlobals,
            rules: highlightRules,
        },
    } as Theme;
}

type RawThemeFile = {
    name: string;
    colors: Record<string, string>;
    theme: Record<string, string> & {
        fileType?: Record<string, string>;
    };
    highlights?: RawHighlights;
    globals?: Record<string, string>;
    rules?: RawHighlightRule[];
};

type RawHighlights = {
    globals?: Record<string, string>;
    rules?: RawHighlightRule[];
};

type RawHighlightRule = {
    name?: string;
    scope?: string;
    scopes?: string[];
    foreground?: string;
    background?: string;
    selection_foreground?: string;
    font_style?: string;
};

const THEME_KEYS = [
    "bg", "fg", "primaryBg", "primaryFg", "mutedBg", "mutedFg", "gutter",
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
    return resolveOptionalColor(value, colors) ?? "#000000ff";
}

function resolveOptionalColor(value: string, colors: Record<string, string>): string | undefined {
    if (value.startsWith("#")) return normalizeHex(value);
    const resolved = colors[value];
    if (resolved) return normalizeHex(resolved);
    return undefined;
}
