const std = @import("std");
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;

pub fn NodeType(comptime K: type, comptime V: type, comptime Context: type) type {
    return struct {
        const Self = @This();
        values: std.ArrayListUnmanaged(V) = .{},
        childrens: std.ArrayHashMap(K, *NodeType(K, V, Context), Context, true),

        pub fn create(alloc: Allocator) !*Self {
            const self = try alloc.create(Self);
            self.* = .{
                .childrens = .init(alloc),
            };
            return self;
        }

        pub fn destroy(self: *Self, alloc: Allocator) void {
            var iter = self.childrens.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.destroy(alloc);
            }

            self.values.deinit(alloc);
            self.childrens.deinit();

            alloc.destroy(self);
        }
    };
}

pub fn Trie(comptime K: type, comptime V: type, comptime Context: type) type {
    const Node = NodeType(K, V, Context);
    return struct {
        const Self = @This();
        root: *Node,
        alloc: Allocator,

        pub fn init(alloc: Allocator) !Self {
            const root = try Node.create(alloc);

            return .{
                .alloc = alloc,
                .root = root,
            };
        }

        pub fn deinit(self: *Self) void {
            self.root.destroy(self.alloc);
        }

        pub fn insert(self: *Self, prefix: []const K, value: V) !void {
            var node = self.root;
            for (prefix) |key| {
                if (!node.childrens.contains(key)) {
                    try node.childrens.put(key, try Node.create(self.alloc));
                }
                node = node.childrens.get(key).?;
            }
            try node.values.append(self.alloc, value);
        }

        pub fn get(self: *Self, prefix: []const K) ?*Node {
            var node = self.root;
            for (prefix) |key| {
                node = node.childrens.get(key) orelse return null;
            }

            return node;
        }

        pub fn name() !void {}

        pub const Iterator = struct {
            stack: std.ArrayListUnmanaged(StackEntry),
            prefix: std.ArrayListUnmanaged(K),
            alloc: Allocator,

            const StackEntry = struct {
                node: *Node,
                child_idx: usize,
                emitted: bool,
            };

            pub const Entry = struct {
                prefix: []const K,
                values: []const V,
            };

            pub fn next(self: *Iterator) Allocator.Error!?Entry {
                while (self.stack.items.len > 0) {
                    const top = &self.stack.items[self.stack.items.len - 1];

                    if (!top.emitted) {
                        top.emitted = true;
                        if (top.node.values.items.len > 0) {
                            return .{ .prefix = self.prefix.items, .values = top.node.values.items };
                        }
                    }

                    const child_keys = top.node.childrens.keys();
                    const child_vals = top.node.childrens.values();
                    if (top.child_idx < child_keys.len) {
                        const idx = top.child_idx;
                        top.child_idx += 1;
                        try self.prefix.append(self.alloc, child_keys[idx]);
                        try self.stack.append(self.alloc, .{ .node = child_vals[idx], .child_idx = 0, .emitted = false });
                    } else {
                        _ = self.stack.pop();
                        if (self.prefix.items.len > 0) {
                            _ = self.prefix.pop();
                        }
                    }
                }
                return null;
            }

            pub fn deinit(self: *Iterator) void {
                self.stack.deinit(self.alloc);
                self.prefix.deinit(self.alloc);
            }
        };

        pub fn iterator(self: *Self) Allocator.Error!Iterator {
            var stack: std.ArrayListUnmanaged(Iterator.StackEntry) = .{};
            try stack.append(self.alloc, .{ .node = self.root, .child_idx = 0, .emitted = false });
            return .{ .stack = stack, .prefix = .{}, .alloc = self.alloc };
        }
    };
}

test "Trie insert" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var trie = try Trie(u8, u32, std.array_hash_map.AutoContext(u8)).init(alloc);
    defer trie.deinit();

    // Insert a value at "abc"
    try trie.insert("abc", 42);

    // Verify intermediate nodes exist but have no values
    const a_node = trie.root.childrens.get('a').?;
    try testing.expectEqual(0, a_node.values.items.len);

    const b_node = a_node.childrens.get('b').?;
    try testing.expectEqual(0, b_node.values.items.len);

    // Verify the leaf node holds the inserted value
    const c_node = b_node.childrens.get('c').?;
    try testing.expectEqual(1, c_node.values.items.len);
    try testing.expectEqual(@as(u32, 42), c_node.values.items[0]);

    // Insert a second value sharing a prefix
    try trie.insert("abd", 99);
    const d_node = b_node.childrens.get('d').?;
    try testing.expectEqual(@as(u32, 99), d_node.values.items[0]);

    // Original value unchanged
    try testing.expectEqual(@as(u32, 42), c_node.values.items[0]);

    // Append another value to the same key
    try trie.insert("abc", 7);
    try testing.expectEqual(2, c_node.values.items.len);
    try testing.expectEqual(@as(u32, 42), c_node.values.items[0]);
    try testing.expectEqual(@as(u32, 7), c_node.values.items[1]);
}

test "Trie get" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var trie = try Trie(u8, u32, std.array_hash_map.AutoContext(u8)).init(alloc);
    defer trie.deinit();

    try trie.insert("hello", 1);
    try trie.insert("help", 2);
    try trie.insert("world", 3);

    // Get existing keys returns the correct values
    try testing.expectEqual(@as(u32, 1), trie.get("hello").?.values.items[0]);
    try testing.expectEqual(@as(u32, 2), trie.get("help").?.values.items[0]);
    try testing.expectEqual(@as(u32, 3), trie.get("world").?.values.items[0]);

    // Get a prefix that exists but has no values
    const hel_node = trie.get("hel").?;
    try testing.expectEqual(0, hel_node.values.items.len);

    // Get a key that doesn't exist returns null
    try testing.expectEqual(null, trie.get("xyz"));
    try testing.expectEqual(null, trie.get("helper"));

    // Get empty prefix returns root (no values)
    try testing.expectEqual(0, trie.get("").?.values.items.len);
}

test "Trie iterator" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var trie = try Trie(u8, u32, std.array_hash_map.AutoContext(u8)).init(alloc);
    defer trie.deinit();

    try trie.insert("ab", 1);
    try trie.insert("ac", 2);
    try trie.insert("b", 3);

    var iter = try trie.iterator();
    defer iter.deinit();

    // DFS order: "ab" -> "ac" -> "b"
    const e1 = (try iter.next()).?;
    try testing.expectEqualSlices(u8, "ab", e1.prefix);
    try testing.expectEqual(@as(u32, 1), e1.values[0]);

    const e2 = (try iter.next()).?;
    try testing.expectEqualSlices(u8, "ac", e2.prefix);
    try testing.expectEqual(@as(u32, 2), e2.values[0]);

    const e3 = (try iter.next()).?;
    try testing.expectEqualSlices(u8, "b", e3.prefix);
    try testing.expectEqual(@as(u32, 3), e3.values[0]);

    try testing.expectEqual(null, try iter.next());
}
