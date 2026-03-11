import { render, useKeydown } from "@ares/tui-solid";
import { AppContext, useSettings, useTheme } from "@ares/shared/solid";
import { TuiApp } from "./app.ts";
import { resolve } from "node:path";

const settingsPath = resolve(import.meta.dir, "../../../../settings");
const bizApp = new TuiApp(settingsPath);
bizApp.start();

function Line(props: { children: any }) {
    return (
        <box width={{ percent: 40 }} height={{ point: 1 }} bg="#1a1a2e" fg="#e0e0e0">
            {props.children}
        </box>
    );
}

function App() {
    const settings = useSettings();
    const theme = useTheme();

    useKeydown((event) => {
        const data = event.data as { codepoint: number; mods: number };
        if (data.codepoint === 99 && (data.mods & 4) !== 0) {
            bizApp.stop();
            process.exit(0);
        }
    });

    return (
        <box bg="#1a1a2e" fg="#e0e0e0" alignItems="center" justifyContent="center" flexGrow={1}>
            <box flexDirection="column" alignItems="center" width={{ percent: 100 }} bg="#1a1a2e" fg="#e0e0e0">
                <Line>Ares</Line>
                <Line>scheme: {settings()?.scheme ?? "loading..."}</Line>
                <Line>light: {settings()?.light_theme ?? "—"}</Line>
                <Line>dark: {settings()?.dark_theme ?? "—"}</Line>
                <Line>theme: {theme()?.name ?? "—"}</Line>
                <Line>fg: {theme()?.fg?.join(", ") ?? "—"}</Line>
                <Line>bg: {theme()?.bg?.join(", ") ?? "—"}</Line>
                <Line>primaryFg: {theme()?.primaryFg?.join(", ") ?? "—"}</Line>
                <Line>primaryBg: {theme()?.primaryBg?.join(", ") ?? "—"}</Line>
                <Line>mutedFg: {theme()?.mutedFg?.join(", ") ?? "—"}</Line>
                <Line>mutedBg: {theme()?.mutedBg?.join(", ") ?? "—"}</Line>
                <Line>scrollThumb: {theme()?.scrollThumb?.join(", ") ?? "—"}</Line>
                <Line>scrollTrack: {theme()?.scrollTrack?.join(", ") ?? "—"}</Line>
                <Line>border: {theme()?.border?.join(", ") ?? "—"}</Line>
            </box>
        </box>
    );
}

const { dispose } = render(() => (
    <AppContext.Provider value={bizApp}>
        <App />
    </AppContext.Provider>
));
