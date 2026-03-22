import type { RPCSchema } from "electrobun/bun";
import type { AppState, Settings, Theme, WorktreeEntry, ScopedKeymaps, Mode, View } from "@ares/shared";

export type GpuRect = { x: number; y: number; width: number; height: number };

export type AppRPC = {
    bun: RPCSchema<{
        requests: {
            getSettings: { params: {}; response: Settings },
            getTheme: { params: {}; response: Theme },
            getState: { params: {}; response: AppState };
            gitFileTree: { params: {}; response: WorktreeEntry[] }
            wgpuTagReady: { params: { id: number; rect: GpuRect; view: View }; response: { success: boolean } }
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
        };
    }>;
};
