import { describe, test, expect } from "bun:test";
import { TuiLib } from "./index";
import { BoxElement, snapshotTree } from "./elements";

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
});
