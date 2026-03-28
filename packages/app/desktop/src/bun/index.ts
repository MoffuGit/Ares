import { App } from "../../../shared/src/app/index.ts";
import { BrowserView, BrowserWindow, Updater, Utils } from "electrobun/bun";
import { homedir } from "os";
import { join, resolve } from "path";
import { AppRPC } from "src/rpc.ts";
import { SurfaceStore } from "./SurfaceStore.ts";

const DEV_SERVER_PORT = 5173;
const DEV_SERVER_URL = `http://localhost:${DEV_SERVER_PORT}`;

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

const settingsPath = resolve(import.meta.dir, "../../../../../../../../../../settings/");
const libPath = resolve(import.meta.dir, "../lib/libcore.dylib");

const app = new App(settingsPath, libPath);

const url = await getMainSurfaceUrl();
const surfaceStore = new SurfaceStore();

const rpc = BrowserView.defineRPC<AppRPC>({
    maxRequestTime: 600000,
    handlers: {
        requests: {
            getState: ({ }) => app._state,
            openProjectDialog: async ({ }) => {
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
                return app._state.project;
            },
            gpuTagReady: ({ id, rect, surface }) => {
                try {
                    surfaceStore.start(app, id, mainWindow, rect, surface);
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
                surfaceStore.selectSurfaceEntry(app, surfaceId, id);
            },
            surfaceScrollTo: ({ surfaceId, row }) => {
                surfaceStore.surfaceScrollTo(app, surfaceId, row);
            },
            setMode: (mode) => app.setMode(mode),
            gpuTagRect: ({ id, rect }) => {
                surfaceStore.updateRect(app, id, rect);
            },
            gpuTagStop: ({ id }) => {
                surfaceStore.stop(app, id);
            },
            gpuTagVisibility: ({ id, visible }) => {
                surfaceStore.setVisibility(app, id, visible);
            },
        },
    },
});


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
    transparent: true,
    rpc: rpc,
});

const alignButtons = () =>
    app.setWindowTrafficLightPosition(
        mainWindow.ptr,
    );


alignButtons();
mainWindow.on("resize", alignButtons);

app.start();

app.on("settingsUpdate", () => {
    if (app._state.settings) {
        console.log("sending new settings:", app._state.settings);
        mainWindow.webview.rpc?.send.settingsUpdate(app._state.settings)
    }
    if (app._state.theme) {
        mainWindow.webview.rpc?.send.themeUpdate(app._state.theme)
    }
});

app.on("themeUpdate", () => {
    if (app._state.theme) {
        mainWindow.webview.rpc?.send.themeUpdate(app._state.theme)
    }
});

app.on("filetreeUpdate", () => {
    if (app._state.filetree) {
        mainWindow.webview.rpc?.send.filetreeUpdate(app._state.filetree);
    }
});

app.on("projectUpdate", (project) => {
    mainWindow.webview.rpc?.send.projectUpdate(project);
});

app.on("keymapsUpdate", () => {
    if (app._state.keymaps) {
        mainWindow.webview.rpc?.send.keymapsUpdate(app._state.keymaps);
    }
});

app.on("bufferUpdate", (state) => {
    mainWindow.webview.rpc?.send.bufferUpdate(state);
});

mainWindow.webview.on("dom-ready", () => {
    setInterval(() => {
        app.drainMailbox()
    }, 100);
});

mainWindow.on("close", () => {
    surfaceStore.stopAll(app);
    app.stop();
    Utils.quit();
});

console.log("Ares desktop app started!");
