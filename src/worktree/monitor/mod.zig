const std = @import("std");
const xev = @import("../../global.zig").xev;
const Allocator = std.mem.Allocator;
const Worktree = @import("../mod.zig");

pub const Monitor = @This();

alloc: Allocator,
watchers: std.AutoHashMap(usize, xev.Watcher),
worktree: *Worktree,

pub fn init(alloc: Allocator, worktree: *Worktree) !Monitor {
    return .{ .watchers = .init(alloc), .alloc = alloc, .worktree = worktree };
}

pub fn deinit(self: *Monitor) void {
    self.watchers.deinit();
}
