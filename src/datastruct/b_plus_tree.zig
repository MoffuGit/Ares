const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const BASE: usize = 6;

pub fn NodeType(comptime K: type, comptime V: type) type {
    return union(enum) {
        const Self = @This();

        Internal: struct { edge: [2 * BASE]*Self = undefined, keys: [2 * BASE - 1]K = undefined, len: u16 = 0 },
        Leaf: struct { items: [2 * BASE - 1]V = undefined, keys: [2 * BASE - 1]K = undefined, len: u16 = 0, next: ?*Self = null },
        //is_empty
        //is_leaf
        //items
    };
}

pub fn BPlusTree(comptime K: type, comptime V: type, comptime comp: *const fn (a: *K, b: *K) std.math.Order) type {
    _ = comp;
    const Node = NodeType(K, V);

    return struct {
        const Self = @This();

        root: *Node,
        alloc: Allocator,

        pub fn init(alloc: Allocator) !Self {
            const root = try alloc.create(Node);
            root.* = .{ .Internal = .{} };

            return .{ .root = root, .alloc = alloc };
        }

        pub fn deinit(self: Self) void {
            self.alloc.destroy(self.root);
        }

        //push(self, k, t)
        // create a Node
        // and call
        //append(self, node one, node two)
    };
}

fn test_comp(a: *usize, b: *usize) std.math.Order {
    return std.math.order(a.*, b.*);
}

test "init B+ tree" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const T = BPlusTree(usize, usize, test_comp);
    const tree = try T.init(alloc);
    defer tree.deinit();
}
