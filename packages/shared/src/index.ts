import type { Settings, SidebarKind, Surface } from "./types.ts";

export type * from "./types.ts";

export function surfaceName(surface: Surface): string {
    switch (surface.kind) {
        case "editor": return surface.entry?.path.split("/").pop() ?? "[No Name]";
        case "terminal": return "terminal";
    }
}

export function canUseSidebarKind(settings: Settings, sidebarKind: SidebarKind): boolean {
    if (sidebarKind == "tabs") return settings?.tabs_position === "vertical";
    return true
}
