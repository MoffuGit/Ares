import { Electroview } from "electrobun/view";
import { Emitter, type App, type AppEvents, type AppState } from "@ares/shared";
import type { AppRPC } from "../../rpc.ts";

export class WebviewApp implements App {
    readonly events = new Emitter<AppEvents>();

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
    private _state: AppState = { settings: null, theme: null };

    get state(): AppState {
        return this._state;
    }

    async loadSettings() {
        this._state = await this.electroview.request.getState({})
    }
}
