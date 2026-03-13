export type ColorScheme = "light" | "dark" | "system";

export type Settings = {
    scheme: ColorScheme;
    light_theme: string;
    dark_theme: string;
};

export type Theme = {
    name: string;
    fg: string;
    bg: string;
    primaryBg: string;
    primaryFg: string;
    mutedBg: string;
    mutedFg: string;
    scrollThumb: string;
    scrollTrack: string;
    border: string;
    card: string;
    cardFg: string;
    popover: string;
    popoverFg: string;
    secondary: string;
    secondaryFg: string;
    accent: string;
    accentFg: string;
    destructive: string;
    destructiveFg: string;
    input: string;
    ring: string;
    chart1: string;
    chart2: string;
    chart3: string;
    chart4: string;
    chart5: string;
    sidebar: string;
    sidebarFg: string;
    sidebarPrimary: string;
    sidebarPrimaryFg: string;
    sidebarAccent: string;
    sidebarAccentFg: string;
    sidebarBorder: string;
    sidebarRing: string;
    fileType: Record<string, string>;
}

export type WorktreeEntry = {
    id: number;
    name: string;
    path: string;
    kind: "file" | "dir";
    fileType: string;
    depth: number;
}
