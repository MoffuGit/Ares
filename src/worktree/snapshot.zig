const std = @import("std");
const datastruct = @import("../datastruct.zig");
const btree = datastruct.btree;
const Allocator = std.mem.Allocator;

pub const Entry = struct {
    id: u64,
    path: []const u8,
};

const Entries = btree.BPlusTree([]const u8, Entry, entryOrder);

//Source: https://github.com/dmtrKovalenko/zlob/blob/main/src/sorting.zig
//License: [licenses/ZLOB]
fn entryOrder(a: []const u8, b: []const u8) std.math.Order {
    const min_len = @min(a.len, b.len);
    const vec_len = std.simd.suggestVectorLength(u8) orelse 16;

    if (min_len >= vec_len) {
        const Vec = @Vector(vec_len, u8);
        const MaskInt = std.meta.Int(.unsigned, vec_len);
        const all_ones: MaskInt = @as(MaskInt, 0) -% 1;

        var i: usize = 0;
        while (i + vec_len <= min_len) : (i += vec_len) {
            const a_vec: Vec = a[i..][0..vec_len].*;
            const b_vec: Vec = b[i..][0..vec_len].*;
            const eq = a_vec == b_vec;
            const mask = @as(MaskInt, @bitCast(eq));

            if (mask != all_ones) {
                const first_diff = @ctz(~mask);
                const a_byte = a[i + first_diff];
                const b_byte = b[i + first_diff];
                if (a_byte < b_byte) return .lt;
                return .gt;
            }
        }
        for (a[i..min_len], b[i..min_len]) |ab, bb| {
            if (ab < bb) return .lt;
            if (ab > bb) return .gt;
        }
    } else {
        for (a[0..min_len], b[0..min_len]) |ab, bb| {
            if (ab < bb) return .lt;
            if (ab > bb) return .gt;
        }
    }

    return std.math.order(a.len, b.len);
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
