import { Electroview } from "electrobun/view";
import { AppEvents, AppState, BaseApp, Emitter } from "@ares/shared";
import type { Mode, Scope, KeymapBinding, KeyDownMods } from "@ares/shared";
import type { AppRPC } from "../../rpc.ts";

export class WebviewApp implements BaseApp {
    _state: AppState = { settings: null, theme: null, filetree: null, mode: "normal", keymaps: null }
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
                    filetreeUpdate: (filetree) => {
                        this._state = { ...this._state, filetree };
                        this.events.emit("filetreeUpdate");
                    },
                    modeUpdate: (mode) => {
                        this._state = { ...this._state, mode };
                        this.events.emit("modeUpdate");
                    },
                    keymapsUpdate: (keymaps) => {
                        this._state = { ...this._state, keymaps };
                        this.events.emit("keymapsUpdate");
                    },
                    keySequence: (sequence) => {
                        this.events.emit("keymapSequence", sequence);
                    }
                },
            },
        })
        ;
    async loadSettings() {
        this._state = await this.electroview.request.getState({})
    }

    selectEntry(id: number) {
        this.electroview.send("selectEntry", id)
    };

    setMode(mode: Mode) {
        if (this._state.mode === mode) return;
        this.electroview.send("setMode", mode);
    }

    readKeymaps(scope: Scope): KeymapBinding[] {
        return this._state.keymaps?.[scope] ?? [];
    }

    handleKeyDown(char: string, mods: KeyDownMods) {
        this.electroview.send("keyDown", { char, mods });
    }
}
