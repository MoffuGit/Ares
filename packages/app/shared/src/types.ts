export type ColorScheme = "light" | "dark" | "system";

export type AppState = {
    settings: Settings | null;
    theme: Theme | null;
    filetree: WorktreeEntry[] | null;
    mode: Mode;
    keymaps: ScopedKeymaps | null;
};

export type AppEvents = {
    settingsUpdate: [];
    themeUpdate: [];
    filetreeUpdate: [];
    modeUpdate: [];
    keymapsUpdate: [];
    keymapSequence: [sequence: string];
};

export type Settings = {
    scheme: ColorScheme;
    system_scheme: ColorScheme;
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

export type GlobalAction =
    | "workspace:enter_insert"
    | "workspace:enter_visual"
    | "workspace:enter_normal"
    | "workspace:toggle_left_sidebar"
    | "workspace:new_tab"
    | "workspace:next_tab"
    | "workspace:prev_tab"
    | "workspace:close_active_tab"
    | "workspace:toggle_command_palette";

export type EditorAction =
    | string;

export type CommandPaletteAction =
    | "command:up"
    | "command:down"
    | "command:select"
    | "command:scroll_up"
    | "command:scroll_down"
    | "command:top"
    | "command:bottom";

export type ScopeActionMap = {
    global: GlobalAction;
    editor: EditorAction;
    command_palette: CommandPaletteAction;
};

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

export type EditorSurface = { kind: "editor"; path: string; gpuSurfaceId?: number; entry?: WorktreeEntry };
export type TerminalSurface = { kind: "terminal"; cwd: string; gpuSurfaceId?: number };
export type Surface = EditorSurface | TerminalSurface;

export type SurfaceKind = Surface["kind"];

export type Tab = {
    id: number;
    name: string;
    surface: Surface;
};
