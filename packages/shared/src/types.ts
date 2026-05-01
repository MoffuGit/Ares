export type ColorScheme = "light" | "dark" | "system";
export type TabsPosition = "horizontal" | "vertical";

export type SidebarKind = "filetree" | "tabs";

export type SurfaceState = {
    cellWidth: number;
    cellHeight: number;
    rendererHealth: number;
};

export type EditorState = {
    entryId: number;
    rowCount: number;
    scrollRow: number;
    cursorRow: number;
    cursorCol: number;
};

export type Project = {
    name: string;
    path: string;
};

export type Settings = {
    scheme: ColorScheme;
    system_scheme: ColorScheme;
    tabs_position: TabsPosition;
    light_theme: string;
    dark_theme: string;
    keymaps: ParsedKeymaps;
};

export type ThemeHighlightRule = {
    name?: string;
    scope?: string;
    scopes?: string[];
    foreground?: string;
    background?: string;
    selection_foreground?: string;
    font_style?: string;
};

export type ThemeHighlights = {
    globals: Record<string, string>;
    rules: ThemeHighlightRule[];
};

export type Theme = {
    name: string;
    fg: string;
    bg: string;
    primaryBg: string;
    primaryFg: string;
    mutedBg: string;
    mutedFg: string;
    gutter: string;
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
    modeNormal: string;
    modeVisual: string;
    modeInsert: string;
    fileType: Record<string, string>;
    highlights: ThemeHighlights;
};

export type WorktreeEntry = {
    id: number;
    name: string;
    path: string;
    expanded: boolean;
    kind: "file" | "dir";
    fileType: string;
    depth: number;
};

export type Mode = "normal" | "insert" | "visual";

export type ParsedKeymap = {
    mode: Mode;
    scope: string;
    cmd: string;
    sequence: string;
};

export type ParsedKeymaps = Record<string, Partial<Record<Mode, ParsedKeymap[]>>>;

export type KeymapMatch = {
    sequence: string;
};

export type KeyDownMods = {
    shift: boolean;
    alt: boolean;
    ctrl: boolean;
    super: boolean;
    hyper: boolean;
    meta: boolean;
    caps_lock: boolean;
    num_lock: boolean;
};

export type EditorSurface = {
    kind: "editor";
    gpuSurfaceId?: number;
    entry?: WorktreeEntry;
    surfaceState?: SurfaceState;
    editorState?: EditorState;
};

export type TerminalSurface = {
    kind: "terminal";
    cwd: string;
    gpuSurfaceId?: number;
    surfaceState?: SurfaceState;
};

export type Surface = EditorSurface | TerminalSurface;

export type SurfaceKind = Surface["kind"];

export type Tab = {
    id: number;
    name: string;
    surface: Surface;
};
