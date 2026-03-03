import type { Theme } from "@ares/shared";

function rgbaToOklch(rgba: number[]): string {
    const [r, g, b] = rgba.map((v) => v / 255);

    // sRGB to linear RGB
    const toLinear = (c: number) =>
        c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    const lr = toLinear(r);
    const lg = toLinear(g);
    const lb = toLinear(b);

    // Linear RGB to XYZ (D65)
    const x = 0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb;
    const y = 0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb;
    const z = 0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb;

    // XYZ to Oklab
    const l_ = Math.cbrt(0.8189330101 * x + 0.3618667424 * y - 0.1288597137 * z);
    const m_ = Math.cbrt(0.0329845436 * x + 0.9293118715 * y + 0.0361456387 * z);
    const s_ = Math.cbrt(0.0482003018 * x + 0.2643662691 * y + 0.6338517070 * z);

    const okL = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
    const okA = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
    const okB = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;

    // Oklab to Oklch
    const C = Math.sqrt(okA * okA + okB * okB);
    const H = Math.atan2(okB, okA) * (180 / Math.PI);
    const hue = H < 0 ? H + 360 : H;

    const alpha = rgba.length >= 4 ? rgba[3] / 255 : 1;
    if (alpha < 1) {
        return `oklch(${okL.toFixed(3)} ${C.toFixed(3)} ${hue.toFixed(3)} / ${(alpha * 100).toFixed(0)}%)`;
    }
    return `oklch(${okL.toFixed(3)} ${C.toFixed(3)} ${hue.toFixed(3)})`;
}

const themeVarMap: Record<string, keyof Theme> = {
    "--background": "bg",
    "--foreground": "fg",
    "--primary": "primaryBg",
    "--primary-foreground": "primaryFg",
    "--muted": "mutedBg",
    "--muted-foreground": "mutedFg",
    "--border": "border",
    "--card": "bg",
    "--card-foreground": "fg",
    "--popover": "bg",
    "--popover-foreground": "fg",
    "--secondary": "mutedBg",
    "--secondary-foreground": "mutedFg",
    "--accent": "mutedBg",
    "--accent-foreground": "mutedFg",
    "--input": "border",
    "--ring": "primaryBg",
    "--sidebar": "mutedBg",
    "--sidebar-foreground": "fg",
    "--sidebar-primary": "primaryBg",
    "--sidebar-primary-foreground": "primaryFg",
    "--sidebar-accent": "mutedBg",
    "--sidebar-accent-foreground": "mutedFg",
    "--sidebar-border": "border",
    "--sidebar-ring": "primaryBg",
};

export function applyTheme(theme: Theme) {
    const root = document.documentElement;
    for (const [cssVar, themeKey] of Object.entries(themeVarMap)) {
        const rgba = theme[themeKey];
        if (Array.isArray(rgba)) {
            root.style.setProperty(cssVar, rgbaToOklch(rgba));
        }
    }
}
