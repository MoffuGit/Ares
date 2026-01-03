const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const panic = std.debug.panic;

const BASE: usize = 6;
const CAPACITY: usize = 2 * BASE;

pub const Error = error{
    OutOfMemory,
    DuplicateKey,
    NotFound,
} || Allocator.Error;

pub fn NodeType(comptime K: type, comptime V: type, comp: *const fn (a: K, b: K) std.math.Order) type {
    return union(enum) {
        const Self = @This();

        Internal: struct { childs: [CAPACITY]*Self = undefined, keys: [CAPACITY]K = undefined, len: u16 = 0, height: usize = 0 },
        Leaf: struct { items: [CAPACITY]V = undefined, keys: [CAPACITY]K = undefined, len: u16 = 0 },

        pub fn add_item(self: *Self, key: K, value: V) Error!void {
            switch (self.*) {
                .Internal => panic("items can be only added to leaf nodes", .{}),
                .Leaf => |*leaf| {
                    if (leaf.len == CAPACITY) {
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

        pub fn add_child(self: *Self, key: K, child: *Self) Error!void {
            switch (self.*) {
                .Internal => |*int| {
                    if (int.len == int.childs.len) {
                        return error.OutOfMemory;
                    }

                    var idx: u16 = int.len;

                    while (idx > 0) : (idx -= 1) {
                        switch (comp(key, int.keys[idx - 1])) {
                            .gt => break,
                            .lt => {
                                int.keys[idx] = int.keys[idx - 1];
                                int.childs[idx] = int.childs[idx - 1];
                            },
                            .eq => return error.DuplicateKey,
                        }
                    }

                    int.keys[idx] = key;
                    int.childs[idx] = child;
                    int.len += 1;
                },
                .Leaf => panic("childs can be only added to internal nodes", .{}),
            }
        }

        pub fn items(self: Self) *const [CAPACITY]V {
            switch (self) {
                .Internal => panic("Internal nodes have not items", .{}),
                .Leaf => |leaf| return &leaf.items,
            }
        }

        pub fn keys(self: Self) *const [CAPACITY]K {
            switch (self) {
                .Internal => |*internal| {
                    return &internal.keys;
                },
                .Leaf => |*leaf| {
                    return &leaf.keys;
                },
            }
        }

        pub fn is_empty(self: Self) bool {
            switch (self) {
                .Internal => return false,
                .Leaf => |leaf| {
                    return leaf.len == 0;
                },
            }
        }

        pub fn len(self: Self) u16 {
            switch (self) {
                .Internal => |int| return int.len,
                .Leaf => |leaf| return leaf.len,
            }
        }

        pub fn is_leaf(self: Self) bool {
            switch (self) {
                .Internal => return false,
                .Leaf => return true,
            }
        }

        pub fn height(self: Self) usize {
            switch (self) {
                .Internal => |internal| return internal.height,
                .Leaf => return 0,
            }
        }

        pub fn is_underflowing(self: Self) bool {
            return self.len() < BASE;
        }

        pub fn childs(self: Self) *const [CAPACITY]*Self {
            switch (self) {
                .Internal => |internal| return &internal.childs,
                .Leaf => panic("Leaf nodes have no childs", .{}),
            }
        }

        pub fn destroy(self: *Self, alloc: Allocator) void {
            switch (self.*) {
                .Internal => |*internal| {
                    if (internal.len > 0) {
                        for (0..internal.len) |idx| {
                            internal.childs[idx].destroy(alloc);
                        }
                    }
                },
                else => {},
            }
            alloc.destroy(self);
        }

        pub fn append(self: *Self, other: Self, alloc: Allocator) Error!void {
            if (self.is_empty()) {
                self.* = other;
            } else if (!other.is_leaf() or other.items().len != 0) {
                if (self.height() < other.height()) {
                    for (other.childs()) |node| {
                        try self.append(node.*, alloc);
                    }
                } else if (try self.append_recursive(other, alloc)) |right| {
                    const left = try alloc.create(Self);
                    left.* = self.*;
                    self.* = try Self.from_child_nodes(left, right);
                }
            }
        }

        pub fn from_child_nodes(left: *Self, right: *Self) !Self {
            var childrens: [CAPACITY]*Self = undefined;
            childrens[0] = left;
            childrens[1] = right;

            var _keys: [CAPACITY]K = undefined;
            _keys[0] = left.keys()[0];
            _keys[1] = right.keys()[0];

            return .{ .Internal = .{ .height = left.height() + 1, .len = 2, .childs = childrens, .keys = _keys } };
        }

        pub fn append_recursive(self: *Self, other: Self, alloc: Allocator) Error!?*Self {
            switch (self.*) {
                .Internal => |*internal| {
                    const height_delta = internal.height - other.height();

                    var keys_to_append: [CAPACITY]K = undefined;
                    var childs_to_append: [CAPACITY]*Self = undefined;

                    var len_to_append: u16 = 0;

                    if (height_delta == 0) {
                        @memcpy(&keys_to_append, other.keys());
                        @memcpy(&childs_to_append, other.childs());
                        len_to_append = other.len();
                    } else if (height_delta == 1 and !other.is_underflowing()) {
                        keys_to_append[0] = other.keys()[0];
                        const new_other_node = try alloc.create(Self);
                        new_other_node.* = other;
                        childs_to_append[0] = new_other_node;
                        len_to_append = 1;
                    } else {
                        var child_idx: u16 = 0;
                        const other_node_min_key = other.keys()[0];
                        while (child_idx < internal.len - 1) {
                            if (comp(other_node_min_key, internal.keys[child_idx]) == .lt) {
                                break;
                            }
                            child_idx += 1;
                        }
                        const node_to_append = try internal.childs[child_idx].append_recursive(other, alloc);

                        internal.keys[child_idx] = internal.childs[child_idx].keys()[0];
                        if (node_to_append) |split| {
                            keys_to_append[0] = split.keys()[0];
                            childs_to_append[0] = split;
                            len_to_append = 1;
                        }
                    }

                    const childs_len = internal.len + len_to_append;
                    if (childs_len > CAPACITY) {
                        const temp_keys = try alloc.alloc(K, childs_len);
                        defer alloc.free(temp_keys);

                        const temp_items = try alloc.alloc(*Self, childs_len);
                        defer alloc.free(temp_items);

                        var idx: usize = 0;
                        var other_idx: usize = 0;
                        var temp: usize = 0;

                        while (idx < internal.len and other_idx < len_to_append) {
                            if (comp(internal.keys[idx], keys_to_append[other_idx]) != .gt) {
                                temp_keys[temp] = internal.keys[idx];
                                temp_items[temp] = internal.childs[idx];
                                idx += 1;
                            } else {
                                temp_keys[temp] = keys_to_append[other_idx];
                                temp_items[temp] = childs_to_append[other_idx];
                                other_idx += 1;
                            }
                            temp += 1;
                        }

                        while (idx < internal.len) {
                            temp_keys[temp] = internal.keys[idx];
                            temp_items[temp] = internal.childs[idx];
                            idx += 1;
                            temp += 1;
                        }

                        while (other_idx < len_to_append) {
                            temp_keys[temp] = keys_to_append[other_idx];
                            temp_items[temp] = childs_to_append[other_idx];
                            other_idx += 1;
                            temp += 1;
                        }

                        var left_keys: [CAPACITY]K = undefined;
                        var left_items: [CAPACITY]*Self = undefined;

                        var right_keys: [CAPACITY]K = undefined;
                        var right_items: [CAPACITY]*Self = undefined;

                        const mid = (childs_len + childs_len % 2) / 2;

                        @memcpy(left_keys[0..mid], temp_keys[0..mid]);
                        @memcpy(left_items[0..mid], temp_items[0..mid]);

                        @memcpy(right_keys[0 .. childs_len - mid], temp_keys[mid..childs_len]);
                        @memcpy(right_items[0 .. childs_len - mid], temp_items[mid..childs_len]);

                        internal.childs = left_items;
                        internal.keys = left_keys;
                        internal.len = mid;

                        const right_node = try alloc.create(Self);
                        right_node.* = .{ .Internal = .{ .childs = right_items, .keys = right_keys, .len = childs_len - mid } };
                        return right_node;
                    } else {
                        var target: usize = childs_len;
                        var idx: usize = internal.len;
                        var append_idx: usize = len_to_append;

                        while (target > 0) {
                            target -= 1;

                            if (append_idx > 0 and (idx == 0 or comp(keys_to_append[append_idx - 1], internal.keys[idx - 1]) == .gt)) {
                                append_idx -= 1;
                                internal.keys[target] = keys_to_append[append_idx];
                                internal.childs[target] = childs_to_append[append_idx];
                            } else {
                                idx -= 1;
                                internal.keys[target] = internal.keys[idx];
                                internal.childs[target] = internal.childs[idx];
                            }
                        }

                        internal.len = childs_len;
                    }
                },
                .Leaf => |*leaf| {
                    assert(other.is_leaf());
                    const other_leaf = other.Leaf;

                    const new_len = leaf.len + other_leaf.len;

                    if (new_len > CAPACITY) {
                        const temp_keys = try alloc.alloc(K, new_len);
                        defer alloc.free(temp_keys);

                        const temp_items = try alloc.alloc(V, new_len);
                        defer alloc.free(temp_items);

                        var idx: usize = 0;
                        var other_idx: usize = 0;
                        var temp: usize = 0;

                        while (idx < leaf.len and other_idx < other_leaf.len) {
                            if (comp(leaf.keys[idx], other_leaf.keys[other_idx]) != .gt) {
                                temp_keys[temp] = leaf.keys[idx];
                                temp_items[temp] = leaf.items[idx];
                                idx += 1;
                            } else {
                                temp_keys[temp] = other_leaf.keys[other_idx];
                                temp_items[temp] = other_leaf.items[other_idx];
                                other_idx += 1;
                            }
                            temp += 1;
                        }

                        while (idx < leaf.len) {
                            temp_keys[temp] = leaf.keys[idx];
                            temp_items[temp] = leaf.items[idx];
                            idx += 1;
                            temp += 1;
                        }

                        while (other_idx < other_leaf.len) {
                            temp_keys[temp] = other_leaf.keys[other_idx];
                            temp_items[temp] = other_leaf.items[other_idx];
                            other_idx += 1;
                            temp += 1;
                        }

                        var left_keys: [CAPACITY]K = undefined;
                        var left_items: [CAPACITY]V = undefined;

                        var right_keys: [CAPACITY]K = undefined;
                        var right_items: [CAPACITY]V = undefined;

                        const mid = (new_len + new_len % 2) / 2;

                        @memcpy(left_keys[0..mid], temp_keys[0..mid]);
                        @memcpy(left_items[0..mid], temp_items[0..mid]);

                        @memcpy(right_keys[0 .. new_len - mid], temp_keys[mid..new_len]);
                        @memcpy(right_items[0 .. new_len - mid], temp_items[mid..new_len]);

                        leaf.items = left_items;
                        leaf.keys = left_keys;
                        leaf.len = mid;

                        const right_node = try alloc.create(Self);
                        right_node.* = .{ .Leaf = .{ .items = right_items, .keys = right_keys, .len = new_len - mid } };
                        return right_node;
                    } else {
                        var target: usize = new_len;
                        var idx: usize = leaf.len;
                        var other_idx: usize = other_leaf.len;

                        while (target > 0) {
                            target -= 1;

                            if (other_idx > 0 and (idx == 0 or comp(other_leaf.keys[other_idx - 1], leaf.keys[idx - 1]) == .gt)) {
                                other_idx -= 1;
                                leaf.keys[target] = other_leaf.keys[other_idx];
                                leaf.items[target] = other_leaf.items[other_idx];
                            } else {
                                idx -= 1;
                                leaf.keys[target] = leaf.keys[idx];
                                leaf.items[target] = leaf.items[idx];
                            }
                        }

                        leaf.len = new_len;
                    }
                },
            }

            return null;
        }

        pub fn find(self: *Self, key: K) Error!V {
            switch (self.*) {
                .Leaf => |*leaf| {
                    var i: u16 = 0;
                    while (i < leaf.len) {
                        switch (comp(key, leaf.keys[i])) {
                            .eq => return leaf.items[i],
                            .lt => break,
                            .gt => i += 1,
                        }
                    }
                    return error.NotFound;
                },
                .Internal => |*internal| {
                    var idx: u16 = 1;

                    while (idx < internal.len) {
                        switch (comp(key, internal.keys[idx])) {
                            .eq => {
                                idx += 1;
                                break;
                            },
                            .gt => {
                                idx += 1;
                            },
                            .lt => {
                                break;
                            },
                        }
                    }

                    return internal.childs[idx - 1].find(key);
                },
            }
        }

        pub fn find_mut(self: *Self, key: K) Error!*V {
            switch (self.*) {
                .Leaf => |*leaf| {
                    var i: u16 = 0;
                    while (i < leaf.len) {
                        switch (comp(key, leaf.keys[i])) {
                            .eq => return &leaf.items[i],
                            .lt => break,
                            .gt => i += 1,
                        }
                    }
                    return error.NotFound;
                },
                .Internal => |*internal| {
                    var idx: u16 = 1;

                    while (idx < internal.len) {
                        switch (comp(key, internal.keys[idx])) {
                            .eq => {
                                idx += 1;
                                break;
                            },
                            .gt => {
                                idx += 1;
                            },
                            .lt => {
                                break;
                            },
                        }
                    }

                    return internal.childs[idx - 1].find_mut(key);
                },
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
            self.root.destroy(self.alloc);
        }

        pub fn push(self: *Self, key: K, value: V) Error!void {
            var node: Node = Node{ .Leaf = .{} };

            try node.add_item(key, value);

            try self.root.append(node, self.alloc);
        }

        pub fn get(self: *Self, key: K) !V {
            return self.root.find(key);
        }

        pub fn get_ref(self: *Self, key: K) !*V {
            return self.root.find_mut(key);
        }
    };
}

fn test_comp(a: usize, b: usize) std.math.Order {
    return std.math.order(a, b);
}

test "B+ Tree push operation and splitting" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const T = BPlusTree(usize, usize, test_comp);
    var tree = try T.init(alloc);
    defer tree.deinit();

    try tree.push(0, 1);

    try testing.expect(!tree.root.is_empty());
    try testing.expect(tree.root.is_leaf());

    for (1..13) |key| {
        try tree.push(key, key + 1);
    }

    try testing.expect(!tree.root.is_leaf());

    try testing.expectEqual(12, tree.get(11));

    for (13..20) |key| {
        try tree.push(key, key + 1);
    }

    try testing.expectEqual(tree.root.len(), 3);
    try testing.expectEqual(12, tree.get(11));
}

test "B+ Tree push operation until height is 2" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const T = BPlusTree(usize, usize, test_comp);
    var tree = try T.init(alloc);
    defer tree.deinit();

    for (0..89) |key| {
        try tree.push(key, key + 1);
    }

    try testing.expectEqual(tree.root.height(), 1);

    try tree.push(89, 90);

    try testing.expectEqual(tree.root.height(), 2);
}

test "B+ Tree get operation" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const T = BPlusTree(usize, usize, test_comp);
    var tree = try T.init(alloc);
    defer tree.deinit();

    for (0..90) |key| {
        try tree.push(key, key + 1);
    }

    for (0..90) |key| {
        try testing.expectEqual(key + 1, tree.get(key));
    }
}

test "B+ Tree get ref operation" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const T = BPlusTree(usize, usize, test_comp);
    var tree = try T.init(alloc);
    defer tree.deinit();

    for (0..90) |key| {
        try tree.push(key, key + 1);
    }

    for (0..90) |key| {
        const value = try tree.get_ref(key);
        value.* = key * 4;
        try testing.expectEqual(key * 4, tree.get(key));
    }
}
