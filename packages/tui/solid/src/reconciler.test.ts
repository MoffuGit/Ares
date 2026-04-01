import { describe, expect, test } from "bun:test"
import { BoxElement, ScrollableElement } from "@ares/tui-core/elements"
import { createElement, createTextNode, insertNode, setProp } from "./reconciler"

describe("reconciler", () => {
    test("resyncs text segments after box colors are applied", () => {
        const box = createElement("box")
        expect(box).toBeInstanceOf(BoxElement)

        const text = createTextNode("Ares")
        insertNode(box, text)

        setProp(box, "bg", "#FF0000")
        setProp(box, "fg", "#000000")

        expect((box as BoxElement).segments).toEqual([
            {
                text: "Ares",
                style: {
                    bg: { type: "rgb", r: 255, g: 0, b: 0 },
                    fg: { type: "rgb", r: 0, g: 0, b: 0 },
                },
            },
        ])
    })

    test("supports scrollable native nodes", () => {
        const root = createElement("box") as BoxElement
        const before = createElement("box") as BoxElement
        const scrollable = createElement("scrollable") as ScrollableElement

        expect(scrollable).toBeInstanceOf(ScrollableElement)

        insertNode(root, before)
        insertNode(root, scrollable)

        setProp(scrollable, "mode", "both")
        expect(scrollable.mode).toBe("both")

        const child = createElement("box") as BoxElement
        insertNode(scrollable, child)
        expect(scrollable.children.map((node) => node.id)).toEqual([child.id])

        const inserted = createElement("box") as BoxElement
        insertNode(root, inserted, scrollable)
        expect(root.children.map((node) => node.id)).toEqual([before.id, inserted.id, scrollable.id])
    })
})
