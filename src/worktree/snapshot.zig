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
    const n = @min(a.len, b.len);
    for (a[0..n], b[0..n]) |a_elem, b_elem| {
        switch (std.math.order(a_elem, b_elem)) {
            .eq => continue,
            .lt => return .lt,
            .gt => return .gt,
        }
    }
    return std.math.order(a.len, b.len);
}

const Snapshot = @This();

entries: Entries,
// id_to_path: std.HashMap(u64, []const u8),
id_to_abs_path: std.AutoHashMapUnmanaged(u64, []const u8),

next_id: u64,

pub fn init(self: *Snapshot, gpa: Allocator) !void {
    self.* = .{
        .entries = undefined,
        .id_to_abs_path = .empty,
        .next_id = 0,
    };

    try self.entries.init(gpa);
}

pub fn insert(self: *Snapshot, gpa: Allocator, path: []const u8) !void {
    _ = try self.entries.insert(gpa, path, .{ .id = self.next_id });
    _ = try self.id_to_abs_path.put(gpa, self.next_id, path);
    self.next_id += 1;
}

pub fn deinit(self: *Snapshot, gpa: Allocator) void {
    self.entries.deinit(gpa);
    self.id_to_abs_path.deinit(gpa);
    // self.id_to_path.deinit();
}
