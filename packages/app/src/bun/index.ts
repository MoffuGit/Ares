import { App } from "@ares/core";
import { Project } from "@ares/shared";
import { BrowserView, BrowserWindow, Updater, Utils } from "electrobun/bun";
import { homedir } from "os";
import { join, resolve, basename } from "path";
import { AppRPC } from "src/rpc.ts";
import { SurfaceStore } from "./SurfaceStore";

const MAC_TRAFFIC_LIGHTS_X = 12;
const MAC_TRAFFIC_LIGHTS_Y = 10;

const DEV_SERVER_PORT = 5173;
const DEV_SERVER_URL = `http://localhost:${DEV_SERVER_PORT}`;

const libPath = resolve(import.meta.dir, "../lib/libcore.dylib");
const settingsPath = resolve(import.meta.dir, "../../../../../../../../../settings/");

const app = new App(settingsPath, libPath);
const surfaceStore = new SurfaceStore(app);

async function getMainSurfaceUrl(): Promise<string> {
    const channel = await Updater.localInfo.channel();
    if (channel === "dev") {
        try {
            await fetch(DEV_SERVER_URL, { method: "HEAD" });
            console.log(`HMR enabled: Using Vite dev server at ${DEV_SERVER_URL}`);
            return DEV_SERVER_URL;
        } catch {
            console.log(
                "Vite dev server not running. Run 'bun run dev:hmr' for HMR support.",
            );
        }
    }
    return "views://mainview/index.html";
}


const rpc = BrowserView.defineRPC<AppRPC>({
    maxRequestTime: 600000,
    handlers: {
        requests: {
            initialLoad: () => {
                return {
                    settings: app.readSettings(),
                    theme: app.readTheme(),
                }
            },
            openProjectDialog: async () => {
                const chosenPaths = await Utils.openFileDialog({
                    startingFolder: join(homedir(), "Desktop"),
                    allowedFileTypes: "*",
                    canChooseFiles: false,
                    canChooseDirectory: true,
                    allowsMultipleSelection: false,
                });

                const projectPath = chosenPaths?.[0];
                if (!projectPath) return null;

                app.openProject(projectPath);
                const name = basename(projectPath) || projectPath;
                const project: Project = { name, path: projectPath };

                return project;
            },
            gpuTagReady: ({ id, rect, surface }) => {
                try {
                    surfaceStore.start(id, mainWindow, rect, surface);
                    const surfaceState = surfaceStore.readSurfaceState(id);
                    if (surfaceState) {
                        mainWindow.webview.rpc?.send.surfaceUpdate({ surfaceId: id, state: surfaceState });
                    }
                    if (surface.kind === "editor") {
                        mainWindow.webview.rpc?.send.editorStateUpdate({ surfaceId: id, state: surfaceStore.readEditorState(id) });
                    }
                    return { success: true };
                } catch (err: any) {
                    console.error(`Metal renderer start failed: ${String(err?.message ?? err)}`);
                    return { success: false };
                }
            },
        },
        messages: {
            expandEntry: (id) => { app.expandEntry(id) },
            selectSurfaceEntry: ({ surfaceId, id }) => {
                surfaceStore.selectSurfaceEntry(surfaceId, id);
            },
            surfaceScrollTo: ({ surfaceId, row }) => {
                surfaceStore.surfaceScrollTo(surfaceId, row);
            },
            surfaceMouseEvent: (event) => {
                surfaceStore.surfaceMouseEvent(event.surfaceId, event.type, event.x, event.y, event.button, event.mods);
            },
            gpuTagRect: ({ id, rect }) => {
                surfaceStore.updateRect(id, rect);
            },
            gpuTagStop: ({ id }) => {
                surfaceStore.stop(id);
            },
            gpuTagVisibility: ({ id, visible }) => {
                surfaceStore.setVisibility(id, visible);
            },
        },
    },
});

const url = await getMainSurfaceUrl();
const mainWindow = new BrowserWindow({
    titleBarStyle: "hiddenInset",
    title: "Ares",
    url,
    frame: {
        width: 900,
        height: 700,
        x: 200,
        y: 200,
    },
    transparent: false,
    rpc: rpc,
});

mainWindow.setWindowButtonPosition(MAC_TRAFFIC_LIGHTS_X, MAC_TRAFFIC_LIGHTS_Y);

app.core.on("SettingsUpdate", () => {
    mainWindow.webview.rpc?.send.settingsUpdate(app.readSettings())
    mainWindow.webview.rpc?.send.themeUpdate(app.readTheme())
});

app.core.on("ThemeUpdate", () => {
    mainWindow.webview.rpc?.send.themeUpdate(app.readTheme());
});

app.core.on("FiletreeUpdate", () => {
    const fileTree = app.readFileTree();
    if (!fileTree) return;
    mainWindow.webview.rpc?.send.filetreeUpdate(fileTree);
});

app.core.on("SurfaceUpdate", () => {
    for (const update of surfaceStore.readAllSurfaceStates()) {
        mainWindow.webview.rpc?.send.surfaceUpdate(update);
    }
});

app.core.on("BufferUpdate", () => {
    for (const update of surfaceStore.readAllEditorStates()) {
        mainWindow.webview.rpc?.send.editorStateUpdate(update);
    }
});

app.core.on("ModeUpdate", ({ mode }) => {
    mainWindow.webview.rpc?.send.modeUpdate(mode);
});

app.core.on("KeymapMatch", (match) => {
    mainWindow.webview.rpc?.send.keymapMatch(match);
});

mainWindow.on("keyDown", (event: any) => {
    const data = event.data;
    if (!data) return;

    if (app.onKeyDown(data)) {
        event.preventDefault();
        //HACK:
        //If we wait for the interval callback
        //the keymaps become kinda slow,
        //because almost every keydown that is consumed produce
        //a sequence this work fine
        app.core.drainMailbox();
    }
});

mainWindow.webview.on("dom-ready", () => {
    setInterval(() => {
        app.core.drainMailbox()
    }, 100);
});

mainWindow.on("close", () => {
    surfaceStore.stopAll();
    app.destroy();
    Utils.quit();
});
