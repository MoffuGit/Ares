const std = @import("std");
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;

pub fn NodeType(comptime K: type, comptime V: type, comptime Context: type) type {
    return struct {
        const Self = @This();
        value: ?V = null,
        childrens: std.ArrayHashMap(K, NodeType(K, V), Context, true),
    };
}

pub fn Trie(comptime K: type, comptime V: type, comptime Context: type) type {
    const Node = NodeType(K, V, Context);
    return struct {
        const Self = @This();
        root: *Node,
        alloc: Allocator,
    };
}
