import { createCliRenderer } from "@opentui/core";
import { createRoot } from "@opentui/react";
import { AresProvider, useSettings } from "@ares/shared/react";
import { TuiApp } from "./app.ts";
import { resolve } from "node:path";

const settingsPath = resolve(import.meta.dir, "../../../settings/settings.json");
const app = new TuiApp(settingsPath);

function App() {
    const settings = useSettings();

    return (
        <box alignItems="center" justifyContent="center" flexGrow={1}>
            <box justifyContent="center" alignItems="flex-end">
                <ascii-font font="tiny" text="Ares" />
                <text>scheme: {settings?.scheme ?? "loading..."}</text>
                <text>light: {settings?.light_theme ?? "—"}</text>
                <text>dark: {settings?.dark_theme ?? "—"}</text>
            </box>
        </box>
    );
}

app.start();

const renderer = await createCliRenderer();
createRoot(renderer).render(
    <AresProvider app={app}>
        <App />
    </AresProvider>,
);
