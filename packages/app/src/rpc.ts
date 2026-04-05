import type { RPCSchema } from "electrobun/bun";
import type { Settings, Theme, WorktreeEntry, Surface, BufferState, Project, KeymapMatch, Mode } from "@ares/shared";

export type GpuRect = { x: number; y: number; width: number; height: number };

export type AppRPC = {
    bun: RPCSchema<{
        requests: {
            initialLoad: { params: {}; response: { settings: Settings, theme: Theme } },
            getTheme: { params: {}; response: Theme },
            openProjectDialog: { params: {}; response: Project | null };
            gitFileTree: { params: {}; response: WorktreeEntry[] }
            gpuTagReady: { params: { id: number; rect: GpuRect; surface: Surface }; response: { success: boolean } }
        };
        messages: {
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
            projectUpdate: Project | null;
            bufferUpdate: BufferState;
            modeUpdate: Mode;
            keymapMatch: KeymapMatch;
        };
    }>;
};
