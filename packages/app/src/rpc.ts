import type { RPCSchema } from "electrobun/bun";
import type { Settings, Theme, WorktreeEntry, Surface, SurfaceState, EditorState, Project, KeymapMatch, Mode } from "@ares/shared";

export type GpuRect = { x: number; y: number; width: number; height: number };

export type AppRPC = {
    bun: RPCSchema<{
        requests: {
            initialLoad: { params: {}; response: { settings: Settings, theme: Theme, mode: Mode } },
            getTheme: { params: {}; response: Theme },
            openProjectDialog: { params: {}; response: Project | null };
            gitFileTree: { params: {}; response: WorktreeEntry[] }
            gpuTagReady: { params: { id: number; rect: GpuRect; surface: Surface }; response: { success: boolean } }
        };
        messages: {
            expandEntry: number;
            selectSurfaceEntry: { surfaceId: number, id: number };
            surfaceScrollTo: { surfaceId: number, row: number };
            setEditorCursorPosition: { surfaceId: number, row: number, col: number };
            surfaceMouseEvent: { surfaceId: number; type: "mousedown" | "mousemove" | "mouseup"; x: number; y: number; button: number; mods: number };
            gpuTagRect: { id: number; rect: GpuRect };
            gpuTagStop: { id: number };
            gpuTagVisibility: { id: number; visible: boolean };
            surfaceKeyEvent: { id: number, key: string, code: string, mods: number, repeat: boolean };
            setMode: Mode;
        };
    }>;
    webview: RPCSchema<{
        requests: {};
        messages: {
            settingsUpdate: Settings;
            themeUpdate: Theme;
            filetreeUpdate: WorktreeEntry[];
            projectUpdate: Project | null;
            surfaceUpdate: { surfaceId: number; state: SurfaceState };
            editorStateUpdate: { surfaceId: number; state: EditorState | null };
            modeUpdate: Mode;
            keymapMatch: KeymapMatch;
        };
    }>;
};
