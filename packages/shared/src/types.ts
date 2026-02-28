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
}
