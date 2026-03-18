import type { Theme } from "@ares/shared";

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

export function applyTheme(theme: Theme, scheme: "light" | "dark") {
    const root = document.documentElement;
    root.classList.remove("light", "dark");
    root.classList.add(scheme);
    for (const [cssVar, themeKey] of Object.entries(themeVarMap)) {
        const color = theme[themeKey];
        if (typeof color === "string") {
            root.style.setProperty(cssVar, color);
        }
    }
}
