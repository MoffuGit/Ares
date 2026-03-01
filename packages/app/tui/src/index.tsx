import { render } from "@opentui/solid";
import { AppContext, useSettings, useTheme } from "@ares/shared/solid";
import { TuiApp } from "./app.ts";
import { resolve } from "node:path";

const settingsPath = resolve(import.meta.dir, "../../../settings");
const app = new TuiApp(settingsPath);

function App() {
    const settings = useSettings();
    const theme = useTheme();

    return (
        <box alignItems="center" justifyContent="center" flexGrow={1}>
            <box justifyContent="center" alignItems="flex-end">
                <ascii_font font="tiny" text="Ares" />
                <text>scheme: {settings()?.scheme ?? "loading..."}</text>
                <text>light: {settings()?.light_theme ?? "—"}</text>
                <text>dark: {settings()?.dark_theme ?? "—"}</text>
                <text>theme: {theme()?.name ?? "—"}</text>
                <text>fg: {theme()?.fg?.join(", ") ?? "—"}</text>
                <text>bg: {theme()?.bg?.join(", ") ?? "—"}</text>
                <text>primaryFg: {theme()?.primaryFg?.join(", ") ?? "—"}</text>
                <text>primaryBg: {theme()?.primaryBg?.join(", ") ?? "—"}</text>
                <text>mutedFg: {theme()?.mutedFg?.join(", ") ?? "—"}</text>
                <text>mutedBg: {theme()?.mutedBg?.join(", ") ?? "—"}</text>
                <text>scrollThumb: {theme()?.scrollThumb?.join(", ") ?? "—"}</text>
                <text>scrollTrack: {theme()?.scrollTrack?.join(", ") ?? "—"}</text>
                <text>border: {theme()?.border?.join(", ") ?? "—"}</text>
            </box>
        </box>
    );
}

app.start();

render(
    () => (
        <AppContext.Provider value={app}>
            <App />
        </AppContext.Provider>
    ),
    {
        onDestroy: () => {
            app.stop();
        },
    },
);
