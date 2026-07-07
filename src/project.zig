const std = @import("std");
const Allocator = std.mem.Allocator;
const App = @import("app.zig");
const Entity = App.Entity;
const Context = App.Context;
const WorktreeStore = @import("project/worktree_store.zig");

const Project = @This();

arena: Allocator,
worktree_store: Entity(WorktreeStore),

pub fn init(self: *Project, ctx: Context(Project), arena: Allocator) !void {
    self.* = .{
        .arena = arena,
        .worktree_store = try .new(ctx.app, .{}),
    };
}

pub fn drop(self: *Project) void {
    self.worktree_store.drop();
}
