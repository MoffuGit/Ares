const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const panic = std.debug.panic;

const BASE: usize = 6;

//i have a notion of what i need to do
//but i need to keep reading over the zed sumtree
//and teh zig b plus tree repo
//with that two things i can write my own b plus tree
//
pub const Error = error{
    OutOfMemory,
    DuplicateKey,
} || Allocator.Error;

pub fn NodeType(comptime K: type, comptime V: type, comp: *const fn (a: K, b: K) std.math.Order) type {
    return union(enum) {
        const Self = @This();

        Internal: struct { childs: [2 * BASE]*Self = undefined, keys: [2 * BASE - 1]K = undefined, len: u16 = 0 },
        Leaf: struct { items: [2 * BASE - 1]V = undefined, keys: [2 * BASE - 1]K = undefined, len: u16 = 0, next: ?*Self = null },

        pub fn add_item(self: *Self, key: K, value: V) Error!void {
            switch (self.*) {
                .Internal => panic("items can be only added to leaf nodes", .{}),
                .Leaf => {
                    const leaf = &self.*.Leaf;
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
        pub fn is_empty(self: *Self) bool {
            switch (self.*) {
                .Internal => {
                    const internal = &self.*.Internal;
                    return internal.len == 0;
                },
                .Leaf => {
                    const leaf = &self.*.Leaf;
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
            self.alloc.destroy(self.root);
        }

        pub fn push(self: *Self, key: K, value: V) Error!void {
            const node = try self.alloc.create(Node);
            defer self.alloc.destroy(node);

            node.* = .{ .Leaf = .{} };

            assert(node.is_empty());

            node.add_item(key, value) catch {};

            try self.append(self.root, node);
        }

        pub fn append(_: *Self, parent: *Node, child: *Node) Error!void {
            if (parent.is_empty()) {
                parent.* = child.*;
            } else {
                //add heigth to a node,
                //check if the height of parent is less than the height of child
                //if is true, get down one level of child and try to append that trees
                //else
                //try to push the child tree to the parent tree, for that you probably are going to need to split the tree
                //and join it latter,
                //one detail is that I'm not sure of how should i split the tree
                //or how to ask for a sibling value, but that ok, i can read it from zed
                //or from the other repo with the impl of a b + tree
            }
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
}
