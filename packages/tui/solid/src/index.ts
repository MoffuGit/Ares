import { createRenderer } from "solid-js/universal";
import { Element, BoxElement, type BoxProps, type Style, type Color, type EventHandler } from "@ares/tui-core/elements";
import { TuiApp } from "@ares/tui-core/app";

// ---- Text node (lightweight wrapper for Solid text expressions) ----

export class TextNode {
    readonly _isTextNode = true;
    text: string;
    parent: Element | null = null;

    constructor(text: string) {
        this.text = typeof text === "number" ? String(text) : text;
    }
}

export type TuiNode = Element | TextNode;

function isTextNode(node: unknown): node is TextNode {
    return node instanceof TextNode;
}

// ---- Prop mapping helpers ----

function parseColor(value: unknown): Color | undefined {
    if (value == null) return undefined;
    if (typeof value === "object" && "type" in (value as object)) return value as Color;
    if (typeof value === "string") {
        const hex = value.replace("#", "");
        if (hex.length === 6) {
            return {
                type: "rgb",
                r: parseInt(hex.slice(0, 2), 16),
                g: parseInt(hex.slice(2, 4), 16),
                b: parseInt(hex.slice(4, 6), 16),
            };
        }
        if (hex.length === 8) {
            return {
                type: "rgba",
                r: parseInt(hex.slice(0, 2), 16),
                g: parseInt(hex.slice(2, 4), 16),
                b: parseInt(hex.slice(4, 6), 16),
                a: parseInt(hex.slice(6, 8), 16) / 255,
            };
        }
    }
    return undefined;
}

// Style prop names that map directly to our Style interface
const styleKeys = new Set<string>([
    "direction", "flexDirection", "justifyContent", "alignContent",
    "alignItems", "alignSelf", "positionType", "flexWrap", "overflow",
    "display", "boxSizing", "flex", "flexGrow", "flexShrink", "flexBasis",
    "width", "height", "minWidth", "minHeight", "maxWidth", "maxHeight",
    "aspectRatio",
]);

// Map camelCase JSX prop to snake_case Style key
function toSnakeCase(str: string): string {
    return str.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`);
}

function setBoxProperty(node: BoxElement, name: string, value: unknown, prev?: unknown): void {
    // Event handlers: on:click, on:keydown, etc.
    if (name.startsWith("on:")) {
        const eventName = name.slice(3);
        if (typeof prev === "function") node.off(eventName, prev as EventHandler);
        if (typeof value === "function") node.on(eventName, value as EventHandler);
        return;
    }

    // SolidJS on* convention: onClick, onKeydown, etc.
    if (name.startsWith("on") && name.length > 2 && name[2] === name[2]!.toUpperCase()) {
        const eventName = name.slice(2).toLowerCase();
        if (typeof prev === "function") node.off(eventName, prev as EventHandler);
        if (typeof value === "function") node.on(eventName, value as EventHandler);
        return;
    }

    switch (name) {
        case "bg":
        case "background": {
            const color = parseColor(value);
            if (color) node.setProps({ bg: color });
            break;
        }
        case "fg":
        case "color": {
            const color = parseColor(value);
            if (color) node.setProps({ fg: color });
            break;
        }
        case "opacity":
            node.setProps({ opacity: value as number });
            break;
        case "zIndex":
            node.setZIndex(value as number);
            break;
        case "rounded":
            node.setProps({ rounded: value as number });
            break;
        case "border":
            node.setProps({ border: value as BoxProps["border"] });
            break;
        case "shadow":
            node.setProps({ shadow: value as BoxProps["shadow"] });
            break;
        case "textAlign":
        case "text_align":
            node.setProps({ text_align: value as BoxProps["text_align"] });
            break;
        case "segments":
            node.setProps({ segments: value as BoxProps["segments"] });
            break;
        case "style":
            if (typeof value === "object" && value != null) {
                node.setStyle(value as Style);
            }
            break;
        case "padding":
            node.setStyle({ padding: value as Style["padding"] });
            break;
        case "margin":
            node.setStyle({ margin: value as Style["margin"] });
            break;
        case "gap":
            node.setStyle({ gap: value as Style["gap"] });
            break;
        case "position":
            node.setStyle({ position: value as Style["position"] });
            break;
        case "ref":
            if (typeof value === "function") {
                (value as (el: BoxElement) => void)(node);
            }
            break;
        case "children":
            // handled by Solid's insert mechanism
            break;
        default:
            // Try as a style shorthand
            if (styleKeys.has(name)) {
                node.setStyle({ [toSnakeCase(name)]: value } as unknown as Style);
            }
            break;
    }
}

// ---- Active app reference (set during render) ----
let activeApp: TuiApp | null = null;

// ---- Internal text children tracking ----
// We store text children separately since TextNode is not a real Element
const textChildrenMap = new WeakMap<Element, TuiNode[]>();

function getTextChildren(parent: Element): TuiNode[] {
    let list = textChildrenMap.get(parent);
    if (!list) {
        list = [];
        textChildrenMap.set(parent, list);
    }
    return list;
}

// ---- Create the Solid renderer ----

export const {
    render: _render,
    effect,
    memo,
    createComponent,
    createElement,
    createTextNode,
    insertNode,
    insert,
    spread,
    setProp,
    mergeProps,
    use,
} = createRenderer<TuiNode>({
    createElement(tag: string): TuiNode {
        let el: Element;
        switch (tag) {
            case "box":
            default:
                el = new BoxElement();
                break;
        }
        activeApp?.registerElement(el);
        return el;
    },

    createTextNode(value: string): TuiNode {
        return new TextNode(String(value));
    },

    isTextNode,

    replaceText(node: TuiNode, value: string): void {
        if (isTextNode(node)) {
            node.text = String(value);
            if (node.parent && node.parent instanceof BoxElement) {
                syncSegments(node.parent);
            }
        }
    },

    insertNode(parent: TuiNode, node: TuiNode, anchor?: TuiNode): void {
        if (isTextNode(parent)) return;
        const parentEl = parent as Element;

        if (isTextNode(node)) {
            node.parent = parentEl;
            const texts = getTextChildren(parentEl);
            if (anchor) {
                const idx = texts.indexOf(anchor);
                if (idx !== -1) {
                    texts.splice(idx, 0, node);
                } else {
                    texts.push(node);
                }
            } else {
                texts.push(node);
            }
            if (parentEl instanceof BoxElement) {
                syncSegments(parentEl);
            }
            return;
        }

        const childEl = node as Element;
        if (anchor && !isTextNode(anchor)) {
            parentEl.insertBefore(childEl, anchor as Element);
        } else {
            parentEl.appendChild(childEl);
        }
    },

    removeNode(parent: TuiNode, node: TuiNode): void {
        if (isTextNode(parent)) return;
        const parentEl = parent as Element;

        if (isTextNode(node)) {
            node.parent = null;
            const texts = getTextChildren(parentEl);
            const idx = texts.indexOf(node);
            if (idx !== -1) texts.splice(idx, 1);
            if (parentEl instanceof BoxElement) {
                syncSegments(parentEl);
            }
            return;
        }

        parentEl.removeChild(node as Element);
    },

    setProperty(node: TuiNode, name: string, value: unknown, prev?: unknown): void {
        if (isTextNode(node)) return;
        if (node instanceof BoxElement) {
            setBoxProperty(node, name, value, prev);
        }
    },

    getParentNode(node: TuiNode): TuiNode | undefined {
        if (isTextNode(node)) return node.parent ?? undefined;
        return (node as Element).parent ?? undefined;
    },

    getFirstChild(node: TuiNode): TuiNode | undefined {
        if (isTextNode(node)) return undefined;
        const el = node as Element;
        // Check text children first
        const texts = textChildrenMap.get(el);
        if (texts && texts.length > 0) return texts[0];
        return el.children[0];
    },

    getNextSibling(node: TuiNode): TuiNode | undefined {
        if (isTextNode(node)) {
            if (!node.parent) return undefined;
            const texts = getTextChildren(node.parent);
            const idx = texts.indexOf(node);
            if (idx !== -1 && idx < texts.length - 1) return texts[idx + 1];
            // After all text children, next is first Element child
            return node.parent.children[0];
        }
        const el = node as Element;
        if (!el.parent) return undefined;
        const siblings = el.parent.children;
        const idx = siblings.indexOf(el);
        if (idx !== -1 && idx < siblings.length - 1) return siblings[idx + 1];
        return undefined;
    },
});

function syncSegments(parent: BoxElement): void {
    const texts = textChildrenMap.get(parent);
    if (!texts || texts.length === 0) {
        parent.setProps({ segments: [] });
        return;
    }
    const segments = texts
        .filter(isTextNode)
        .map((t) => ({ text: t.text }));
    parent.setProps({ segments });
}

// ---- Public render function ----

export interface RenderOptions {
    app?: TuiApp;
    onDestroy?: () => void;
}

export function render(
    code: () => TuiNode,
    options: RenderOptions = {},
): () => void {
    const app = options.app ?? new TuiApp();
    activeApp = app;

    const root = new BoxElement();
    root.setStyle({ flex_grow: 1 });
    app.setRoot(root);

    const dispose = _render(code, root);

    app.flush();
    app.start();

    return () => {
        dispose();
        activeApp = null;
        app.destroy();
        options.onDestroy?.();
    };
}
