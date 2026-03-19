import { Electroview } from "electrobun/view";
import { AppEvents, AppState, BaseApp, Emitter, KeymapHandler, buildKeymapTrie, edgeKey } from "@ares/shared";
import type { Mode, Scope, KeymapBinding, KeyDownMods, ScopedKeymaps, Buffer } from "@ares/shared";
import type { AppRPC } from "../../rpc.ts";
import type { TSTrieNode } from "@ares/shared";

export class WebviewApp implements BaseApp {
    _state: AppState = { settings: null, theme: null, filetree: null, mode: "normal", keymaps: null }
    events = new Emitter<AppEvents>;

    private trieRoot: TSTrieNode | null = null;
    private keymapHandler = new KeymapHandler<TSTrieNode>(this);

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
                        this.trieRoot = null;
                        this.events.emit("modeUpdate");
                    },
                    keymapsUpdate: (keymaps) => {
                        this._state = { ...this._state, keymaps };
                        this.rebuildTrie(keymaps);
                        this.events.emit("keymapsUpdate");
                    },
                },
            },
        })
        ;

    async loadSettings() {
        this._state = await this.electroview.request.getState({})
        this.rebuildTrie(this._state.keymaps);
    }

    expandEntry(id: number) {
        this.electroview.send("expandEntry", id)
    };

    setMode(mode: Mode) {
        if (this._state.mode === mode) return;
        this.electroview.send("setMode", mode);
    }

    readKeymaps(scope: Scope): KeymapBinding[] {
        return this._state.keymaps?.[scope] ?? [];
    }

    handleKeyDown(char: string | number, mods: KeyDownMods): boolean {
        return this.keymapHandler.handleKeyDown(char, mods);
    }

    getTrieRoot(_mode: Mode): TSTrieNode | null {
        return this.trieRoot;
    }

    readBuffer(id: number): Buffer | null {
        this.electroview.request("readBuffer", { id }).then((buffer) => {
            if (buffer) {
                console.log(buffer.state);
            }
        });
        return {
            state: "empty"
        }
    }

    trieStep(node: TSTrieNode, codepoint: number, mods: number): TSTrieNode | null {
        return node.children.get(edgeKey(codepoint, mods)) ?? null;
    }

    trieNodeIsTerminal(node: TSTrieNode): boolean {
        return node.terminal;
    }

    trieNodeHasChildren(node: TSTrieNode): boolean {
        return node.children.size > 0;
    }

    private rebuildTrie(keymaps: ScopedKeymaps | null): void {
        this.trieRoot = buildKeymapTrie(keymaps);
    }
}
