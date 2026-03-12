import { BrowserView, BrowserWindow, Updater, Utils } from "electrobun/bun";
import { resolve } from "path";
import { DesktopApp } from "./app.ts";
import { AppRPC } from "src/rpc.ts";

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
const app = new DesktopApp(settingsPath, projectPath, libPath);

const url = await getMainViewUrl();

const rpc = BrowserView.defineRPC<AppRPC>({
    maxRequestTime: 5000,
    handlers: {
        requests: {
            getState: ({ }) => app._state,
        },
        messages: {},
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
    rpc: rpc,
});

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

mainWindow.webview.on("dom-ready", () => {
    setInterval(() => {
        app.drainMailbox()
    }, 100);
});

mainWindow.on("close", () => {
    app.stop();
    Utils.quit();
});

console.log("Ares desktop app started!");
