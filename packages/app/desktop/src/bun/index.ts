import { App } from "../../../shared/src/app/index.ts";
import { BrowserView, BrowserWindow, Updater, Utils } from "electrobun/bun";
import { resolve } from "path";
import { AppRPC } from "src/rpc.ts";
import { ViewStore } from "./ViewStore.ts";

const DEV_SERVER_PORT = 5173;
const DEV_SERVER_URL = `http://localhost:${DEV_SERVER_PORT}`;

async function getMainViewUrl(): Promise<string> {
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
const projectPath = "/Volumes/Home_SSD/Users/home/Documents/projects/ares";

const app = new App(settingsPath, libPath);
app.openProject(projectPath);

const url = await getMainViewUrl();
const metalRenderer = new ViewStore(app.core);

const rpc = BrowserView.defineRPC<AppRPC>({
    maxRequestTime: 5000,
    handlers: {
        requests: {
            getState: ({ }) => app._state,
            gpuTagReady: ({ id, rect, view }) => {
                try {
                    metalRenderer.start(id, mainWindow, rect, view);
                    return { success: true };
                } catch (err: any) {
                    console.error(`Metal renderer start failed: ${String(err?.message ?? err)}`);
                    return { success: false };
                }
            },
        },
        messages: {
            expandEntry: (id) => { app.expandEntry(id) },
            setMode: (mode) => app.setMode(mode),
            gpuTagRect: ({ id, rect }) => {
                metalRenderer.updateRect(id, rect);
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

app.on("keymapsUpdate", () => {
    if (app._state.keymaps) {
        mainWindow.webview.rpc?.send.keymapsUpdate(app._state.keymaps);
    }
});

mainWindow.webview.on("dom-ready", () => {
    setInterval(() => {
        app.drainMailbox()
    }, 100);
});

mainWindow.on("close", () => {
    metalRenderer.stopAll();
    app.stop();
    Utils.quit();
});

console.log("Ares desktop app started!");
