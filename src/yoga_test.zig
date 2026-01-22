const std = @import("std");
const yoga = @import("yoga");

pub fn main() !void {
    std.debug.print("=== Yoga Layout Test ===\n\n", .{});

    // Create a root node (container)
    const root = yoga.YGNodeNew();
    defer yoga.YGNodeFreeRecursive(root);

    // Set root node styles (flexbox container)
    yoga.YGNodeStyleSetFlexDirection(root, yoga.YGFlexDirectionColumn);
    yoga.YGNodeStyleSetWidth(root, 100);
    yoga.YGNodeStyleSetHeight(root, 100);
    yoga.YGNodeStyleSetPadding(root, yoga.YGEdgeAll, 10);

    // Create first child
    const child1 = yoga.YGNodeNew();
    yoga.YGNodeStyleSetFlexGrow(child1, 1);
    yoga.YGNodeStyleSetMargin(child1, yoga.YGEdgeBottom, 5);
    yoga.YGNodeInsertChild(root, child1, 0);

    // Create second child
    const child2 = yoga.YGNodeNew();
    yoga.YGNodeStyleSetFlexGrow(child2, 2);
    yoga.YGNodeInsertChild(root, child2, 1);

    // Calculate layout
    yoga.YGNodeCalculateLayout(root, yoga.YGUndefined, yoga.YGUndefined, yoga.YGDirectionLTR);

    // Print layout results
    std.debug.print("Root Layout:\n", .{});
    printNodeLayout("  root", root);

    std.debug.print("\nChild Layouts:\n", .{});
    printNodeLayout("  child1", child1);
    printNodeLayout("  child2", child2);

    std.debug.print("\n=== Test Complete ===\n", .{});
}

fn printNodeLayout(name: []const u8, node: yoga.YGNodeRef) void {
    const left = yoga.YGNodeLayoutGetLeft(node);
    const top = yoga.YGNodeLayoutGetTop(node);
    const width = yoga.YGNodeLayoutGetWidth(node);
    const height = yoga.YGNodeLayoutGetHeight(node);

    std.debug.print("{s}: left={d:.1}, top={d:.1}, width={d:.1}, height={d:.1}\n", .{
        name,
        left,
        top,
        width,
        height,
    });
}
