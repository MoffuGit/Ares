import type { Theme } from "@ares/shared";

function rgbaToString(rgba: number[]): string {
    const [r, g, b] = rgba;
    const a = rgba.length >= 4 ? rgba[3] / 255 : 1;
    if (a < 1) {
        return `rgba(${r}, ${g}, ${b}, ${a.toFixed(3)})`;
    }
    return `rgb(${r}, ${g}, ${b})`;
}

const themeVarMap: Record<string, keyof Theme> = {
    "--background": "bg",
    "--foreground": "fg",
    "--primary": "primaryBg",
    "--primary-foreground": "primaryFg",
    "--muted": "mutedBg",
    "--muted-foreground": "mutedFg",
    "--border": "border",
    "--card": "card",
    "--card-foreground": "cardFg",
    "--popover": "popover",
    "--popover-foreground": "popoverFg",
    "--secondary": "secondary",
    "--secondary-foreground": "secondaryFg",
    "--accent": "accent",
    "--accent-foreground": "accentFg",
    "--destructive": "destructive",
    "--destructive-foreground": "destructiveFg",
    "--input": "input",
    "--ring": "ring",
    "--chart-1": "chart1",
    "--chart-2": "chart2",
    "--chart-3": "chart3",
    "--chart-4": "chart4",
    "--chart-5": "chart5",
    "--sidebar": "sidebar",
    "--sidebar-foreground": "sidebarFg",
    "--sidebar-primary": "sidebarPrimary",
    "--sidebar-primary-foreground": "sidebarPrimaryFg",
    "--sidebar-accent": "sidebarAccent",
    "--sidebar-accent-foreground": "sidebarAccentFg",
    "--sidebar-border": "sidebarBorder",
    "--sidebar-ring": "sidebarRing",
};

export function applyTheme(theme: Theme) {
    const root = document.documentElement;
    for (const [cssVar, themeKey] of Object.entries(themeVarMap)) {
        const rgba = theme[themeKey];
        if (Array.isArray(rgba)) {
            root.style.setProperty(cssVar, rgbaToString(rgba));
        }
    }
}
