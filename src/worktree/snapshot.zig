const std = @import("std");
const datastruct = @import("../datastruct.zig");
const btree = datastruct.btree;
const Allocator = std.mem.Allocator;

pub const Entry = struct {
    id: u64,
    // file_type: []const u8,
    // stat: std.Io.File.Stat,

};

const Entries = btree.BPlusTree([]const u8, Entry, entryOrder);

fn entryOrder(a: []const u8, b: []const u8) std.math.Order {
    return std.mem.order(u8, a, b);
}

const Snapshot = @This();

entries: Entries,
// id_to_path: std.HashMap(u64, []const u8),
// id_to_abs_path: std.HashMap(u64, []const u8),

next_id: u64,

pub fn init(self: *Snapshot, gpa: Allocator) !void {
    self.* = .{
        .entries = undefined,
        .next_id = 0,
    };

    try self.entries.init(gpa);
}

pub fn insert(self: *Snapshot, gpa: Allocator, path: []const u8) !void {
    try self.entries.insert(gpa, path, .{ .id = self.next_id });
    self.next_id += 1;
}

pub fn deinit(self: *Snapshot, gpa: Allocator) void {
    self.entries.deinit(gpa);
    // self.id_to_abs_path.deinit();
    // self.id_to_path.deinit();
}
