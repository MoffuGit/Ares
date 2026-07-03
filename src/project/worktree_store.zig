const std = @import("std");
const Allocator = std.mem.Allocator;
const App = @import("../app.zig");
const Context = App.Context;
const Worktree = @import("../worktree.zig");

const WorktreeStore = @This();

worktrees: std.ArrayList(Worktree),

pub fn init(self: *WorktreeStore, _: Context(WorktreeStore)) !void {
    self.* = .{
        .worktrees = .empty,
    };
}

pub fn deinit(self: *WorktreeStore) void {
    _ = self;
}
