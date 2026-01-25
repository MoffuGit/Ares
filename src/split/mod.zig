pub const nodepkg = @import("Node.zig");

pub const Direction = nodepkg.Direction;
pub const Split = nodepkg.Split;
pub const View = nodepkg.View;
pub const Node = nodepkg.Node;

const std = @import("std");
const Allocator = std.mem.Allocator;
const Element = @import("../element/mod.zig").Element;
const Buffer = @import("../Buffer.zig");
const EventContext = @import("../events/EventContext.zig");
const vaxis = @import("vaxis");

pub const Tree = @This();

pub const NodePath = std.ArrayList(usize);

alloc: Allocator,
root: *Node,
next_id: u64,
element: Element,

fn draw(element: *Element, buffer: *Buffer) void {
    const x = element.layout.left;
    const y = element.layout.top;

    var row: u16 = 0;
    while (row < element.layout.height) : (row += 1) {
        var col: u16 = 0;
        while (col < element.layout.width) : (col += 1) {
            const px = x + col;
            const py = y + row;
            if (px < buffer.width and py < buffer.height) {
                buffer.writeCell(px, py, .{ .style = .{ .bg = .{ .rgb = .{ 255, 0, 0 } } } });
            }
        }
    }
}

pub fn keyPressFn(element: *Element, ctx: *EventContext, key: vaxis.Key) void {
    if (key.matches('l', .{ .ctrl = true })) {
        const self: *Tree = @ptrCast(@alignCast(element.userdata));

        _ = self.split(0, .horizontal, true) catch {};

        ctx.stopPropagation();
    }
}

pub fn create(alloc: Allocator) !*Tree {
    const self = try alloc.create(Tree);
    errdefer alloc.destroy(self);

    const view = try View.create(alloc, 0);
    errdefer view.destroy();

    const root = try alloc.create(Node);
    errdefer root.destroy();
    root.* = Node{ .view = view };

    self.* = .{
        .alloc = alloc,
        .root = root,
        .next_id = 1,
        .element = Element.init(
            alloc,
            .{
                .keyPressFn = keyPressFn,
                .userdata = self,
                .drawFn = draw,
                .style = .{
                    .width = .{ .percent = 100 },
                    .height = .{ .percent = 100 },
                    .flex_direction = .row,
                },
            },
        ),
    };

    try self.element.addChild(&view.element);

    return self;
}

pub fn destroy(self: *Tree) void {
    self.root.destroy();
    self.alloc.destroy(self.root);
    self.element.deinit();
    self.alloc.destroy(self);
}

pub fn nextId(self: *Tree) u64 {
    const id = self.next_id;
    self.next_id += 1;
    return id;
}

pub fn find(self: *Tree, id: u64) ?*Node {
    return self.root.find(id);
}

pub fn findPath(self: *Tree, id: u64) ?NodePath {
    return self.root.path(self.alloc, id);
}

pub fn getNodeFromPath(self: *Tree, path: []const usize) ?*Node {
    var current: *Node = self.root;

    if (path.len == 0) return self.root;

    for (path) |index| {
        switch (current.*) {
            .split => |s| {
                if (index >= s.children.items.len) return null;
                current = s.children.items[index];
            },
            .view => return null,
        }
    }
    return current;
}

pub fn getParentFromPath(self: *Tree, path: []const usize) ?*Node {
    if (path.len == 0) return null;

    const parent_path = path[0 .. path.len - 1];

    return self.getNodeFromPath(parent_path);
}

pub fn count(self: *const Tree) usize {
    return self.root.count();
}

pub fn split(self: *Tree, id: u64, direction: Direction, after: bool) !u64 {
    const new_id = self.nextId();

    if (self.root.* == .view) {
        //NOTE: check this part, is broken
        if (self.root.view.id != id) return error.NotFound;
        try self.root._split(self.alloc, new_id, direction, after);
        try self.element.addChild(self.root.getElement());
        return new_id;
    }

    var path = self.findPath(id) orelse return error.NotFound;
    defer path.deinit(self.alloc);

    const parent = self.getParentFromPath(path.items) orelse return error.PathIsBroken;
    const index = path.items[path.items.len - 1];

    if (parent.* != .split) return error.PathIsBroken;

    const node = try parent.get(index);

    if (parent.split.direction == direction) {
        const new_view = try View.create(self.alloc, new_id);
        new_view.equal = true;
        const new_node = try self.alloc.create(Node);
        new_node.* = Node{ .view = new_view };

        try parent.insertChild(if (after) index + 1 else index, new_node);
    } else {
        try node._split(self.alloc, new_id, direction, after);
    }

    return new_id;
}

pub fn remove(self: *Tree, id: u64) void {
    if (self.root.* == .view) {
        return;
    }
    var path = self.findPath(id) orelse return;
    defer path.deinit(self.alloc);

    const parent = self.getParentFromPath(path.items) orelse return;
    const index = path.items[path.items.len - 1];

    const removed = parent.removeChild(index);

    if (parent.split.childCount() == 1) {
        parent.collapse(self.alloc);
    } else if (!removed.isEqual()) {
        const removed_ratio = removed.ratio();
        const children = &parent.split.children.items;
        const left: ?*Node = if (index > 0) children.*[index - 1] else null;
        const right: ?*Node = if (index < children.len) children.*[index] else null;

        if (left != null and !left.?.isEqual()) {
            left.?.setRatio(left.?.ratio() + removed_ratio);
        } else if (right != null and !right.?.isEqual()) {
            right.?.setRatio(right.?.ratio() + removed_ratio);
        }
    }

    removed.destroy();
}
