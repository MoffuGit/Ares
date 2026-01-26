const std = @import("std");
const Allocator = std.mem.Allocator;
const vaxis = @import("vaxis");

const Element = @import("../element/mod.zig").Element;
const Style = @import("../element/mod.zig").Style;
const Buffer = @import("../Buffer.zig");
const HitGrid = @import("../HitGrid.zig");
const split = @import("mod.zig");
const Direction = split.Direction;
const Sizing = split.Sizing;
const Node = split.Node;

const Divider = @This();

direction: Direction,
left: *Node,
right: *Node,
element: *Element,
dragging: bool,

pub fn create(alloc: Allocator, direction: Direction, left: *Node, right: *Node) !*Divider {
    const divider = try alloc.create(Divider);

    const element = try alloc.create(Element);
    element.* = Element.init(alloc, .{
        .style = switch (direction) {
            .horizontal => .{
                .height = .{ .point = 1 },
                .width = .{ .percent = 100 },
                .flex_shrink = 0,
            },
            .vertical => .{
                .width = .{ .point = 1 },
                .height = .{ .percent = 100 },
                .flex_shrink = 0,
            },
        },
        .hitGridFn = hit,
        .userdata = divider,
        .drawFn = draw,
    });

    divider.* = .{
        .direction = direction,
        .left = left,
        .right = right,
        .element = element,
        .dragging = false,
    };
    return divider;
}

fn hit(element: *Element, hit_grid: *HitGrid) void {
    hit_grid.fillRect(
        element.layout.left,
        element.layout.top,
        element.layout.width,
        element.layout.height,
        element.num,
    );
}

fn draw(element: *Element, buffer: *Buffer) void {
    buffer.fillRect(
        element.layout.left,
        element.layout.top,
        element.layout.width,
        element.layout.height,
        .{ .style = .{ .bg = .{ .rgb = .{ 255, 0, 0 } } } },
    );
}

pub fn destroy(self: *Divider, alloc: Allocator) void {
    self.element.remove();
    self.element.deinit();
    alloc.destroy(self.element);
    alloc.destroy(self);
}

pub fn onDrag(self: *Divider, delta: f32) void {
    const total_ratio = self.left.ratio + self.right.ratio;
    const delta_ratio = delta * total_ratio;

    const new_left = @max(0.05, self.left.ratio + delta_ratio);
    const new_right = @max(0.05, self.right.ratio - delta_ratio);

    if (new_left >= 0.05 and new_right >= 0.05) {
        self.left.ratio = new_left;
        self.right.ratio = new_right;

        self.left.sizing = .fixed;
        self.right.sizing = .fixed;

        self.left.applyRatio();
        self.right.applyRatio();
    }
}

test "create divider" {
    const alloc = std.testing.allocator;

    const left = try Node.createView(alloc, 1);
    defer left.destroy(alloc);

    const right = try Node.createView(alloc, 2);
    defer right.destroy(alloc);

    const divider = try Divider.create(alloc, .vertical, left, right);
    defer divider.destroy(alloc);

    try std.testing.expectEqual(Direction.vertical, divider.direction);
    try std.testing.expectEqual(left, divider.left);
    try std.testing.expectEqual(right, divider.right);
    try std.testing.expect(!divider.dragging);
}

test "onDrag adjusts ratios" {
    const alloc = std.testing.allocator;

    const left = try Node.createView(alloc, 1);
    defer left.destroy(alloc);

    const right = try Node.createView(alloc, 2);
    defer right.destroy(alloc);

    left.ratio = 0.5;
    right.ratio = 0.5;

    const divider = try Divider.create(alloc, .vertical, left, right);
    defer divider.destroy(alloc);

    divider.onDrag(0.2);

    try std.testing.expect(left.ratio > 0.5);
    try std.testing.expect(right.ratio < 0.5);
    try std.testing.expectEqual(Sizing.fixed, left.sizing);
    try std.testing.expectEqual(Sizing.fixed, right.sizing);
}
