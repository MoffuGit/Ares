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
