import type { RPCSchema } from "electrobun/bun";
import type { AppState, Settings, Theme, WorktreeEntry, Mode, ScopedKeymaps } from "@ares/shared";

export type AppRPC = {
    bun: RPCSchema<{
        requests: {
            getSettings: { params: {}; response: Settings },
            getTheme: { params: {}; response: Theme },
            getState: { params: {}; response: AppState };
            gitFileTree: { params: {}; response: WorktreeEntry[] }
        };
        messages: {
            selectEntry: number;
            setMode: Mode;
        };
    }>;
    webview: RPCSchema<{
        requests: {};
        messages: {
            settingsUpdate: Settings;
            themeUpdate: Theme;
            filetreeUpdate: WorktreeEntry[];
            modeUpdate: Mode;
            keymapsUpdate: ScopedKeymaps;
        };
    }>;
};
