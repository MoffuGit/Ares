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

abs_root: []const u8,
root_name: []const u8,

pub fn init(self: *Snapshot, abs_root: []const u8, root_name: []const u8, gpa: Allocator) !void {
    self.* = .{
        .abs_root = abs_root,
        .root_name = root_name,
        .entries = undefined,
    };

    try self.entries.init(gpa);
}

pub fn clone(self: *Snapshot, from: *Snapshot, gpa: Allocator) !void {
    self.* = from.*;
    self.entries = try from.entries.clone(gpa);
}

pub fn insert(self: *Snapshot, gpa: Allocator, entry: Entry) !void {
    _ = try self.entries.insert(gpa, entry.path, entry);
}

pub fn deinit(self: *Snapshot, gpa: Allocator) void {
    self.entries.deinit(gpa);
}
