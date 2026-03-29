import { describe, expect, test } from "bun:test"
import { BoxElement } from "@ares/tui-core/elements"
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
})
