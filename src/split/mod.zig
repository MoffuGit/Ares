pub const nodepkg = @import("Node.zig");

pub const Direction = nodepkg.Direction;
pub const Split = nodepkg.Split;
pub const View = nodepkg.View;
pub const Node = nodepkg.Node;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Tree = @This();

pub const NodePath = std.ArrayList(usize);

alloc: Allocator,
root: Node,
next_id: u64,

pub fn init(alloc: Allocator) Tree {
    return .{
        .alloc = alloc,
        .root = Node{ .view = View.init(0) },
        .next_id = 1,
    };
}

pub fn deinit(self: *Tree) void {
    self.root.deinit();
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
    var current: *Node = &self.root;

    if (path.len == 0) return &self.root;

    for (path) |index| {
        switch (current.*) {
            .split => |*s| {
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

pub fn splitView(self: *Tree, id: u64, direction: Direction, after: bool) !u64 {
    const new_id = self.nextId();

    if (self.root == .view) {
        if (self.root.view.id != id) return error.NotFound;
        try self.root._split(self.alloc, new_id, direction, after);
        return new_id;
    }

    var path = self.findPath(id) orelse return error.NotFound;
    defer path.deinit(self.alloc);

    const parent = self.getParentFromPath(path.items) orelse return error.PathIsBroken;
    const index = path.items[path.items.len - 1];

    switch (parent.*) {
        .split => |*split| {
            if (split.direction == direction) {
                try split.insertChild(
                    if (after) index + 1 else index,
                    Node{ .view = View.init(new_id) },
                );
            } else {
                const node = try split.get(index);
                try node._split(self.alloc, new_id, direction, after);
            }
        },
        .view => return error.PathIsBroken,
    }

    return new_id;
}

pub fn remove(self: *Tree, id: u64) void {
    if (self.root == .view) {
        return;
    }
    var path = self.findPath(id) orelse return;
    defer path.deinit(self.alloc);

    const parent = self.getParentFromPath(path.items) orelse return;
    const index = path.items[path.items.len - 1];

    const removed = parent.removeChild(index);
    removed.deinit();
    self.alloc.destroy(removed);

    if (parent.count() == 1) {
        parent.collapse();
    }
}

const testing = std.testing;

test "init: creates tree with single view" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    try testing.expectEqual(@as(usize, 1), tree.count());
    try testing.expect(tree.root == .view);
    try testing.expectEqual(@as(u64, 0), tree.root.view.id);
}

test "find: locates nested view after splits" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    const id1 = try tree.splitView(0, .horizontal, true);
    const id2 = try tree.splitView(id1, .vertical, true);

    const found0 = tree.find(0);
    const found1 = tree.find(id1);
    const found2 = tree.find(id2);

    try testing.expect(found0 != null);
    try testing.expect(found1 != null);
    try testing.expect(found2 != null);
    try testing.expectEqual(@as(u64, 0), found0.?.view.id);
    try testing.expectEqual(id1, found1.?.view.id);
    try testing.expectEqual(id2, found2.?.view.id);
}

test "find: returns null for nonexistent id" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    try testing.expect(tree.find(999) == null);
}

test "splitView: splits root horizontally after" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    const new_id = try tree.splitView(0, .horizontal, true);

    try testing.expectEqual(@as(u64, 1), new_id);
    try testing.expectEqual(@as(usize, 2), tree.count());
    try testing.expect(tree.root == .split);
    try testing.expectEqual(Direction.horizontal, tree.root.split.direction);
    try testing.expectEqual(@as(u64, 0), tree.root.split.children.items[0].view.id);
    try testing.expectEqual(@as(u64, 1), tree.root.split.children.items[1].view.id);
}

test "splitView: splits root vertically before" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    const new_id = try tree.splitView(0, .vertical, false);

    try testing.expectEqual(@as(u64, 1), new_id);
    try testing.expect(tree.root == .split);
    try testing.expectEqual(Direction.vertical, tree.root.split.direction);
    try testing.expectEqual(@as(u64, 1), tree.root.split.children.items[0].view.id);
    try testing.expectEqual(@as(u64, 0), tree.root.split.children.items[1].view.id);
}

test "splitView: nested split creates new split node" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    _ = try tree.splitView(0, .horizontal, true);
    _ = try tree.splitView(0, .vertical, true);

    try testing.expectEqual(@as(usize, 3), tree.count());
    try testing.expect(tree.root == .split);

    const first_child = tree.root.split.children.items[0];
    try testing.expect(first_child.* == .split);
    try testing.expectEqual(Direction.vertical, first_child.split.direction);
}

test "splitView: same direction adds sibling" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    _ = try tree.splitView(0, .horizontal, true);
    _ = try tree.splitView(0, .horizontal, true);

    try testing.expectEqual(@as(usize, 3), tree.count());
    try testing.expect(tree.root == .split);
    try testing.expectEqual(@as(usize, 3), tree.root.split.children.items.len);
}

test "splitView: returns error for nonexistent id" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    const result = tree.splitView(999, .horizontal, true);
    try testing.expectError(error.NotFound, result);
}

test "findPath: returns correct path to nested node" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    _ = try tree.splitView(0, .horizontal, true);

    var path0 = tree.findPath(0) orelse return error.TestUnexpectedResult;
    defer path0.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), path0.items.len);
    try testing.expectEqual(@as(usize, 0), path0.items[0]);

    var path1 = tree.findPath(1) orelse return error.TestUnexpectedResult;
    defer path1.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), path1.items.len);
    try testing.expectEqual(@as(usize, 1), path1.items[0]);
}

test "findPath: returns null for nonexistent id" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    try testing.expect(tree.findPath(999) == null);
}

test "getNodeFromPath: empty path returns root" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    const node = tree.getNodeFromPath(&.{});
    try testing.expect(node != null);
    try testing.expect(node.? == &tree.root);
}

test "getNodeFromPath: valid path returns correct node" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    _ = try tree.splitView(0, .horizontal, true);

    const node0 = tree.getNodeFromPath(&.{0});
    const node1 = tree.getNodeFromPath(&.{1});

    try testing.expect(node0 != null);
    try testing.expect(node1 != null);
    try testing.expectEqual(@as(u64, 0), node0.?.view.id);
    try testing.expectEqual(@as(u64, 1), node1.?.view.id);
}

test "getNodeFromPath: invalid path returns null" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    _ = try tree.splitView(0, .horizontal, true);

    try testing.expect(tree.getNodeFromPath(&.{99}) == null);
    try testing.expect(tree.getNodeFromPath(&.{ 0, 0 }) == null);
}

test "count: tracks views through splits" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    try testing.expectEqual(@as(usize, 1), tree.count());

    _ = try tree.splitView(0, .horizontal, true);
    try testing.expectEqual(@as(usize, 2), tree.count());

    _ = try tree.splitView(0, .vertical, true);
    try testing.expectEqual(@as(usize, 3), tree.count());

    _ = try tree.splitView(1, .horizontal, false);
    try testing.expectEqual(@as(usize, 4), tree.count());
}

test "remove: removes view and collapses parent with one child" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    _ = try tree.splitView(0, .horizontal, true);
    try testing.expectEqual(@as(usize, 2), tree.count());

    tree.remove(1);

    try testing.expectEqual(@as(usize, 1), tree.count());
    try testing.expect(tree.root == .view);
    try testing.expectEqual(@as(u64, 0), tree.root.view.id);
}

test "remove: keeps split with multiple children" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    _ = try tree.splitView(0, .horizontal, true);
    _ = try tree.splitView(0, .horizontal, true);
    try testing.expectEqual(@as(usize, 3), tree.count());

    tree.remove(1);

    try testing.expectEqual(@as(usize, 2), tree.count());
    try testing.expect(tree.root == .split);
    try testing.expectEqual(@as(usize, 2), tree.root.split.children.items.len);
}

test "remove: does nothing for nonexistent id" {
    var tree = Tree.init(testing.allocator);
    defer tree.deinit();

    _ = try tree.splitView(0, .horizontal, true);
    try testing.expectEqual(@as(usize, 2), tree.count());

    tree.remove(999);

    try testing.expectEqual(@as(usize, 2), tree.count());
}
