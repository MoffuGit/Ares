import type { Color } from "@ares/tui-core/elements"

let internalId = 0

export function nextInternalId(): number {
    return --internalId
}

export function camelToSnake(str: string): string {
    return str.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`)
}

export function parseColor(value: unknown): Color {
    if (value == null) return { type: "default" }

    if (typeof value === "object" && "type" in (value as object)) {
        return value as Color
    }

    if (typeof value === "string") {
        const hex = value.startsWith("#") ? value.slice(1) : value

        if (hex.length === 6) {
            return {
                type: "rgb",
                r: parseInt(hex.slice(0, 2), 16),
                g: parseInt(hex.slice(2, 4), 16),
                b: parseInt(hex.slice(4, 6), 16),
            }
        }

        if (hex.length === 8) {
            return {
                type: "rgb",
                r: parseInt(hex.slice(0, 2), 16),
                g: parseInt(hex.slice(2, 4), 16),
                b: parseInt(hex.slice(4, 6), 16),
            }
        }
    }

    return { type: "default" }
}

export function log(...args: unknown[]): void {
    if (process.env.DEBUG) {
        console.log("[Reconciler]", ...args)
    }
}
