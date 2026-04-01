import { BoxElement, Element as CoreElement, ScrollableElement, type Segment } from "@ares/tui-core/elements"
import { createRenderer } from "./renderer"
import { nextInternalId, camelToSnake, parseColor, log } from "./utils"

export class TextNode {
    readonly id: number
    text: string
    parent: TuiNode | null = null

    constructor(text: string) {
        this.id = nextInternalId()
        this.text = text
    }
}

export class SlotNode {
    readonly id: number
    parent: TuiNode | null = null

    constructor() {
        this.id = nextInternalId()
    }
}

type NativeNode = BoxElement | ScrollableElement

export type TuiNode = NativeNode | TextNode | SlotNode

const nodeChildren = new WeakMap<TuiNode, TuiNode[]>()

function getChildren(node: TuiNode): TuiNode[] {
    let c = nodeChildren.get(node)
    if (!c) {
        c = []
        nodeChildren.set(node, c)
    }
    return c
}

function syncSegments(parent: BoxElement): void {
    const children = getChildren(parent)
    const segments: Segment[] = []

    for (const child of children) {
        if (child instanceof TextNode) {
            segments.push({
                text: child.text, style: {
                    bg: parent.bg,
                    fg: parent.fg
                }
            })
        }
    }

    if (segments.length > 0) {
        parent.setProps({ segments })
    } else {
        parent.setProps({ segments: [] })
    }
}

function isNativeNode(node: TuiNode): node is NativeNode {
    return node instanceof CoreElement
}

function findNativeAnchor(children: TuiNode[], afterIndex: number): NativeNode | null {
    for (let i = afterIndex; i < children.length; i++) {
        const candidate = children[i]
        if (candidate && isNativeNode(candidate)) return candidate
    }
    return null
}

const BOX_PROPS = new Set(["bg", "fg", "opacity", "segments", "text_align", "rounded", "border", "shadow"])
const MOUSE_EVENTS = new Set(["click", "mousedown", "mouseup", "mousemove", "mouseenter", "mouseleave", "wheel"])

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
        log("createElement:", tag)
        switch (tag) {
            case "box":
                return new BoxElement()
            case "scrollable":
                return new ScrollableElement()
            default:
                throw new Error(`[Reconciler] Unknown element type: "${tag}". Supported types are "box" and "scrollable".`)
        }
    },

    createTextNode(value: string): TuiNode {
        log("createTextNode:", value)
        if (typeof value === "number") value = (value as number).toString()
        return new TextNode(value)
    },

    createSlotNode(): TuiNode {
        log("createSlotNode")
        return new SlotNode()
    },

    replaceText(node: TuiNode, value: string): void {
        if (!(node instanceof TextNode)) return
        log("replaceText:", value, "in node:", node.id)

        node.text = value
        if (node.parent && node.parent instanceof BoxElement) {
            syncSegments(node.parent)
        }
    },

    isTextNode(node: TuiNode): boolean {
        return node instanceof TextNode
    },

    setProperty(node: TuiNode, name: string, value: unknown, prev?: unknown): void {
        if (!isNativeNode(node)) return

        if (name === "children") return

        if (name === "ref") {
            if (typeof value === "function") (value as (el: NativeNode) => void)(node)
            return
        }

        if (name.startsWith("on:")) {
            const event = name.slice(3)
            if (prev) node.off(event, prev as any)
            if (value) {
                node.on(event, value as any)
                if (MOUSE_EVENTS.has(event) && node instanceof BoxElement) {
                    node.setProps({ interactive: true })
                }
            }
            return
        }

        if (name.length > 2 && name.startsWith("on") && name[2]! >= "A" && name[2]! <= "Z") {
            const event = name.slice(2).toLowerCase()
            if (prev) node.off(event, prev as any)
            if (value) {
                node.on(event, value as any)
                if (MOUSE_EVENTS.has(event) && node instanceof BoxElement) {
                    node.setProps({ interactive: true })
                }
            }
            return
        }

        if (name === "focused") {
            if (value) node.focus()
            return
        }

        if (name === "style") {
            if (value) node.setStyle(value as any)
            return
        }

        if (name === "mode") {
            if (node instanceof ScrollableElement) {
                node.setProps({ mode: value as ScrollableElement["mode"] })
            }
            return
        }

        if (name === "bg" || name === "fg") {
            if (!(node instanceof BoxElement)) return
            node.setProps({ [name]: parseColor(value) } as any)
            if (getChildren(node).some((child) => child instanceof TextNode)) {
                syncSegments(node)
            }
            return
        }

        if (name === "zIndex") {
            node.setZIndex(value as number)
            return
        }

        if (node instanceof BoxElement && BOX_PROPS.has(name)) {
            node.setProps({ [name]: value } as any)
            return
        }

        const styleKey = camelToSnake(name)
        node.setStyle({ [styleKey]: value } as any)
    },

    insertNode(parent: TuiNode, node: TuiNode, anchor?: TuiNode): void {
        log("insertNode:", nodeId(node), "into:", nodeId(parent), "anchor:", anchor ? nodeId(anchor) : "none")

        const children = getChildren(parent)

        if (!anchor) {
            children.push(node)
        } else {
            const idx = children.indexOf(anchor)
            if (idx === -1) {
                children.push(node)
            } else {
                children.splice(idx, 0, node)
            }
        }

        if (node instanceof TextNode || node instanceof SlotNode) {
            node.parent = parent
        }

        if (isNativeNode(node) && isNativeNode(parent)) {
            if (!anchor) {
                parent.appendChild(node)
            } else {
                const nodeIdx = children.indexOf(node)
                const nativeAnchor = findNativeAnchor(children, nodeIdx + 1)
                if (nativeAnchor) {
                    parent.insertBefore(node, nativeAnchor)
                } else {
                    parent.appendChild(node)
                }
            }
        }

        if (node instanceof TextNode && parent instanceof BoxElement) {
            syncSegments(parent)
        }
    },

    removeNode(parent: TuiNode, node: TuiNode): void {
        log("removeNode:", nodeId(node), "from:", nodeId(parent))

        const children = getChildren(parent)
        const idx = children.indexOf(node)
        if (idx !== -1) {
            children.splice(idx, 1)
        }

        if (node instanceof TextNode || node instanceof SlotNode) {
            node.parent = null
        }

        if (isNativeNode(node) && isNativeNode(parent)) {
            parent.removeChild(node)
        }

        if (node instanceof TextNode && parent instanceof BoxElement) {
            syncSegments(parent)
        }
    },

    getParentNode(node: TuiNode): TuiNode | undefined {
        if (node instanceof TextNode || node instanceof SlotNode) {
            return node.parent ?? undefined
        }
        return (node.parent as NativeNode | null) ?? undefined
    },

    getFirstChild(node: TuiNode): TuiNode | undefined {
        const children = getChildren(node)
        return children[0]
    },

    getNextSibling(node: TuiNode): TuiNode | undefined {
        let parent: TuiNode | null | undefined
        if (node instanceof TextNode || node instanceof SlotNode) {
            parent = node.parent
        } else {
            parent = node.parent as NativeNode | null
        }
        if (!parent) return undefined

        const siblings = getChildren(parent)
        const index = siblings.indexOf(node)
        if (index === -1 || index === siblings.length - 1) return undefined
        return siblings[index + 1]
    },
})

function nodeId(node: TuiNode): string {
    if (isNativeNode(node)) return `${node.elementType}-${node.id}`
    if (node instanceof TextNode) return `text-${node.id}`
    return `slot-${(node as SlotNode).id}`
}
