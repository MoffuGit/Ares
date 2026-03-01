import type { RPCSchema } from "electrobun/bun";
import type { AppState, Settings, Theme } from "@ares/shared";

export type AppRPC = {
    bun: RPCSchema<{
        requests: {
            getState: { params: {}; response: AppState };
        };
        messages: {};
    }>;
    webview: RPCSchema<{
        requests: {};
        messages: {
            settingsUpdate: Settings;
            themeUpdate: Theme;
        };
    }>;
};
