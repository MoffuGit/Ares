import { useSettings, useTheme } from "@ares/shared/react";

function App() {
    const settings = useSettings();
    const theme = useTheme();

    return (
        <div className="flex items-center justify-center min-h-screen">
            <div className="flex flex-col items-end gap-1 font-mono text-sm">
                <p>scheme: {settings?.scheme ?? "loading..."}</p>
                <p>light: {settings?.light_theme ?? "—"}</p>
                <p>dark: {settings?.dark_theme ?? "—"}</p>
                <p>theme: {theme?.name ?? "—"}</p>
                <p>fg: {theme?.fg?.join(", ") ?? "—"}</p>
                <p>bg: {theme?.bg?.join(", ") ?? "—"}</p>
                <p>primaryFg: {theme?.primaryFg?.join(", ") ?? "—"}</p>
                <p>primaryBg: {theme?.primaryBg?.join(", ") ?? "—"}</p>
                <p>mutedFg: {theme?.mutedFg?.join(", ") ?? "—"}</p>
                <p>mutedBg: {theme?.mutedBg?.join(", ") ?? "—"}</p>
                <p>scrollThumb: {theme?.scrollThumb?.join(", ") ?? "—"}</p>
                <p>scrollTrack: {theme?.scrollTrack?.join(", ") ?? "—"}</p>
                <p>border: {theme?.border?.join(", ") ?? "—"}</p>
            </div>
        </div>
    );
}

export default App;
