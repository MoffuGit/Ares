import { Electroview } from "electrobun/view";
import { BaseApp } from "@ares/shared";
import type { AppRPC } from "../../rpc.ts";

export class WebviewApp extends BaseApp {
    electroview =
        Electroview.defineRPC<AppRPC>({
            handlers: {
                requests: {},
                messages: {
                    settingsUpdate: (settings) => {
                        console.log("received settings", settings);
                        this._state = { ...this._state, settings };
                        this.events.emit("settingsUpdate");
                    },
                    themeUpdate: (theme) => {
                        this._state = { ...this._state, theme };
                        this.events.emit("themeUpdate");
                    },
                    worktreeUpdate: (worktree) => {
                        console.log("worktree update");
                        this._state = { ...this._state, worktree };
                        this.events.emit("worktreeUpdate");
                    },
                },
            },
        })
        ;
    async loadSettings() {
        this._state = await this.electroview.request.getState({})
    }
}
