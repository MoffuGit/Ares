export type ColorScheme = "light" | "dark" | "system";

export type Settings = {
    scheme: ColorScheme;
    light_theme: string;
    dark_theme: string;
};

export type Theme = {
    name: string;
    fg: number[];
    bg: number[];
    primaryBg: number[];
    primaryFg: number[];
    mutedBg: number[];
    mutedFg: number[];
    scrollThumb: number[];
    scrollTrack: number[];
    border: number[];
    card: number[];
    cardFg: number[];
    popover: number[];
    popoverFg: number[];
    secondary: number[];
    secondaryFg: number[];
    accent: number[];
    accentFg: number[];
    destructive: number[];
    destructiveFg: number[];
    input: number[];
    ring: number[];
    chart1: number[];
    chart2: number[];
    chart3: number[];
    chart4: number[];
    chart5: number[];
    sidebar: number[];
    sidebarFg: number[];
    sidebarPrimary: number[];
    sidebarPrimaryFg: number[];
    sidebarAccent: number[];
    sidebarAccentFg: number[];
    sidebarBorder: number[];
    sidebarRing: number[];
}

export type WorktreeEntry = {
    id: number;
    name: string;
    path: string;
    kind: "file" | "dir";
    fileType: string;
    depth: number;
}
