const std = @import("std");
const Worktree = @import("../worktree/mod.zig").Worktree;
const Context = @import("../app/mod.zig").Context;

const Project = @This();

ctx: *Context,
worktree: *Worktree,

pub fn create(alloc: std.mem.Allocator, abs_path: []const u8, ctx: *Context) !*Project {
    const project = try alloc.create(Project);
    errdefer alloc.destroy(project);

    const worktree = try Worktree.create(abs_path, alloc, &ctx.app.loop);
    errdefer worktree.destroy();

    project.* = .{
        .ctx = ctx,
        .worktree = worktree,
    };

    return project;
}

pub fn destroy(self: *Project, alloc: std.mem.Allocator) void {
    self.worktree.destroy();
    alloc.destroy(self);
}
