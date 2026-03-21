import type { RPCSchema } from "electrobun/bun";
import type { AppState, Settings, Theme, WorktreeEntry, ScopedKeymaps, Buffer, Mode } from "@ares/shared";

export type GpuRect = { x: number; y: number; width: number; height: number };

export type AppRPC = {
    bun: RPCSchema<{
        requests: {
            getSettings: { params: {}; response: Settings },
            getTheme: { params: {}; response: Theme },
            getState: { params: {}; response: AppState };
            gitFileTree: { params: {}; response: WorktreeEntry[] }
            readBuffer: { params: { id: number }, response: Buffer | null }
            wgpuTagReady: { params: { id: number; rect: GpuRect }; response: { success: boolean } }
        };
        messages: {
            setMode: Mode;
            expandEntry: number;
            wgpuTagRect: { id: number; rect: GpuRect };
        };
    }>;
    webview: RPCSchema<{
        requests: {};
        messages: {
            settingsUpdate: Settings;
            themeUpdate: Theme;
            filetreeUpdate: WorktreeEntry[];
            keymapsUpdate: ScopedKeymaps;
            bufferUpdate: Buffer;
        };
    }>;
};
