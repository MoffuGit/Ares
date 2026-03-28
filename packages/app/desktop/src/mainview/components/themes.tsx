import { useEffect } from "react";
import { useAppStore } from "@/lib/app";
import { applyTheme } from "@/lib/theme";

export function Theme() {
    const theme = useAppStore((state) => state.theme);
    const settings = useAppStore((state) => state.settings);

    useEffect(() => {
        if (!theme || !settings) return;

        const scheme = settings.scheme === "system"
            ? (settings.system_scheme as "light" | "dark")
            : settings.scheme;

        applyTheme(theme, scheme);
    }, [settings, theme]);

    return null;
}
