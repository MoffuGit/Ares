const std = @import("std");
const Allocator = std.mem.Allocator;
const Worktree = @import("../mod.zig");

pub const Scanner = @This();

alloc: Allocator,
worktree: *Worktree,

pub fn init(alloc: Allocator, worktree: *Worktree) !Scanner {
    return .{ .alloc = alloc, .worktree = worktree };
}

pub fn deinit(self: *Scanner) void {
    _ = self;
}
