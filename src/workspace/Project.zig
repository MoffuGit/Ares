const std = @import("std");
const vaxis = @import("vaxis");
const Worktree = @import("../worktree/mod.zig").Worktree;
const app_mod = @import("../app/mod.zig");
const Context = app_mod.Context;
const BufferStore = @import("../buffer/BufferStore.zig");

const Project = @This();

ctx: *Context,
worktree: *Worktree,
buffer_store: BufferStore,

selected_entry: ?u64 = null,

pub fn create(alloc: std.mem.Allocator, abs_path: []const u8, ctx: *Context) !*Project {
    const project = try alloc.create(Project);
    errdefer alloc.destroy(project);

    const worktree = try Worktree.create(abs_path, alloc, &ctx.app.loop);
    errdefer worktree.destroy();

    project.* = .{
        .ctx = ctx,
        .worktree = worktree,
        .buffer_store = BufferStore.init(alloc, &project.worktree.io, &ctx.app.loop),
    };

    return project;
}

pub fn destroy(self: *Project, alloc: std.mem.Allocator) void {
    self.buffer_store.deinit();
    self.worktree.destroy();
    alloc.destroy(self);
}
