import type { RPCSchema } from "electrobun/bun";
import type { AppState, Settings, Theme, WorktreeEntry, ScopedKeymaps, Mode, Surface } from "@ares/shared";

export type GpuRect = { x: number; y: number; width: number; height: number };

export type AppRPC = {
    bun: RPCSchema<{
        requests: {
            getSettings: { params: {}; response: Settings },
            getTheme: { params: {}; response: Theme },
            getState: { params: {}; response: AppState };
            gitFileTree: { params: {}; response: WorktreeEntry[] }
            gpuTagReady: { params: { id: number; rect: GpuRect; surface: Surface }; response: { success: boolean } }
        };
        messages: {
            setMode: Mode;
            expandEntry: number;
            selectSurfaceEntry: { surfaceId: number, id: number };
            surfaceScrollTo: { surfaceId: number, row: number };
            gpuTagRect: { id: number; rect: GpuRect };
            gpuTagStop: { id: number };
            gpuTagVisibility: { id: number; visible: boolean };
        };
    }>;
    webview: RPCSchema<{
        requests: {};
        messages: {
            settingsUpdate: Settings;
            themeUpdate: Theme;
            filetreeUpdate: WorktreeEntry[];
            keymapsUpdate: ScopedKeymaps;
        };
    }>;
};
