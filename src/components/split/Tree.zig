const std = @import("std");
const Allocator = std.mem.Allocator;
const vaxis = @import("vaxis");

const Buffer = @import("../Buffer.zig");
const Element = @import("../element/mod.zig").Element;
const Style = @import("../element/mod.zig").Style;
const EventContext = @import("../events/mod.zig").EventContext;
const splitpkg = @import("mod.zig");
const Node = splitpkg.Node;
const Direction = splitpkg.Direction;
const Divider = splitpkg.Divider;
const MIN_WIDTH = splitpkg.MIN_WIDTH;
const MIN_HEIGHT = splitpkg.MIN_HEIGHT;

const Tree = @This();

alloc: Allocator,
root: *Node,
next_id: u64,
focused_view: u64,
element: *Element,

pub fn create(alloc: Allocator) !*Tree {
    const tree = try alloc.create(Tree);

    const element = try alloc.create(Element);
    element.* = Element.init(
        alloc,
        .{
            .style = .{
                .width = .{ .percent = 100 },
                .height = .{ .percent = 100 },
            },
            .userdata = tree,
        },
    );
    try element.addEventListener(.key_press, Tree, tree, keyPressFn);

    const initial_id: u64 = 1;
    const root = try Node.createView(alloc, initial_id);
    root.tree = tree;
    try element.addChild(root.element);

    tree.* = .{
        .alloc = alloc,
        .root = root,
        .next_id = initial_id + 1,
        .focused_view = initial_id,
        .element = element,
    };
    return tree;
}

fn keyPressFn(self: *Tree, data: Element.EventData) void {
    const key_data = data.key_press;
    const ctx = key_data.ctx;
    const key = key_data.key;

    if (key.mods.ctrl) {
        const handled = switch (key.codepoint) {
            'h' => blk: {
                _ = self.split(self.focused_view, .vertical, false) catch break :blk false;
                break :blk true;
            },
            'l' => blk: {
                _ = self.split(self.focused_view, .vertical, true) catch break :blk false;
                break :blk true;
            },
            'k' => blk: {
                _ = self.split(self.focused_view, .horizontal, false) catch break :blk false;
                break :blk true;
            },
            'j' => blk: {
                _ = self.split(self.focused_view, .horizontal, true) catch break :blk false;
                break :blk true;
            },
            else => false,
        };

        if (handled) {
            ctx.stopPropagation();
            if (element.context) |app_ctx| {
                app_ctx.requestDraw();
            }
        }
    }
}

pub fn destroy(self: *Tree) void {
    self.root.destroy(self.alloc);
    self.element.deinit();
    self.alloc.destroy(self.element);
    self.alloc.destroy(self);
}

pub fn nextId(self: *Tree) u64 {
    const id = self.next_id;
    self.next_id += 1;
    return id;
}

pub fn find(self: *Tree, id: u64) ?*Node {
    return findInNode(self.root, id);
}

fn findInNode(node: *Node, id: u64) ?*Node {
    switch (node.data) {
        .view => |v| {
            if (v.id == id) return node;
        },
        .split => |s| {
            for (s.children.items) |child| {
                if (findInNode(child, id)) |found| return found;
            }
        },
    }
    return null;
}

pub fn split(self: *Tree, id: u64, direction: Direction, after: bool) !u64 {
    const target = self.find(id) orelse return error.NodeNotFound;

    const target_size: u16 = switch (direction) {
        .vertical => target.element.layout.width,
        .horizontal => target.element.layout.height,
    };
    const min_size: u16 = switch (direction) {
        .vertical => MIN_WIDTH,
        .horizontal => MIN_HEIGHT,
    };
    if (target_size < min_size * 2) return error.NodeTooSmall;

    const new_id = self.nextId();
    const new_view = try Node.createView(self.alloc, new_id);
    new_view.tree = self;

    if (target.parent) |parent| {
        if (parent.isSplit() and parent.data.split.direction == direction) {
            const idx = parent.findChildIndex(target) orelse return error.NodeNotFound;
            const insert_idx = if (after) idx + 1 else idx;
            new_view.parent = parent;

            if (target.sizing == .fixed) {
                const half_ratio = target.ratio / 2.0;
                target.ratio = half_ratio;
                target.applyRatio();
                new_view.ratio = half_ratio;
                new_view.sizing = .fixed;
                new_view.applyRatio();
                try parent.data.split.insertChildFixed(insert_idx, new_view, self.alloc, parent.element);
            } else {
                try parent.data.split.insertChild(insert_idx, new_view, self.alloc, parent.element);
            }
            return new_id;
        }
    }

    const new_split = try Node.createSplit(self.alloc, direction);
    new_split.tree = self;

    if (target.parent) |parent| {
        const idx = parent.findChildIndex(target) orelse return error.NodeNotFound;
        target.element.remove();

        for (parent.data.split.dividers.items) |d| {
            if (d.left == target) d.left = new_split;
            if (d.right == target) d.right = new_split;
        }

        parent.data.split.children.items[idx] = new_split;
        new_split.parent = parent;
        new_split.ratio = target.ratio;
        new_split.sizing = target.sizing;
        new_split.applyRatio();
        try parent.element.insertChild(new_split.element, idx * 2);
    } else {
        self.element.removeChild(target.element.num);
        self.root = new_split;
        try self.element.addChild(new_split.element);
    }

    target.ratio = 1.0;
    target.sizing = .equal;

    target.parent = new_split;
    new_view.parent = new_split;

    if (after) {
        try new_split.data.split.addChild(target, self.alloc, new_split.element);
        try new_split.data.split.addChild(new_view, self.alloc, new_split.element);
    } else {
        try new_split.data.split.addChild(new_view, self.alloc, new_split.element);
        try new_split.data.split.addChild(target, self.alloc, new_split.element);
    }

    return new_id;
}

pub fn remove(self: *Tree, id: u64) !void {
    const node = self.find(id) orelse return error.NodeNotFound;

    if (node.parent == null) {
        return error.CannotRemoveRoot;
    }

    const parent = node.parent.?;
    const idx = parent.findChildIndex(node) orelse return error.NodeNotFound;

    const removed = parent.data.split.removeChild(idx, self.alloc);

    if (parent.data.split.children.items.len == 1) {
        try self.collapse(parent);
    }

    removed.destroy(self.alloc);

    if (self.focused_view == id) {
        self.focusFirst();
    }
}

fn collapse(self: *Tree, parent: *Node) !void {
    const remaining = parent.data.split.children.items[0];
    remaining.element.remove();

    if (parent.parent) |grandparent| {
        const idx = grandparent.findChildIndex(parent) orelse return error.NodeNotFound;

        parent.element.remove();

        for (grandparent.data.split.dividers.items) |d| {
            if (d.left == parent) d.left = remaining;
            if (d.right == parent) d.right = remaining;
        }

        grandparent.data.split.children.items[idx] = remaining;
        remaining.parent = grandparent;
        remaining.ratio = parent.ratio;
        remaining.sizing = parent.sizing;
        remaining.applyRatio();
        try grandparent.element.insertChild(remaining.element, idx * 2);
    } else {
        parent.element.remove();
        self.root = remaining;
        remaining.parent = null;
        try self.element.addChild(remaining.element);
    }

    parent.data.split.children.clearRetainingCapacity();
    parent.data.split.dividers.deinit(self.alloc);
    parent.data.split.children.deinit(self.alloc);
    parent.element.deinit();
    self.alloc.destroy(parent.element);
    self.alloc.destroy(parent);
}

pub fn focus(self: *Tree, id: u64) void {
    if (self.find(id) != null) {
        self.focused_view = id;
    }
}

fn focusFirst(self: *Tree) void {
    if (findFirstView(self.root)) |node| {
        self.focused_view = node.data.view.id;
    }
}

fn findFirstView(node: *Node) ?*Node {
    switch (node.data) {
        .view => return node,
        .split => |s| {
            if (s.children.items.len > 0) {
                return findFirstView(s.children.items[0]);
            }
        },
    }
    return null;
}

pub fn getFocusedView(self: *Tree) ?*Node {
    return self.find(self.focused_view);
}
