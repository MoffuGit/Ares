const std = @import("std");
const datastruct = @import("../datastruct.zig");
const btree = datastruct.btree;
const Allocator = std.mem.Allocator;

pub const Entry = struct {
    id: u64,
    path: []const u8,
};

const Entries = btree.BPlusTree([]const u8, Entry, entryOrder);

fn entryOrder(a: []const u8, b: []const u8) std.math.Order {
    return std.mem.order(u8, a, b);
}

const Snapshot = @This();

entries: Entries,

abs_root: []u8,
root_name: []u8,
next_id: u64,

pub fn init(self: *Snapshot, abs_root: []u8, root_name: []u8, gpa: Allocator) !void {
    self.* = .{
        .abs_root = abs_root,
        .root_name = root_name,
        .entries = undefined,
        .next_id = 0,
    };

    try self.entries.init(gpa);
    _ = try self.entries.insert(gpa, root_name, .{ .id = self.next_id, .path = root_name });
    self.next_id += 1;
}

pub fn clone(self: *Snapshot, from: *Snapshot, gpa: Allocator) !void {
    self.* = from.*;
    self.entries = try from.entries.clone(gpa);
}

pub fn insert(self: *Snapshot, gpa: Allocator, path_name: []const u8) !void {
    _ = try self.entries.insert(gpa, path_name, .{ .id = self.next_id, .path = path_name });
    self.next_id += 1;
}

pub fn deinit(self: *Snapshot, gpa: Allocator) void {
    self.entries.deinit(gpa);
}
