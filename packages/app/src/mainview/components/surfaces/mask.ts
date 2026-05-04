export interface RootMaskHoleRect {
    x: number;
    y: number;
    width: number;
    height: number;
}

const holes = new Map<string | number, RootMaskHoleRect>();

const MASK_PROPS = [
    "mask-image",
    "mask-position",
    "mask-size",
    "mask-repeat",
    "mask-composite",
    "-webkit-mask-image",
    "-webkit-mask-position",
    "-webkit-mask-size",
    "-webkit-mask-repeat",
    "-webkit-mask-composite",
] as const;

function snap(v: number): number {
    const dpr = window.devicePixelRatio || 1;
    return Math.round(v * dpr) / dpr;
}

function snapRect(rect: RootMaskHoleRect): RootMaskHoleRect {
    return {
        x: snap(rect.x),
        y: snap(rect.y),
        width: snap(rect.width),
        height: snap(rect.height),
    };
}

function rectsEqual(a: RootMaskHoleRect, b: RootMaskHoleRect): boolean {
    return a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height;
}

function applyMask(): void {
    const root = document.getElementById("root");
    if (!root) return;

    const live = Array.from(holes.values()).filter((r) => r.width > 0 && r.height > 0);

    if (live.length === 0) {
        for (const prop of MASK_PROPS) {
            root.style.removeProperty(prop);
        }
        return;
    }

    const black = "linear-gradient(#000, #000)";
    const layerCount = live.length + 1;

    const images = Array(layerCount).fill(black).join(", ");
    const positions = ["0 0", ...live.map((r) => `${r.x}px ${r.y}px`)].join(", ");
    const sizes = ["100% 100%", ...live.map((r) => `${r.width}px ${r.height}px`)].join(", ");
    const repeats = Array(layerCount).fill("no-repeat").join(", ");
    const stdComposite = Array(live.length).fill("exclude").join(", ");
    const webkitComposite = Array(live.length).fill("xor").join(", ");

    root.style.setProperty("mask-image", images);
    root.style.setProperty("mask-position", positions);
    root.style.setProperty("mask-size", sizes);
    root.style.setProperty("mask-repeat", repeats);
    root.style.setProperty("mask-composite", stdComposite);
    root.style.setProperty("-webkit-mask-image", images);
    root.style.setProperty("-webkit-mask-position", positions);
    root.style.setProperty("-webkit-mask-size", sizes);
    root.style.setProperty("-webkit-mask-repeat", repeats);
    root.style.setProperty("-webkit-mask-composite", webkitComposite);
}

export function upsertRootMaskHole(key: string | number, rect: RootMaskHoleRect): void {
    const snapped = snapRect(rect);
    const prev = holes.get(key);
    if (prev && rectsEqual(prev, snapped)) return;
    holes.set(key, snapped);
    applyMask();
}

export function removeRootMaskHole(key: string | number): void {
    if (!holes.has(key)) return;
    holes.delete(key);
    applyMask();
}
