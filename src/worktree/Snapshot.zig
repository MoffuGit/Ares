const std = @import("std");
const Allocator = std.mem.Allocator;
const worktreepkg = @import("mod.zig");
const Entries = worktreepkg.Entries;

pub const Snapshot = @This();

mutex: std.Thread.Mutex = .{},
alloc: Allocator,
version: std.atomic.Value(u64) = .{ .raw = 0 },
next_id: std.atomic.Value(u64) = .{ .raw = 1 },

entries: Entries,
id_to_path: std.AutoHashMap(u64, []const u8),

pub fn init(alloc: Allocator) !Snapshot {
    const entries = try Entries.init(alloc);

    return .{
        .alloc = alloc,
        .entries = entries,
        .id_to_path = std.AutoHashMap(u64, []const u8).init(alloc),
    };
}

pub fn deinit(self: *Snapshot) void {
    var it = self.entries.iter();
    while (it.next()) |entry| {
        self.alloc.free(entry.key);
    }
    self.entries.deinit();
    self.id_to_path.deinit();
}
