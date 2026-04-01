import { describe, test, expect } from "bun:test";
import { TuiLib } from "./index";
import { BoxElement, ScrollableElement, createEvent, snapshotTree } from "./elements";

describe("Tree comparison", () => {
    test("TS and Zig element trees match after mutations", () => {
        const core = new TuiLib();

        const window = core.createTestWindow();
        expect(window).not.toBeNull();

        const mutations = core.createMutations(window!);
        expect(mutations).not.toBeNull();

        // Build a tree on the TS side
        const root = new BoxElement();
        const child1 = new BoxElement();
        const child2 = new BoxElement();
        const grandchild = new BoxElement();

        root.appendChild(child1);
        root.appendChild(child2);
        child1.appendChild(grandchild);
        root.setAsRoot();

        // Flush mutations to Zig
        core.processMutations(mutations!);

        // Snapshot TS tree
        const tsTree = snapshotTree(root);

        // Snapshot Zig tree
        const zigTree = core.dumpTree(window!);
        //
        expect(zigTree).not.toBeNull();
        expect(zigTree).toEqual(tsTree);

        core.destroyTestWindow(window!);
        core.destroyMutations(mutations!);
        core.deinitState();
    });

    test("nested tree with z-index", () => {
        const core = new TuiLib();

        const window = core.createTestWindow();
        const mutations = core.createMutations(window!);

        const root = new BoxElement();
        const a = new BoxElement();
        const b = new BoxElement();

        a.setZIndex(5);
        b.setZIndex(2);

        root.appendChild(a);
        root.appendChild(b);
        root.setAsRoot();

        core.processMutations(mutations!);

        const tsTree = snapshotTree(root);
        const zigTree = core.dumpTree(window!);

        expect(zigTree).toEqual(tsTree);

        core.destroyTestWindow(window!);
        core.destroyMutations(mutations!);
        core.deinitState();
    });

    test("remove child keeps trees in sync", () => {
        const core = new TuiLib();

        const window = core.createTestWindow();
        const mutations = core.createMutations(window!);

        const root = new BoxElement();
        const a = new BoxElement();
        const b = new BoxElement();

        root.appendChild(a);
        root.appendChild(b);
        root.setAsRoot();

        // Flush first batch
        core.processMutations(mutations!);

        // Now remove a child
        root.removeChild(a);

        // Flush second batch
        core.processMutations(mutations!);

        const tsTree = snapshotTree(root);
        const zigTree = core.dumpTree(window!);

        expect(zigTree).toEqual(tsTree);

        core.destroyTestWindow(window!);
        core.destroyMutations(mutations!);
        core.deinitState();
    });

    test("scrollable keeps its public tree shape in sync", () => {
        const core = new TuiLib();

        const window = core.createTestWindow();
        const mutations = core.createMutations(window!);

        const root = new ScrollableElement();
        const a = new BoxElement();
        const b = new BoxElement();

        root.appendChild(a);
        root.appendChild(b);
        root.setAsRoot();

        core.processMutations(mutations!);

        const tsTree = snapshotTree(root);
        const zigTree = core.dumpTree(window!);

        expect(zigTree).toEqual(tsTree);

        core.destroyTestWindow(window!);
        core.destroyMutations(mutations!);
        core.deinitState();
    });

    test("scrollable wheel events call the Zig scroll exports", () => {
        const core = new TuiLib();

        const window = core.createTestWindow();
        const mutations = core.createMutations(window!);

        const root = new ScrollableElement();
        root.appendChild(new BoxElement());
        root.setAsRoot();

        core.processMutations(mutations!);

        expect(root.scrollBy(0, 1)).toBe(true);
        expect(root.scrollTo(0, 0)).toBe(true);

        const event = createEvent("wheel", root, { button: "wheel_down" });
        root.dispatchEvent(event);

        expect(event.stopped).toBe(true);

        core.destroyTestWindow(window!);
        core.destroyMutations(mutations!);
        core.deinitState();
    });

    test("scrollable bar drag captures descendant mouse events", () => {
        const root = new ScrollableElement();
        const child = new BoxElement();
        root.appendChild(child);

        root.barPress = () => true;
        root.barDrag = () => true;
        root.barRelease = () => true;
        root.containsPoint = () => false;

        const mouseDown = createEvent("mousedown", root, { button: "left", col: 4, row: 1 });
        root.dispatchEvent(mouseDown);
        expect(mouseDown.stopped).toBe(true);

        const mouseMove = createEvent("mousemove", child, { col: 4, row: 2 });
        child.dispatchEvent(mouseMove);
        expect(mouseMove.stopped).toBe(true);

        const mouseUp = createEvent("mouseup", child, { col: 4, row: 2 });
        child.dispatchEvent(mouseUp);
        expect(mouseUp.stopped).toBe(true);

        const click = createEvent("click", child, { col: 4, row: 2 });
        child.dispatchEvent(click);
        expect(click.stopped).toBe(true);

        const nextClick = createEvent("click", child, { col: 4, row: 2 });
        child.dispatchEvent(nextClick);
        expect(nextClick.stopped).toBe(false);

        root.removeChild(child);
        child.delete();
        root.delete();
    });
});
