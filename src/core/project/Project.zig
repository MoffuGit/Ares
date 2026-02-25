const std = @import("std");
const Worktree = @import("../worktree/mod.zig").Worktree;
const BufferStore = @import("../buffer/BufferStore.zig");
const Monitor = @import("../monitor/mod.zig");
const Io = @import("../io/mod.zig");

const Project = @This();

worktree: *Worktree,
buffer_store: BufferStore,

selected_entry: ?u64 = null,

pub fn create(alloc: std.mem.Allocator, monitor: *Monitor, io: *Io, abs_path: []const u8) !*Project {
    const project = try alloc.create(Project);
    errdefer alloc.destroy(project);

    const worktree = try Worktree.create(abs_path, monitor, alloc);
    errdefer worktree.destroy();

    project.* = .{
        .worktree = worktree,
        .buffer_store = BufferStore.init(alloc, io),
    };

    return project;
}

pub fn destroy(self: *Project, alloc: std.mem.Allocator) void {
    self.buffer_store.deinit();
    self.worktree.destroy();
    alloc.destroy(self);
}
