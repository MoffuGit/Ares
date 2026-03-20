import type { RPCSchema } from "electrobun/bun";
import type { AppState, Settings, Theme, WorktreeEntry, ScopedKeymaps, Buffer, Mode } from "@ares/shared";

export type AppRPC = {
    bun: RPCSchema<{
        requests: {
            getSettings: { params: {}; response: Settings },
            getTheme: { params: {}; response: Theme },
            getState: { params: {}; response: AppState };
            gitFileTree: { params: {}; response: WorktreeEntry[] }
            readBuffer: { params: { id: number }, response: Buffer | null }
        };
        messages: {
            setMode: Mode;
            expandEntry: number;
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
