const std = @import("std");
const Allocator = std.mem.Allocator;
const worktreepkg = @import("mod.zig");
const Entries = worktreepkg.Entries;

pub const Snapshot = @This();

mutex: std.Thread.Mutex = .{},
alloc: Allocator,

entries: Entries,

pub fn init(alloc: Allocator) !Snapshot {
    const entries = try Entries.init(alloc);

    return .{ .alloc = alloc, .entries = entries };
}

pub fn deinit(self: *Snapshot) void {
    var iter = self.entries.iter();
    while (iter.next()) |entry| {
        self.alloc.free(entry.value.path);
    }
    self.entries.deinit();
}
