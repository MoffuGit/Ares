const std = @import("std");
const Allocator = std.mem.Allocator;
const vaxis = @import("vaxis");

const Element = @import("../element/mod.zig").Element;
const Style = @import("../element/mod.zig").Style;
const EventContext = @import("../events/mod.zig").EventContext;
const Buffer = @import("../Buffer.zig");
const split = @import("mod.zig");
const Direction = split.Direction;
const Sizing = split.Sizing;
const Divider = split.Divider;
const HitGrid = @import("../HitGrid.zig");

const Tree = @import("Tree.zig");

const Node = @This();

parent: ?*Node,
tree: ?*Tree,
ratio: f32,
sizing: Sizing,
element: *Element,
data: Data,

pub const Data = union(enum) {
    split: SplitData,
    view: ViewData,
};

pub const SplitData = struct {
    direction: Direction,
    children: std.ArrayList(*Node),
    dividers: std.ArrayList(*Divider),

    pub fn addChild(self: *SplitData, node: *Node, alloc: Allocator, parent_element: *Element) !void {
        if (self.children.items.len > 0) {
            const left = self.children.items[self.children.items.len - 1];
            const divider = try Divider.create(alloc, self.direction, left, node);
            try self.dividers.append(alloc, divider);
            try parent_element.addChild(divider.element);
        }
        try self.children.append(alloc, node);
        try parent_element.addChild(node.element);
        self.updateEqualRatios();
    }

    pub fn insertChild(self: *SplitData, index: usize, node: *Node, alloc: Allocator, parent_element: *Element) !void {
        const left = if (index > 0) self.children.items[index - 1] else null;
        const right = if (index < self.children.items.len) self.children.items[index] else null;
        const node_elem_idx = index * 2;

        if (left != null and right != null) {
            for (self.dividers.items, 0..) |d, i| {
                if (d.left == left and d.right == right.?) {
                    d.right = node;
                    const new_divider = try Divider.create(alloc, self.direction, node, right.?);
                    try self.dividers.insert(alloc, i + 1, new_divider);
                    try parent_element.insertChild(node.element, node_elem_idx);
                    try parent_element.insertChild(new_divider.element, node_elem_idx + 1);
                    break;
                }
            }
        } else if (right != null) {
            const new_divider = try Divider.create(alloc, self.direction, node, right.?);
            try self.dividers.insert(alloc, 0, new_divider);
            try parent_element.insertChild(node.element, node_elem_idx);
            try parent_element.insertChild(new_divider.element, node_elem_idx + 1);
        } else if (left != null) {
            const new_divider = try Divider.create(alloc, self.direction, left.?, node);
            try self.dividers.append(alloc, new_divider);
            try parent_element.addChild(new_divider.element);
            try parent_element.addChild(node.element);
        }

        try self.children.insert(alloc, index, node);
        self.updateEqualRatios();
    }

    fn elementIndexFor(self: *SplitData, child_index: usize) usize {
        _ = self;
        return child_index * 2;
    }

    pub fn removeChild(self: *SplitData, index: usize, alloc: Allocator) *Node {
        const removed = self.children.orderedRemove(index);
        removed.element.remove();

        if (self.dividers.items.len > 0) {
            const divider_idx = if (index > 0) index - 1 else 0;
            if (divider_idx < self.dividers.items.len) {
                const divider = self.dividers.orderedRemove(divider_idx);
                divider.destroy(alloc);

                if (index > 0 and index < self.children.items.len + 1 and divider_idx < self.dividers.items.len) {
                    self.dividers.items[divider_idx].left = self.children.items[index - 1];
                } else if (index == 0 and self.dividers.items.len > 0) {}
            }
        }

        self.updateEqualRatios();
        return removed;
    }

    pub fn updateEqualRatios(self: *SplitData) void {
        var equal_count: usize = 0;
        for (self.children.items) |child| {
            if (child.sizing == .equal) equal_count += 1;
        }
        if (equal_count == 0) return;

        const new_ratio = 1.0 / @as(f32, @floatFromInt(equal_count));
        for (self.children.items) |child| {
            if (child.sizing == .equal) {
                child.ratio = new_ratio;
                child.applyRatio();
            }
        }
    }
};

pub const ViewData = struct {
    id: u64,
};

pub fn createView(alloc: Allocator, id: u64) !*Node {
    const node = try alloc.create(Node);

    const element = try alloc.create(Element);
    element.* = Element.init(alloc, .{
        .style = .{
            .flex_grow = 1,
        },
        .userdata = node,
        .drawFn = drawView,
        .clickFn = clickView,
        .hitGridFn = hitView,
    });

    node.* = .{
        .parent = null,
        .tree = null,
        .ratio = 1.0,
        .sizing = .equal,
        .element = element,
        .data = .{ .view = .{ .id = id } },
    };
    return node;
}

fn drawView(element: *Element, buffer: *Buffer) void {
    const cell: vaxis.Cell = if (element.focused) vaxis.Cell{ .style = .{ .bg = .{ .rgb = .{ 255, 0, 255 } } } } else vaxis.Cell{ .style = .{ .bg = .{ .rgb = .{ 0, 255, 0 } } } };
    buffer.fillRect(
        element.layout.left,
        element.layout.top,
        element.layout.width,
        element.layout.height,
        cell,
    );
}

fn clickView(element: *Element, _: *EventContext, _: vaxis.Mouse) void {
    const node: *Node = @ptrCast(@alignCast(element.userdata));

    if (element.context) |ctx| {
        ctx.window.setFocus(element);
    }

    if (node.tree) |tree| {
        tree.focus(node.data.view.id);
    }
}

fn hitView(element: *Element, hit_grid: *HitGrid) void {
    hit_grid.fillRect(
        element.layout.left,
        element.layout.top,
        element.layout.width,
        element.layout.height,
        element.num,
    );
}

pub fn createSplit(alloc: Allocator, direction: Direction) !*Node {
    const element = try alloc.create(Element);
    element.* = Element.init(alloc, .{
        .style = .{
            .flex_direction = direction.toFlexDirection(),
            .flex_grow = 1,
        },
    });

    const node = try alloc.create(Node);
    node.* = .{
        .parent = null,
        .tree = null,
        .ratio = 1.0,
        .sizing = .equal,
        .element = element,
        .data = .{
            .split = .{
                .direction = direction,
                .children = .{},
                .dividers = .{},
            },
        },
    };
    return node;
}

pub fn destroy(self: *Node, alloc: Allocator) void {
    switch (self.data) {
        .split => |*s| {
            for (s.dividers.items) |divider| {
                divider.destroy(alloc);
            }
            for (s.children.items) |child| {
                child.destroy(alloc);
            }
            s.children.deinit(alloc);
            s.dividers.deinit(alloc);
        },
        .view => {},
    }
    self.element.deinit();
    alloc.destroy(self.element);
    alloc.destroy(self);
}

pub fn isView(self: *const Node) bool {
    return self.data == .view;
}

pub fn isSplit(self: *const Node) bool {
    return self.data == .split;
}

pub fn applyRatio(self: *Node) void {
    self.element.style.flex_grow = self.ratio;
    self.element.node.setFlexGrow(self.ratio);
}

pub fn childCount(self: *const Node) usize {
    return switch (self.data) {
        .split => |s| s.children.items.len,
        .view => 0,
    };
}

pub fn findChildIndex(self: *Node, child: *Node) ?usize {
    switch (self.data) {
        .split => |s| {
            for (s.children.items, 0..) |c, i| {
                if (c == child) return i;
            }
        },
        .view => {},
    }
    return null;
}

test "createView allocates node with view data" {
    const alloc = std.testing.allocator;

    const node = try createView(alloc, 42);
    defer node.destroy(alloc);

    try std.testing.expect(node.isView());
    try std.testing.expect(!node.isSplit());
    try std.testing.expectEqual(@as(u64, 42), node.data.view.id);
    try std.testing.expectEqual(@as(f32, 1.0), node.ratio);
    try std.testing.expectEqual(Sizing.equal, node.sizing);
}

test "createSplit allocates node with split data" {
    const alloc = std.testing.allocator;

    const node = try createSplit(alloc, .vertical);
    defer node.destroy(alloc);

    try std.testing.expect(node.isSplit());
    try std.testing.expect(!node.isView());
    try std.testing.expectEqual(Direction.vertical, node.data.split.direction);
    try std.testing.expectEqual(@as(usize, 0), node.childCount());
}

test "applyRatio updates element flex_grow" {
    const alloc = std.testing.allocator;

    const node = try createView(alloc, 1);
    defer node.destroy(alloc);

    node.ratio = 0.5;
    node.applyRatio();
}

test "SplitData addChild and updateEqualRatios" {
    const alloc = std.testing.allocator;

    const parent = try createSplit(alloc, .horizontal);
    defer parent.destroy(alloc);

    const child1 = try createView(alloc, 1);
    child1.parent = parent;
    try parent.data.split.addChild(child1, alloc, parent.element);

    try std.testing.expectEqual(@as(usize, 1), parent.childCount());
    try std.testing.expectEqual(@as(f32, 1.0), child1.ratio);

    const child2 = try createView(alloc, 2);
    child2.parent = parent;
    try parent.data.split.addChild(child2, alloc, parent.element);

    try std.testing.expectEqual(@as(usize, 2), parent.childCount());
    try std.testing.expectEqual(@as(f32, 0.5), child1.ratio);
    try std.testing.expectEqual(@as(f32, 0.5), child2.ratio);
}

test "SplitData removeChild" {
    const alloc = std.testing.allocator;

    const parent = try createSplit(alloc, .horizontal);
    defer parent.destroy(alloc);

    const child1 = try createView(alloc, 1);
    child1.parent = parent;
    try parent.data.split.addChild(child1, alloc, parent.element);

    const child2 = try createView(alloc, 2);
    child2.parent = parent;
    try parent.data.split.addChild(child2, alloc, parent.element);

    try std.testing.expectEqual(@as(usize, 2), parent.childCount());
    try std.testing.expectEqual(@as(usize, 1), parent.data.split.dividers.items.len);

    const removed = parent.data.split.removeChild(0, alloc);
    defer removed.destroy(alloc);

    try std.testing.expectEqual(@as(usize, 1), parent.childCount());
    try std.testing.expectEqual(@as(usize, 0), parent.data.split.dividers.items.len);
    try std.testing.expectEqual(@as(f32, 1.0), child2.ratio);
}
