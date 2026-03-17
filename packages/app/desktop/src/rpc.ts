import type { RPCSchema } from "electrobun/bun";
import type { AppState, Settings, Theme, WorktreeEntry, Mode, ScopedKeymaps, KeyDownMods } from "@ares/shared";

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
            keyDown: { char: string, mods: KeyDownMods }
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
            keySequence: string,
        };
    }>;
};
