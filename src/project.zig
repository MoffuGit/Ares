const std = @import("std");
const Allocator = std.mem.Allocator;

const Worktree = @import("worktree.zig");

const WorktreeStore = std.ArrayList(Worktree);

pub const Project = @This();

worktrees: WorktreeStore,

pub fn init(self: *Project) !void {
    self.* = .{
        .worktrees = .empty,
    };
}

pub fn deinit(self: *Project, gpa: Allocator) void {
    self.worktrees.deinit(gpa);
}
