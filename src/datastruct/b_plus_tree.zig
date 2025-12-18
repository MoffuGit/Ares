const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const panic = std.debug.panic;

const BASE: usize = 6;
const MAXCHILDS: usize = 2 * BASE;
const CAPACITY: usize = MAXCHILDS - 1;

pub const Error = error{
    OutOfMemory,
    DuplicateKey,
} || Allocator.Error;

pub fn NodeType(comptime K: type, comptime V: type, comp: *const fn (a: K, b: K) std.math.Order) type {
    return union(enum) {
        const Self = @This();

        Internal: struct { childs: [MAXCHILDS]*Self = undefined, keys: [CAPACITY]K = undefined, len: u16 = 0, height: usize = 0 },
        Leaf: struct { items: [CAPACITY]V = undefined, keys: [CAPACITY]K = undefined, len: u16 = 0, next: ?*Self = null },

        pub fn add_item(self: *Self, key: K, value: V) Error!void {
            switch (self.*) {
                .Internal => panic("items can be only added to leaf nodes", .{}),
                .Leaf => |*leaf| {
                    if (leaf.len == leaf.items.len) {
                        return error.OutOfMemory;
                    }

                    var idx: u16 = leaf.len;

                    while (idx > 0) : (idx -= 1) {
                        switch (comp(key, leaf.keys[idx - 1])) {
                            .gt => break,
                            .lt => {
                                leaf.keys[idx] = leaf.keys[idx - 1];
                                leaf.items[idx] = leaf.items[idx - 1];
                            },
                            .eq => return error.DuplicateKey,
                        }
                    }

                    leaf.keys[idx] = key;
                    leaf.items[idx] = value;
                    leaf.len += 1;
                },
            }
        }

        pub fn items(self: *Self) *const [CAPACITY]V {
            switch (self.*) {
                .Internal => panic("Internal nodes have not items", .{}),
                .Leaf => |leaf| return &leaf.items,
            }
        }

        pub fn is_empty(self: *Self) bool {
            switch (self.*) {
                .Internal => return false,
                .Leaf => |leaf| {
                    return leaf.len == 0;
                },
            }
        }

        pub fn is_leaf(self: *Self) bool {
            switch (self.*) {
                .Internal => return false,
                .Leaf => return true,
            }
        }

        pub fn height(self: *Self) usize {
            switch (self.*) {
                .Internal => |internal| return internal.height,
                .Leaf => return 0,
            }
        }

        pub fn childs(self: *Self) *const [MAXCHILDS]*Self {
            switch (self.*) {
                .Internal => |internal| return &internal.childs,
                .Leaf => panic("Leaf nodes have no childs", .{}),
            }
        }
    };
}

pub fn BPlusTree(comptime K: type, comptime V: type, comptime comp: *const fn (a: K, b: K) std.math.Order) type {
    const Node = NodeType(K, V, comp);

    return struct {
        const Self = @This();

        root: *Node,
        alloc: Allocator,

        pub fn init(alloc: Allocator) !Self {
            const root = try alloc.create(Node);
            root.* = .{ .Leaf = .{} };

            return .{ .root = root, .alloc = alloc };
        }

        pub fn deinit(self: Self) void {
            self.destroy_recursive(self.root);
        }

        pub fn destroy_recursive(self: Self, node: *Node) void {
            switch (node.*) {
                .Internal => |*internal| {
                    if (internal.len > 0) {
                        for (0..internal.len) |idx| {
                            self.destroy_recursive(internal.childs[idx]);
                        }
                    }
                    self.alloc.destroy(node);
                },
                .Leaf => {
                    self.alloc.destroy(node);
                },
            }
        }

        pub fn push(self: *Self, key: K, value: V) Error!void {
            const node = try self.alloc.create(Node);
            defer self.alloc.destroy(node);

            node.* = .{ .Leaf = .{} };

            assert(node.is_empty());

            node.add_item(key, value) catch {};

            try self.append(self.root, node);
        }

        pub fn append(self: *Self, parent: *Node, child: *Node) Error!void {
            if (parent.is_empty()) {
                parent.* = child.*;
            } else if (!child.is_leaf() or child.items().len != 0) {
                if (parent.height() < child.height()) {
                    for (child.childs()) |node| {
                        try self.append(parent, node);
                    }
                } else if (try self.append_recursive(parent, child)) |split| {
                    const parent_clone = try self.alloc.create(Node);
                    parent_clone.* = parent.*;
                    const new = try self.from_child_nodes(parent_clone, split);
                    defer self.alloc.destroy(new);
                    parent.* = new.*;
                }
            }
        }

        pub fn append_recursive(self: *Self, parent: *Node, child: *Node) Error!?*Node {
            switch (parent.*) {
                .Internal => {
                    return null;
                },
                .Leaf => |*leaf| {
                    const child_leaf = child.Leaf;

                    const items = leaf.len + child_leaf.len;

                    if (items > CAPACITY) {
                        var left_items: [CAPACITY]V = undefined;
                        var right_items: [CAPACITY]V = undefined;

                        var left_keys: [CAPACITY]K = undefined;
                        var right_keys: [CAPACITY]K = undefined;

                        const mid = (items + items % 2) / 2;

                        var p: usize = 0;
                        var c: usize = 0;

                        for (0..items) |idx| {
                            if (p < leaf.len and (c >= child_leaf.len or comp(leaf.keys[p], child_leaf.keys[c]) == .lt)) {
                                if (idx < mid) {
                                    left_items[idx] = leaf.items[p];
                                    left_keys[idx] = leaf.keys[p];
                                } else {
                                    right_items[idx - mid] = leaf.items[p];
                                    right_keys[idx - mid] = leaf.keys[p];
                                }
                                p += 1;
                            } else if (c < child_leaf.len and (p >= leaf.len or comp(leaf.keys[p], child_leaf.keys[c]) == .gt)) {
                                if (idx < mid) {
                                    left_items[idx] = child_leaf.items[c];
                                    left_keys[idx] = child_leaf.keys[c];
                                } else {
                                    right_items[idx - mid] = child_leaf.items[c];
                                    right_keys[idx - mid] = child_leaf.keys[c];
                                }
                                c += 1;
                            }
                        }

                        leaf.items = left_items;
                        leaf.keys = left_keys;
                        leaf.len = mid;

                        const right_node = try self.alloc.create(Node);
                        right_node.* = .{ .Leaf = .{ .items = right_items, .keys = right_keys, .len = items - mid } };
                        return right_node;
                    } else {
                        var idx: u16 = 0;
                        while (idx < child_leaf.len) : (idx += 1) {
                            const item = child_leaf.items[idx];
                            const key = child_leaf.keys[idx];

                            try parent.add_item(key, item);
                        }
                    }

                    return null;
                },
            }
        }

        pub fn from_child_nodes(self: *Self, left: *Node, right: *Node) Error!*Node {
            const height = left.height() + 1;
            const keys: [CAPACITY]K = undefined;
            var childs: [MAXCHILDS]*Node = undefined;
            childs[0] = left;
            childs[1] = right;
            const node = try self.alloc.create(Node);
            node.* = .{ .Internal = .{ .len = 2, .childs = childs, .height = height, .keys = keys } };

            return node;
        }
    };
}

fn test_comp(a: usize, b: usize) std.math.Order {
    return std.math.order(a, b);
}

test "init B+ tree and first push value" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const T = BPlusTree(usize, usize, test_comp);
    var tree = try T.init(alloc);
    defer tree.deinit();

    try tree.push(0, 1);

    assert(!tree.root.is_empty());
    assert(tree.root.is_leaf());

    try tree.push(1, 1);
    try tree.push(2, 1);
    try tree.push(3, 1);
    try tree.push(4, 1);
    try tree.push(5, 1);
    try tree.push(6, 1);
    try tree.push(7, 1);
    try tree.push(8, 1);
    try tree.push(9, 1);
    try tree.push(10, 1);
    try tree.push(11, 1);
    // try tree.push(12, 1);
    // try tree.push(13, 1);
    // try tree.push(14, 1);

    assert(!tree.root.is_leaf());
}
