import { Electroview } from "electrobun/view";
import { AppEvents, AppState, BaseApp, Emitter } from "@ares/shared";
import type { AppRPC } from "../../rpc.ts";

export class WebviewApp implements BaseApp {
    _state: AppState = { settings: null, theme: null }
    events = new Emitter<AppEvents>;

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
                },
            },
        })
        ;
    async loadSettings() {
        this._state = await this.electroview.request.getState({})
    }
}
