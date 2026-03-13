import type { RPCSchema } from "electrobun/bun";
import type { AppState, Settings, Theme, WorktreeEntry } from "@ares/shared";

export type AppRPC = {
    bun: RPCSchema<{
        requests: {
            getSettings: { params: {}; response: Settings },
            getTheme: { params: {}; response: Theme },
            getState: { params: {}; response: AppState };
            gitFileTree: { params: {}; response: WorktreeEntry[] }
            selectEntry: { params: { id: number }; response: {} };
        };
        messages: {};
    }>;
    webview: RPCSchema<{
        requests: {};
        messages: {
            settingsUpdate: Settings;
            themeUpdate: Theme;
            filetreeUpdate: WorktreeEntry[]
        };
    }>;
};
