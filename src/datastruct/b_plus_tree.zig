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
        Leaf: struct { items: [CAPACITY]V = undefined, keys: [CAPACITY]K = undefined, len: u16 = 0, next: ?*Self = null },

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
                        var idx: u16 = 1;

                        while (idx < internal.len) {
                            switch (comp(other.keys()[0], internal.keys[idx])) {
                                .eq => {
                                    return error.DuplicateKey;
                                },
                                .gt => {
                                    idx += 1;
                                },
                                .lt => {
                                    break;
                                },
                            }
                        }

                        const node_to_append = try internal.childs[idx - 1].append_recursive(other, alloc);

                        internal.keys[idx - 1] = internal.childs[idx - 1].keys()[0];

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
                        right_node.* = .{ .Internal = .{ .childs = right_items, .keys = right_keys, .len = childs_len - mid, .height = internal.height } };
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
                            switch (comp(leaf.keys[idx], other_leaf.keys[other_idx])) {
                                .lt => {
                                    temp_keys[temp] = leaf.keys[idx];
                                    temp_items[temp] = leaf.items[idx];
                                    idx += 1;
                                },
                                .gt => {
                                    temp_keys[temp] = other_leaf.keys[other_idx];
                                    temp_items[temp] = other_leaf.items[other_idx];
                                    other_idx += 1;
                                },
                                .eq => {
                                    return error.DuplicateKey;
                                },
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

                        const original_next_leaf = leaf.next;

                        leaf.items = left_items;
                        leaf.keys = left_keys;
                        leaf.len = mid;

                        const right_node = try alloc.create(Self);
                        right_node.* = .{ .Leaf = .{ .items = right_items, .keys = right_keys, .len = new_len - mid, .next = original_next_leaf } };

                        leaf.next = right_node;

                        return right_node;
                    } else {
                        const temp_keys = try alloc.alloc(K, new_len);
                        defer alloc.free(temp_keys);

                        const temp_items = try alloc.alloc(V, new_len);
                        defer alloc.free(temp_items);

                        var idx: usize = 0;
                        var other_idx: usize = 0;
                        var temp_ptr: usize = 0;

                        while (idx < leaf.len and other_idx < other_leaf.len) {
                            switch (comp(leaf.keys[idx], other_leaf.keys[other_idx])) {
                                .lt => {
                                    temp_keys[temp_ptr] = leaf.keys[idx];
                                    temp_items[temp_ptr] = leaf.items[idx];
                                    idx += 1;
                                },
                                .gt => {
                                    temp_keys[temp_ptr] = other_leaf.keys[other_idx];
                                    temp_items[temp_ptr] = other_leaf.items[other_idx];
                                    other_idx += 1;
                                },
                                .eq => {
                                    return error.DuplicateKey;
                                },
                            }
                            temp_ptr += 1;
                        }

                        while (idx < leaf.len) {
                            temp_keys[temp_ptr] = leaf.keys[idx];
                            temp_items[temp_ptr] = leaf.items[idx];
                            idx += 1;
                            temp_ptr += 1;
                        }

                        while (other_idx < other_leaf.len) {
                            temp_keys[temp_ptr] = other_leaf.keys[other_idx];
                            temp_items[temp_ptr] = other_leaf.items[other_idx];
                            other_idx += 1;
                            temp_ptr += 1;
                        }

                        for (0..new_len - 1) |i| {
                            if (comp(temp_keys[i], temp_keys[i + 1]) == .eq) {
                                return error.DuplicateKey;
                            }
                        }

                        @memcpy(leaf.keys[0..new_len], temp_keys[0..new_len]);
                        @memcpy(leaf.items[0..new_len], temp_items[0..new_len]);
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

        pub fn delete(self: *Self, key: K) !V {
            _ = self;
            _ = key;
        }
    };
}

pub fn BPlusTree(comptime K: type, comptime V: type, comptime comp: *const fn (a: K, b: K) std.math.Order) type {
    const Node = NodeType(K, V, comp);

    return struct {
        const Self = @This();

        root: *Node,
        alloc: Allocator,

        pub const Iterator = struct {
            leaf: ?*Node,
            index: usize,

            pub fn init(tree: *const Self) Iterator {
                var current: ?*Node = tree.root;
                while (current) |node| {
                    switch (node.*) {
                        .Internal => |*internal| {
                            if (internal.len == 0) {
                                current = null;
                                break;
                            }
                            current = internal.childs[0];
                        },
                        .Leaf => {
                            return .{ .leaf = current, .index = 0 };
                        },
                    }
                }
                return .{ .leaf = null, .index = 0 };
            }

            pub fn next(self: *Iterator) ?struct { key: K, value: V } {
                while (self.leaf) |node| {
                    if (node.is_leaf()) {
                        const leaf = node.Leaf;
                        if (self.index < leaf.len) {
                            self.index += 1;
                            return .{ .key = leaf.keys[self.index - 1], .value = leaf.items[self.index - 1] };
                        } else {
                            self.leaf = leaf.next;
                            self.index = 0;
                        }
                    } else {
                        unreachable;
                    }
                }
                return null;
            }
        };

        pub fn init(alloc: Allocator) !Self {
            const root = try alloc.create(Node);
            root.* = .{ .Leaf = .{} };

            return .{ .root = root, .alloc = alloc };
        }

        pub fn deinit(self: Self) void {
            self.root.destroy(self.alloc);
        }

        pub fn insert(self: *Self, key: K, value: V) Error!void {
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

        pub fn remove(self: *Self, key: K) !V {
            return self.root.delete(key);
        }

        pub fn iter(self: *Self) Iterator {
            return Iterator.init(self);
        }

        pub fn print(self: *const Self) !void {
            var queue = try std.ArrayList(*Node).initCapacity(self.alloc, 0);
            defer queue.deinit(self.alloc);

            if (self.root.len() == 0) {
                std.debug.print("Tree is empty.\n", .{});
                return;
            }

            try queue.append(self.alloc, self.root);

            while (queue.items.len > 0) {
                var next_queue = try std.ArrayList(*Node).initCapacity(self.alloc, 0);
                defer next_queue.deinit(self.alloc);

                while (queue.items.len > 0) {
                    const node = queue.orderedRemove(0);
                    if (!node.is_leaf()) {
                        const internal = node.Internal;
                        std.debug.print("{s}", .{"{ "});
                        for (0..internal.len) |i| {
                            std.debug.print("{any}", .{internal.keys[i]});
                            if (i < internal.len - 1) {
                                std.debug.print(", ", .{});
                            }
                            try next_queue.append(self.alloc, internal.childs[i]);
                        }
                        std.debug.print("{s}", .{" } "});
                    } else {
                        const leaf = node.Leaf;
                        std.debug.print("{s}", .{"{ "});
                        for (0..leaf.len) |i| {
                            std.debug.print("{{ {any}, {any} }}", .{ leaf.keys[i], leaf.items[i] });
                            if (i < leaf.len - 1) {
                                std.debug.print(", ", .{});
                            }
                        }
                        std.debug.print("{s}", .{" } "});
                        std.debug.print("\n", .{});
                    }
                }
                std.debug.print("\n", .{});

                queue.clearRetainingCapacity();
                for (next_queue.items) |node| {
                    try queue.append(self.alloc, node);
                }
            }
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

    try tree.insert(0, 1);

    try testing.expect(!tree.root.is_empty());
    try testing.expect(tree.root.is_leaf());

    for (1..13) |key| {
        try tree.insert(key, key + 1);
    }

    try testing.expect(!tree.root.is_leaf());

    try testing.expectEqual(12, tree.get(11));

    for (13..20) |key| {
        try tree.insert(key, key + 1);
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
        try tree.insert(key, key + 1);
    }

    try testing.expectEqual(tree.root.height(), 1);

    try tree.insert(89, 90);

    try testing.expectEqual(tree.root.height(), 2);
}

test "B+ Tree get operation" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const T = BPlusTree(usize, usize, test_comp);
    var tree = try T.init(alloc);
    defer tree.deinit();

    for (0..90) |key| {
        try tree.insert(key, key + 1);
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
        try tree.insert(key, key + 1);
    }

    for (0..90) |key| {
        const value = try tree.get_ref(key);
        value.* = key * 4;
        try testing.expectEqual(key * 4, tree.get(key));
    }
}

test "B+ Tree leaf traversal" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const T = BPlusTree(usize, usize, test_comp);
    var tree = try T.init(alloc);
    defer tree.deinit();

    for (0..20) |key| {
        try tree.insert(key, key + 100);
    }

    var iter = tree.iter();
    var expected_key: usize = 0;
    while (iter.next()) |n| {
        try testing.expectEqual(expected_key, n.key);
        try testing.expectEqual(expected_key + 100, n.value);
        expected_key += 1;
    }
    try testing.expectEqual(20, expected_key);
}

test "B+ Tree insert a duplicate key" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const T = BPlusTree(usize, usize, test_comp);
    var tree = try T.init(alloc);
    defer tree.deinit();

    try tree.insert(0, 1);
    try testing.expectEqual(tree.insert(0, 2), error.DuplicateKey);

    try testing.expectEqual(1, tree.get(0));

    for (1..90) |key| {
        try tree.insert(key, key + 1);
    }

    for (20..30) |key| {
        try testing.expectEqual(tree.insert(key, 2), error.DuplicateKey);
        try testing.expectEqual(tree.get(key), key + 1);
    }

    try tree.print();
}
