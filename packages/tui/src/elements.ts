export type StyleValue =
    | "undefined"
    | "auto"
    | "max_content"
    | "fit_content"
    | "stretch"
    | { point: number }
    | { percent: number };

export type Direction = "inherit" | "ltr" | "rtl";
export type FlexDirection = "column" | "column_reverse" | "row" | "row_reverse";
export type JustifyContent = "flex_start" | "center" | "flex_end" | "space_between" | "space_around" | "space_evenly";
export type AlignValue = "auto" | "flex_start" | "center" | "flex_end" | "stretch" | "baseline" | "space_between" | "space_around" | "space_evenly";
export type PositionType = "static" | "relative" | "absolute";
export type FlexWrap = "no_wrap" | "wrap" | "wrap_reverse";
export type Overflow = "visible" | "hidden" | "scroll";
export type Display = "flex" | "none" | "contents";
export type BoxSizing = "border_box" | "content_box";
export type TextAlign = "left" | "center" | "right" | "justify";

export interface Edges {
    left?: StyleValue;
    top?: StyleValue;
    right?: StyleValue;
    bottom?: StyleValue;
    start?: StyleValue;
    end?: StyleValue;
    horizontal?: StyleValue;
    vertical?: StyleValue;
    all?: StyleValue;
}

export interface BorderEdges {
    left?: number;
    top?: number;
    right?: number;
    bottom?: number;
    start?: number;
    end?: number;
    horizontal?: number;
    vertical?: number;
    all?: number;
}

export interface Gap {
    column?: StyleValue;
    row?: StyleValue;
    all?: StyleValue;
}

export interface Style {
    direction?: Direction;
    flex_direction?: FlexDirection;
    justify_content?: JustifyContent;
    align_content?: AlignValue;
    align_items?: AlignValue;
    align_self?: AlignValue;
    position_type?: PositionType;
    flex_wrap?: FlexWrap;
    overflow?: Overflow;
    display?: Display;
    box_sizing?: BoxSizing;

    flex?: number;
    flex_grow?: number;
    flex_shrink?: number;
    flex_basis?: StyleValue;

    position?: Edges;
    margin?: Edges;
    padding?: Edges;
    border?: BorderEdges;

    gap?: Gap;

    width?: StyleValue;
    height?: StyleValue;
    min_width?: StyleValue;
    min_height?: StyleValue;
    max_width?: StyleValue;
    max_height?: StyleValue;

    aspect_ratio?: number;
}

// ---- Color ----

export type Color =
    | { type: "default" }
    | { type: "rgba"; r: number; g: number; b: number; a: number }
    | { type: "rgb"; r: number; g: number; b: number };

// ---- Segment (for text rendering) ----

export interface Segment {
    text: string;
    style?: {
        fg?: Color;
        bg?: Color;
        bold?: boolean;
        italic?: boolean;
        underline?: boolean;
        strikethrough?: boolean;
    };
}

// ---- Wire command type (JSON objects sent to Zig) ----

export type ElementType = "box";
export type WireCommand = Record<string, unknown>;

// ---- Event handler types ----

export type EventHandler = (event: ElementEvent) => void;

export interface ElementEvent {
    type: string;
    target: Element;
    currentTarget: Element;
    data: unknown;
    stopped: boolean;
    stopPropagation(): void;
}

// ---- ID generation ----

let nextId = 1;

function allocId(): number {
    return nextId++;
}

// ---- Mutation queue ----

const mutationQueue: WireCommand[] = [];

export function enqueue(cmd: WireCommand): void {
    mutationQueue.push(cmd);
}

export function drainMutations(): WireCommand[] {
    const batch = mutationQueue.slice();
    mutationQueue.length = 0;
    return batch;
}

// ---- Base Element ----

export class Element {
    readonly id: number;
    readonly elementType: ElementType;

    parent: Element | null = null;
    children: Element[] = [];

    private handlers: Map<string, EventHandler[]> = new Map();

    zIndex: number = 0;
    style: Style = {};

    constructor(elementType: ElementType) {
        this.id = allocId();
        this.elementType = elementType;

        enqueue({ cmd: "create", id: this.id, element_type: elementType });
    }

    // ---- Children ----

    appendChild(child: Element): void {
        child.parent?.removeChild(child);
        child.parent = this;
        this.children.push(child);

        enqueue({ cmd: "append_child", id: this.id, child_id: child.id });
    }

    insertBefore(child: Element, before: Element): void {
        child.parent?.removeChild(child);
        child.parent = this;

        const idx = this.children.indexOf(before);
        if (idx === -1) {
            this.children.push(child);
        } else {
            this.children.splice(idx, 0, child);
        }

        enqueue({ cmd: "insert_before", id: this.id, child_id: child.id, before_id: before.id });
    }

    removeChild(child: Element): void {
        const idx = this.children.indexOf(child);
        if (idx === -1) return;

        this.children.splice(idx, 1);
        child.parent = null;

        enqueue({ cmd: "remove_child", id: this.id, child_id: child.id });
    }

    // ---- Deletion ----

    delete(): void {
        this.parent?.removeChild(this);
        enqueue({ cmd: "delete", id: this.id });
    }

    // ---- Props ----

    setStyle(style: Style): void {
        this.style = { ...this.style, ...style };
        this.enqueueSetProps({ style });
    }

    setZIndex(z: number): void {
        this.zIndex = z;
        this.enqueueSetProps({ zIndex: z });
    }

    protected enqueueSetProps(props: object): void {
        enqueue({ cmd: "set_props", id: this.id, props });
    }

    // ---- Events (TS-side propagation) ----

    on(eventName: string, handler: EventHandler): void {
        let list = this.handlers.get(eventName);
        if (!list) {
            list = [];
            this.handlers.set(eventName, list);
        }
        list.push(handler);
    }

    off(eventName: string, handler: EventHandler): void {
        const list = this.handlers.get(eventName);
        if (!list) return;
        const idx = list.indexOf(handler);
        if (idx !== -1) list.splice(idx, 1);
    }

    dispatchEvent(event: ElementEvent): void {
        // Build path from root to this element
        const path: Element[] = [];
        let current: Element | null = this;
        while (current) {
            path.unshift(current);
            current = current.parent;
        }

        // Capture phase (root → target, excluding target)
        for (let i = 0; i < path.length - 1; i++) {
            if (event.stopped) return;
            event.currentTarget = path[i]!;
            path[i]!.fireHandlers(`capture:${event.type}`, event);
        }

        // Target phase
        if (event.stopped) return;
        event.currentTarget = this;
        this.fireHandlers(event.type, event);

        // Bubble phase (target parent → root)
        for (let i = path.length - 2; i >= 0; i--) {
            if (event.stopped) return;
            event.currentTarget = path[i]!;
            path[i]!.fireHandlers(event.type, event);
        }
    }

    private fireHandlers(key: string, event: ElementEvent): void {
        const list = this.handlers.get(key);
        if (!list) return;
        for (const handler of list) {
            handler(event);
            if (event.stopped) return;
        }
    }

    // ---- Focus ----

    focus(): void {
        enqueue({ cmd: "set_focus", id: this.id });
    }

    // ---- Set as root ----

    setAsRoot(): void {
        enqueue({ cmd: "set_root", id: this.id });
    }

    // ---- Draw request ----

    requestDraw(): void {
        enqueue({ cmd: "request_draw", id: this.id });
    }
}

// ---- Box Element ----

export interface BoxBorderKind {
    top?: string;
    bottom?: string;
    left?: string;
    right?: string;
    top_left?: string;
    top_right?: string;
    bottom_left?: string;
    bottom_right?: string;
}

export interface BoxBorderColor {
    type: "all" | "sides" | "axes";
    fg?: Color;
    bg?: Color;
    top?: { fg?: Color; bg?: Color };
    bottom?: { fg?: Color; bg?: Color };
    left?: { fg?: Color; bg?: Color };
    right?: { fg?: Color; bg?: Color };
    vertical?: { fg?: Color; bg?: Color };
    horizontal?: { fg?: Color; bg?: Color };
}

export interface BoxBorder {
    kind?: BoxBorderKind;
    color?: BoxBorderColor;
}

export interface BoxShadow {
    color?: Color;
    offset_x?: number;
    offset_y?: number;
    spread?: number;
    opacity?: number;
}

export interface BoxProps {
    zIndex?: number;
    style?: Style;
    bg?: Color;
    fg?: Color;
    opacity?: number;
    segments?: Segment[];
    text_align?: TextAlign;
    rounded?: number;
    border?: BoxBorder;
    shadow?: BoxShadow;
}

export class BoxElement extends Element {
    bg: Color = { type: "default" };
    fg: Color = { type: "default" };
    opacity: number = 1;
    segments: Segment[] | null = null;
    text_align: TextAlign = "left";
    rounded: number | null = null;
    border: BoxBorder | null = null;
    shadow: BoxShadow | null = null;

    constructor() {
        super("box");
    }

    setProps(props: BoxProps): void {
        if (props.bg !== undefined) this.bg = props.bg;
        if (props.fg !== undefined) this.fg = props.fg;
        if (props.opacity !== undefined) this.opacity = props.opacity;
        if (props.segments !== undefined) this.segments = props.segments;
        if (props.text_align !== undefined) this.text_align = props.text_align;
        if (props.rounded !== undefined) this.rounded = props.rounded;
        if (props.border !== undefined) this.border = props.border;
        if (props.shadow !== undefined) this.shadow = props.shadow;
        if (props.style !== undefined) this.style = { ...this.style, ...props.style };
        if (props.zIndex !== undefined) this.zIndex = props.zIndex;

        this.enqueueSetProps(props);
    }
}

// ---- Factory ----

export function createElement(type: ElementType): Element {
    switch (type) {
        case "box":
            return new BoxElement();
    }
}

// ---- Tree snapshot (for testing) ----

export interface TreeNode {
    id: number;
    kind: string;
    zIndex: number;
    children?: TreeNode[];
}

export function snapshotTree(elem: Element): TreeNode {
    const node: TreeNode = {
        id: elem.id,
        kind: elem.elementType,
        zIndex: elem.zIndex,
    };
    if (elem.children.length > 0) {
        node.children = elem.children.map(snapshotTree);
    }
    return node;
}

// ---- Event creation helper ----

export function createEvent(type: string, target: Element, data: unknown): ElementEvent {
    return {
        type,
        target,
        currentTarget: target,
        data,
        stopped: false,
        stopPropagation() {
            this.stopped = true;
        },
    };
}
