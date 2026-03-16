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
    expanded: boolean,
    kind: "file" | "dir";
    fileType: string;
    depth: number;
}

export type Mode = "normal" | "insert" | "visual";
export type Scope = "global" | "editor" | "command_palette";

export type KeymapBinding = {
    sequence: string;
    action: string;
}

export type ScopedKeymaps = Record<Scope, KeymapBinding[]>;

export type KeyDownMods = {
    shift: boolean;
    alt: boolean;
    ctrl: boolean;
    super: boolean;
    hyper: boolean;
    meta: boolean;
    caps_lock: boolean;
    num_lock: boolean;
}
