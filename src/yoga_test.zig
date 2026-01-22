const std = @import("std");
const yoga = @import("yoga");
const Style = @import("element/Style.zig");

pub fn main() !void {
    std.debug.print("=== Yoga Incremental Layout Test ===\n\n", .{});

    const root = yoga.YGNodeNew();
    defer yoga.YGNodeFreeRecursive(root);

    const root_style = Style{
        .flex_direction = .column,
        .width = Style.StyleValue.px(100),
        .height = Style.StyleValue.px(100),
        .padding = Style.Edges.uniform(Style.StyleValue.px(10)),
    };
    root_style.apply(root);

    const child1 = yoga.YGNodeNew();
    const child1_style = Style{ .flex_grow = 1 };
    child1_style.apply(child1);
    yoga.YGNodeInsertChild(root, child1, 0);

    const child2 = yoga.YGNodeNew();
    const child2_style = Style{ .flex_grow = 1 };
    child2_style.apply(child2);
    yoga.YGNodeInsertChild(root, child2, 1);

    // --- Initial Layout ---
    std.debug.print("--- Initial Layout ---\n", .{});
    std.debug.print("Before calculate:\n", .{});
    printDirtyState(root, child1, child2);

    yoga.YGNodeCalculateLayout(root, yoga.YGUndefined, yoga.YGUndefined, yoga.YGDirectionLTR);

    std.debug.print("\nAfter calculate:\n", .{});
    printDirtyState(root, child1, child2);
    printAllLayouts(root, child1, child2);

    clearNewLayoutFlags(root);
    clearNewLayoutFlags(child1);
    clearNewLayoutFlags(child2);

    // --- Recalculate without changes (should use cache) ---
    std.debug.print("\n--- Recalculate (no changes) ---\n", .{});
    std.debug.print("Before calculate:\n", .{});
    printDirtyState(root, child1, child2);

    yoga.YGNodeCalculateLayout(root, yoga.YGUndefined, yoga.YGUndefined, yoga.YGDirectionLTR);

    std.debug.print("\nAfter calculate:\n", .{});
    printDirtyState(root, child1, child2);
    std.debug.print("(hasNewLayout should be false - layout was cached)\n", .{});

    // --- Change child1's height ---
    std.debug.print("\n--- Change child1 to fixed height=20 ---\n", .{});
    const child1_updated = Style{
        .height = Style.StyleValue.px(20),
        .flex_grow = 0,
    };
    child1_updated.apply(child1);

    std.debug.print("Before calculate:\n", .{});
    printDirtyState(root, child1, child2);

    yoga.YGNodeCalculateLayout(root, yoga.YGUndefined, yoga.YGUndefined, yoga.YGDirectionLTR);

    std.debug.print("\nAfter calculate:\n", .{});
    printDirtyState(root, child1, child2);
    printAllLayouts(root, child1, child2);

    clearNewLayoutFlags(root);
    clearNewLayoutFlags(child1);
    clearNewLayoutFlags(child2);

    // --- Change only child2 ---
    std.debug.print("\n--- Change only child2 margin ---\n", .{});
    const child2_updated = Style{
        .flex_grow = 1,
        .margin = Style.Edges{ .top = Style.StyleValue.px(5) },
    };
    child2_updated.apply(child2);

    std.debug.print("Before calculate:\n", .{});
    printDirtyState(root, child1, child2);

    yoga.YGNodeCalculateLayout(root, yoga.YGUndefined, yoga.YGUndefined, yoga.YGDirectionLTR);

    std.debug.print("\nAfter calculate:\n", .{});
    printDirtyState(root, child1, child2);
    printAllLayouts(root, child1, child2);

    std.debug.print("\n=== Test Complete ===\n", .{});
}

fn printDirtyState(root: yoga.YGNodeRef, child1: yoga.YGNodeRef, child2: yoga.YGNodeRef) void {
    std.debug.print("  root:   dirty={}, hasNewLayout={}\n", .{ yoga.YGNodeIsDirty(root), yoga.YGNodeGetHasNewLayout(root) });
    std.debug.print("  child1: dirty={}, hasNewLayout={}\n", .{ yoga.YGNodeIsDirty(child1), yoga.YGNodeGetHasNewLayout(child1) });
    std.debug.print("  child2: dirty={}, hasNewLayout={}\n", .{ yoga.YGNodeIsDirty(child2), yoga.YGNodeGetHasNewLayout(child2) });
}

fn printAllLayouts(root: yoga.YGNodeRef, child1: yoga.YGNodeRef, child2: yoga.YGNodeRef) void {
    std.debug.print("\nLayout results:\n", .{});
    printNodeLayout("  root", root);
    printNodeLayout("  child1", child1);
    printNodeLayout("  child2", child2);
}

fn printNodeLayout(name: []const u8, node: yoga.YGNodeRef) void {
    std.debug.print("{s}: left={d:.0}, top={d:.0}, w={d:.0}, h={d:.0}\n", .{
        name,
        yoga.YGNodeLayoutGetLeft(node),
        yoga.YGNodeLayoutGetTop(node),
        yoga.YGNodeLayoutGetWidth(node),
        yoga.YGNodeLayoutGetHeight(node),
    });
}

fn clearNewLayoutFlags(node: yoga.YGNodeRef) void {
    yoga.YGNodeSetHasNewLayout(node, false);
}
