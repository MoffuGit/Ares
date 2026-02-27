export type ColorScheme = "light" | "dark" | "system";

export type SettingsDTO = {
  scheme: ColorScheme;
  light_theme: string;
  dark_theme: string;
};

export type BackendEvent = "settings:update";
