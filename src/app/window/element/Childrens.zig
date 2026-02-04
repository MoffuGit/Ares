const std = @import("std");
const Element = @import("mod.zig");
const Allocator = std.mem.Allocator;

pub const Childrens = @This();

by_order: std.ArrayList(*Element) = .{},
by_z_index: std.ArrayList(*Element) = .{},

pub fn len(self: *Childrens) usize {
    return self.by_order.items.len;
}

pub fn deinit(self: *Childrens, alloc: std.mem.Allocator) void {
    self.by_order.deinit(alloc);
    self.by_z_index.deinit(alloc);
}

pub fn add(self: *Childrens, child: *Element, alloc: Allocator) !void {
    try self.by_order.append(alloc, child);
    try self.insertByZIndex(child, alloc);
}

pub fn insert(self: *Childrens, child: *Element, index: usize, alloc: Allocator) !void {
    try self.by_order.insert(alloc, index, child);
    try self.insertByZIndex(child, alloc);
}

fn insertByZIndex(self: *Childrens, child: *Element, alloc: Allocator) !void {
    const insert_idx = blk: {
        var idx: usize = 0;
        for (self.by_z_index.items) |c| {
            if (c.zIndex > child.zIndex) break :blk idx;
            idx += 1;
        }
        break :blk idx;
    };
    try self.by_z_index.insert(alloc, insert_idx, child);
}

pub fn remove(self: *Childrens, num: u64) ?*Element {
    var removed_child: ?*Element = null;

    for (self.by_order.items, 0..) |child, idx| {
        if (num == child.num) {
            removed_child = self.by_order.orderedRemove(idx);
            break;
        }
    }

    for (self.by_z_index.items, 0..) |child, idx| {
        if (num == child.num) {
            _ = self.by_z_index.orderedRemove(idx);
            break;
        }
    }

    return removed_child;
}
